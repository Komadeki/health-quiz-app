import 'product_catalog.dart';

/// Cached proof used for offline access decisions.
class EntitlementSnapshot {
  EntitlementSnapshot({
    Iterable<String> ownedProductIds = const [],
    Iterable<String> selectedBundleDeckIds = const [],
  })  : ownedProductIds = Set.unmodifiable(ownedProductIds),
        selectedBundleDeckIds = Set.unmodifiable(
          selectedBundleDeckIds.map((id) => id.toLowerCase()),
        );

  final Set<String> ownedProductIds;
  final Set<String> selectedBundleDeckIds;

  EntitlementSnapshot mergedWith(EntitlementSnapshot other) {
    return EntitlementSnapshot(
      ownedProductIds: {...ownedProductIds, ...other.ownedProductIds},
      selectedBundleDeckIds: {
        ...selectedBundleDeckIds,
        ...other.selectedBundleDeckIds,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is EntitlementSnapshot &&
      _setEquals(other.ownedProductIds, ownedProductIds) &&
      _setEquals(other.selectedBundleDeckIds, selectedBundleDeckIds);

  @override
  int get hashCode => Object.hash(
        Object.hashAllUnordered(ownedProductIds),
        Object.hashAllUnordered(selectedBundleDeckIds),
      );
}

/// Persistence is supplied by the app shell; the quiz engine knows no plugin.
abstract interface class EntitlementCache {
  Future<EntitlementSnapshot> load();

  /// Adds verified entitlements without removing previously cached access.
  Future<EntitlementSnapshot> merge(EntitlementSnapshot additions);
}

/// Pure content access rules for one monetization architecture.
abstract interface class EntitlementPolicy {
  bool canAccessContent({
    required String deckId,
    required bool isPremium,
    required EntitlementSnapshot snapshot,
    required ProductCatalog catalog,
  });

  bool canAccessFeature({
    required String featureKey,
    required EntitlementSnapshot snapshot,
    required ProductCatalog catalog,
  });
}

/// Reproduces the health app's individual, five-pack, bundle-all and Pro rules.
class LegacyDeckBundleEntitlementPolicy implements EntitlementPolicy {
  const LegacyDeckBundleEntitlementPolicy();

  static const _proFeatures = {
    'review_test',
    'review_cards',
    'reminder',
  };

  @override
  bool canAccessContent({
    required String deckId,
    required bool isPremium,
    required EntitlementSnapshot snapshot,
    required ProductCatalog catalog,
  }) {
    if (!isPremium) return true;

    final normalizedDeckId = deckId.toLowerCase();
    final individualProductId = catalog.productIdForDeck(normalizedDeckId);
    if (individualProductId != null &&
        snapshot.ownedProductIds.contains(individualProductId)) {
      return true;
    }

    final bundleAllProductId = catalog.bundleAllProductId;
    if (bundleAllProductId != null &&
        snapshot.ownedProductIds.contains(bundleAllProductId)) {
      return true;
    }

    // Existing health gates trust the persisted selection itself. Keep that
    // compatibility even if the separate five-pack flag is missing.
    return snapshot.selectedBundleDeckIds.contains(normalizedDeckId);
  }

  @override
  bool canAccessFeature({
    required String featureKey,
    required EntitlementSnapshot snapshot,
    required ProductCatalog catalog,
  }) {
    final proProductId = catalog.proProductId;
    return proProductId != null &&
        snapshot.ownedProductIds.contains(proProductId) &&
        _proFeatures.contains(featureKey);
  }
}

/// Free cards remain available; one recognized product unlocks premium cards.
class SingleFullUnlockEntitlementPolicy implements EntitlementPolicy {
  const SingleFullUnlockEntitlementPolicy();

  @override
  bool canAccessContent({
    required String deckId,
    required bool isPremium,
    required EntitlementSnapshot snapshot,
    required ProductCatalog catalog,
  }) {
    if (!isPremium) return true;
    final fullUnlockProductId = catalog.fullUnlockProductId;
    return fullUnlockProductId != null &&
        snapshot.ownedProductIds.contains(fullUnlockProductId);
  }

  @override
  bool canAccessFeature({
    required String featureKey,
    required EntitlementSnapshot snapshot,
    required ProductCatalog catalog,
  }) {
    return false;
  }
}

bool _setEquals<T>(Set<T> left, Set<T> right) =>
    left.length == right.length && left.containsAll(right);
