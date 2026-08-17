import 'dart:async';

import 'package:quiz_engine/quiz_engine.dart';
import 'package:test/test.dart';

const _legacyCatalog = ProductCatalog(
  deckProducts: [
    DeckProduct(deckId: 'deck_m01', productId: 'deck_m01_unlock'),
    DeckProduct(deckId: 'deck_m02', productId: 'deck_m02_unlock'),
    DeckProduct(deckId: 'deck_m03', productId: 'deck_m03_unlock'),
  ],
  bundle5ProductId: 'bundle_5decks_unlock',
  bundleAllProductId: 'bundle_all_unlock',
  proProductId: 'pro_upgrade',
);

const _legacyDefinition = MonetizationDefinition(
  architecture: PurchaseArchitecture.legacyDeckBundles,
  productCatalog: _legacyCatalog,
  entitlementPolicy: LegacyDeckBundleEntitlementPolicy(),
);

const _singleUnlockCatalog = ProductCatalog(
  fullUnlockProductId: 'fixture_full_unlock',
);

const _singleUnlockDefinition = MonetizationDefinition(
  architecture: PurchaseArchitecture.singleFullUnlock,
  productCatalog: _singleUnlockCatalog,
  entitlementPolicy: SingleFullUnlockEntitlementPolicy(),
);

void main() {
  group('legacy health entitlement policy', () {
    final policy = _legacyDefinition.entitlementPolicy;

    bool canAccess(
      String deckId,
      EntitlementSnapshot snapshot,
    ) {
      return policy.canAccessContent(
        deckId: deckId,
        isPremium: true,
        snapshot: snapshot,
        catalog: _legacyDefinition.productCatalog,
      );
    }

    test('individual deck unlocks only that deck', () {
      expect(
        _legacyDefinition.architecture,
        PurchaseArchitecture.legacyDeckBundles,
      );
      final snapshot = EntitlementSnapshot(
        ownedProductIds: {'deck_m01_unlock'},
      );

      expect(canAccess('deck_m01', snapshot), isTrue);
      expect(canAccess('deck_m02', snapshot), isFalse);
    });

    test('five-pack selection unlocks selected but not outside deck', () {
      final snapshot = EntitlementSnapshot(
        ownedProductIds: {'bundle_5decks_unlock'},
        selectedBundleDeckIds: {'deck_m02'},
      );

      expect(canAccess('deck_m02', snapshot), isTrue);
      expect(canAccess('deck_m03', snapshot), isFalse);
    });

    test('bundle all unlocks every catalog deck', () {
      final snapshot = EntitlementSnapshot(
        ownedProductIds: {'bundle_all_unlock'},
      );

      for (final deckId in _legacyCatalog.deckIds) {
        expect(canAccess(deckId, snapshot), isTrue);
      }
    });

    test('Pro unlocks only known Pro features', () {
      final snapshot = EntitlementSnapshot(
        ownedProductIds: {'pro_upgrade'},
      );

      expect(canAccess('deck_m01', snapshot), isFalse);
      expect(
        policy.canAccessFeature(
          featureKey: 'review_test',
          snapshot: snapshot,
          catalog: _legacyCatalog,
        ),
        isTrue,
      );
      expect(
        policy.canAccessFeature(
          featureKey: 'unknown',
          snapshot: snapshot,
          catalog: _legacyCatalog,
        ),
        isFalse,
      );
    });

    test('coexisting rights remain additive without broadening access', () {
      final snapshot = EntitlementSnapshot(
        ownedProductIds: {'deck_m01_unlock', 'pro_upgrade'},
        selectedBundleDeckIds: {'deck_m02'},
      );

      expect(canAccess('deck_m01', snapshot), isTrue);
      expect(canAccess('deck_m02', snapshot), isTrue);
      expect(canAccess('deck_m03', snapshot), isFalse);
    });
  });

  group('single full unlock entitlement policy', () {
    const policy = SingleFullUnlockEntitlementPolicy();

    bool canAccess({
      required bool isPremium,
      Iterable<String> ownedProductIds = const [],
    }) {
      return policy.canAccessContent(
        deckId: 'fixture_deck',
        isPremium: isPremium,
        snapshot: EntitlementSnapshot(ownedProductIds: ownedProductIds),
        catalog: _singleUnlockCatalog,
      );
    }

    test('free card without purchase is allowed', () {
      expect(canAccess(isPremium: false), isTrue);
    });

    test('premium card without purchase is denied', () {
      expect(canAccess(isPremium: true), isFalse);
    });

    test('premium card with full unlock is allowed', () {
      expect(
        canAccess(
          isPremium: true,
          ownedProductIds: {'fixture_full_unlock'},
        ),
        isTrue,
      );
    });

    test('unrelated product does not unlock premium content', () {
      expect(
        canAccess(isPremium: true, ownedProductIds: {'unknown_product'}),
        isFalse,
      );
    });
  });

  group('purchase lifecycle', () {
    late _FakePurchaseGateway gateway;
    late _FakeEntitlementCache cache;
    late PurchaseEntitlementCoordinator coordinator;

    setUp(() {
      gateway = _FakePurchaseGateway();
      cache = _FakeEntitlementCache();
      coordinator = PurchaseEntitlementCoordinator(
        gateway: gateway,
        definition: _singleUnlockDefinition,
        cache: cache,
      );
    });

    test('purchase start is limited to catalog products', () async {
      await coordinator.purchase('fixture_full_unlock');
      expect(gateway.purchasedProductIds, ['fixture_full_unlock']);

      expect(
        () => coordinator.purchase('unknown_product'),
        throwsArgumentError,
      );
    });

    test('purchased success grants and caches entitlement', () async {
      final snapshot = await coordinator.handlePurchaseResult(
        const PurchaseResult(
          eventId: 'purchase-1',
          productId: 'fixture_full_unlock',
          status: PurchaseResultStatus.purchased,
          pendingCompletePurchase: true,
        ),
      );

      expect(snapshot.ownedProductIds, {'fixture_full_unlock'});
      expect(cache.mergeCount, 1);
      expect(gateway.completedEventIds, ['purchase-1']);
    });

    test('restored success grants and caches entitlement', () async {
      final snapshot = await coordinator.handlePurchaseResult(
        const PurchaseResult(
          eventId: 'restore-1',
          productId: 'fixture_full_unlock',
          status: PurchaseResultStatus.restored,
        ),
      );

      expect(snapshot.ownedProductIds, {'fixture_full_unlock'});
      expect(cache.mergeCount, 1);
    });

    for (final status in [
      PurchaseResultStatus.pending,
      PurchaseResultStatus.canceled,
      PurchaseResultStatus.error,
    ]) {
      test('$status does not grant or remove an entitlement', () async {
        cache.snapshot = EntitlementSnapshot(
          ownedProductIds: {'previously_cached_product'},
        );
        final snapshot = await coordinator.handlePurchaseResult(
          PurchaseResult(
            eventId: '$status-1',
            productId: 'fixture_full_unlock',
            status: status,
          ),
        );

        expect(snapshot.ownedProductIds, {'previously_cached_product'});
        expect(cache.mergeCount, 0);
      });
    }

    test('restore error preserves existing cached entitlement', () async {
      cache.snapshot = EntitlementSnapshot(
        ownedProductIds: {'fixture_full_unlock'},
      );
      gateway.restoreError = StateError('offline');

      await expectLater(coordinator.restore(), throwsStateError);

      expect(
        (await cache.load()).ownedProductIds,
        {'fixture_full_unlock'},
      );
      expect(cache.mergeCount, 0);
    });

    test('duplicate success is idempotent', () async {
      const result = PurchaseResult(
        eventId: 'duplicate-1',
        productId: 'fixture_full_unlock',
        status: PurchaseResultStatus.purchased,
      );

      final first = await coordinator.handlePurchaseResult(result);
      final second = await coordinator.handlePurchaseResult(result);

      expect(second, first);
      expect(second.ownedProductIds, {'fixture_full_unlock'});
    });

    test('multiple successful events are merged serially', () async {
      coordinator = PurchaseEntitlementCoordinator(
        gateway: gateway,
        definition: _legacyDefinition,
        cache: cache,
      );

      await Future.wait([
        coordinator.handlePurchaseResult(
          const PurchaseResult(
            eventId: 'deck-1',
            productId: 'deck_m01_unlock',
            status: PurchaseResultStatus.restored,
          ),
        ),
        coordinator.handlePurchaseResult(
          const PurchaseResult(
            eventId: 'deck-2',
            productId: 'deck_m02_unlock',
            status: PurchaseResultStatus.restored,
          ),
        ),
      ]);

      expect(
        (await cache.load()).ownedProductIds,
        {'deck_m01_unlock', 'deck_m02_unlock'},
      );
    });

    test('unknown successful product does not grant', () async {
      final snapshot = await coordinator.handlePurchaseResult(
        const PurchaseResult(
          eventId: 'unknown-1',
          productId: 'unknown_product',
          status: PurchaseResultStatus.restored,
        ),
      );

      expect(snapshot.ownedProductIds, isEmpty);
      expect(cache.mergeCount, 0);
    });
  });
}

class _FakePurchaseGateway implements PurchaseGateway {
  final _results = StreamController<PurchaseResult>.broadcast();
  final purchasedProductIds = <String>[];
  final completedEventIds = <String>[];
  Object? restoreError;

  @override
  Stream<PurchaseResult> get purchaseResults => _results.stream;

  @override
  Future<void> complete(PurchaseResult result) async {
    completedEventIds.add(result.eventId);
  }

  @override
  Future<void> purchase(String productId) async {
    purchasedProductIds.add(productId);
  }

  @override
  Future<ProductQueryResult> queryProducts(Set<String> productIds) async {
    return ProductQueryResult(storeAvailable: true);
  }

  @override
  Future<void> restore() async {
    final error = restoreError;
    if (error != null) throw error;
  }
}

class _FakeEntitlementCache implements EntitlementCache {
  EntitlementSnapshot snapshot = EntitlementSnapshot();
  var mergeCount = 0;

  @override
  Future<EntitlementSnapshot> load() async => snapshot;

  @override
  Future<EntitlementSnapshot> merge(EntitlementSnapshot additions) async {
    mergeCount++;
    return snapshot = snapshot.mergedWith(additions);
  }
}
