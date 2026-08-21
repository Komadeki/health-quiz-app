import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:quiz_engine/quiz_engine.dart' as engine;
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class LifecyclePurchaseGateway
    implements engine.PurchaseGateway {
  void startListening();
  Future<void> dispose();
}

final class StorePurchaseGateway implements LifecyclePurchaseGateway {
  StorePurchaseGateway({InAppPurchase? inAppPurchase})
      : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _inAppPurchase;
  final _results = StreamController<engine.PurchaseResult>.broadcast();
  final _pendingCompletions = <String, PurchaseDetails>{};
  final _products = <String, ProductDetails>{};
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  var _nextEventId = 0;

  @override
  Stream<engine.PurchaseResult> get purchaseResults => _results.stream;

  @override
  void startListening() {
    if (_subscription != null) return;
    _subscription = _inAppPurchase.purchaseStream.listen(
      _onPurchases,
      onError: (Object error, StackTrace stackTrace) {
        _results.add(
          engine.PurchaseResult(
            eventId: _newEventId(),
            productId: '',
            status: engine.PurchaseResultStatus.error,
            errorMessage: '$error',
          ),
        );
      },
    );
  }

  @override
  Future<engine.ProductQueryResult> queryProducts(
    Set<String> productIds,
  ) async {
    if (!await _inAppPurchase.isAvailable()) {
      return engine.ProductQueryResult(storeAvailable: false);
    }
    final response = await _inAppPurchase.queryProductDetails(productIds);
    _products
      ..clear()
      ..addEntries(
        response.productDetails.map((product) => MapEntry(product.id, product)),
      );
    return engine.ProductQueryResult(
      storeAvailable: true,
      products: response.productDetails.map(
        (product) => engine.PurchaseProduct(
          id: product.id,
          title: product.title,
          description: product.description,
          price: product.price,
        ),
      ),
      notFoundProductIds: response.notFoundIDs,
      errorMessage: response.error?.message,
    );
  }

  @override
  Future<void> purchase(String productId) async {
    final product = _products[productId];
    if (product == null) throw StateError('Product not loaded: $productId');
    await _inAppPurchase.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  @override
  Future<void> restore() => _inAppPurchase.restorePurchases();

  @override
  Future<void> complete(engine.PurchaseResult result) async {
    final purchase = _pendingCompletions.remove(result.eventId);
    if (purchase != null && purchase.pendingCompletePurchase) {
      await _inAppPurchase.completePurchase(purchase);
    }
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _results.close();
  }

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      final eventId = _newEventId();
      if (purchase.pendingCompletePurchase) {
        _pendingCompletions[eventId] = purchase;
      }
      _results.add(
        engine.PurchaseResult(
          eventId: eventId,
          productId: purchase.productID,
          status: _statusOf(purchase.status),
          errorMessage: purchase.error?.message,
          pendingCompletePurchase: purchase.pendingCompletePurchase,
        ),
      );
    }
  }

  String _newEventId() => 'qualification-store-${_nextEventId++}';

  static engine.PurchaseResultStatus _statusOf(PurchaseStatus status) {
    return switch (status) {
      PurchaseStatus.pending => engine.PurchaseResultStatus.pending,
      PurchaseStatus.purchased => engine.PurchaseResultStatus.purchased,
      PurchaseStatus.restored => engine.PurchaseResultStatus.restored,
      PurchaseStatus.canceled => engine.PurchaseResultStatus.canceled,
      PurchaseStatus.error => engine.PurchaseResultStatus.error,
    };
  }
}

final class SharedPreferencesFullUnlockEntitlementCache
    implements engine.EntitlementCache {
  const SharedPreferencesFullUnlockEntitlementCache({
    required this.appKey,
    required this.productId,
  });

  final String appKey;
  final String productId;

  String get _key => 'qualification_factory.$appKey.full_unlock.v1';

  @override
  Future<engine.EntitlementSnapshot> load() async {
    final unlocked =
        (await SharedPreferences.getInstance()).getBool(_key) ?? false;
    return engine.EntitlementSnapshot(
      ownedProductIds: unlocked ? {productId} : const <String>{},
    );
  }

  @override
  Future<engine.EntitlementSnapshot> merge(
    engine.EntitlementSnapshot additions,
  ) async {
    if (additions.ownedProductIds.contains(productId)) {
      await (await SharedPreferences.getInstance()).setBool(_key, true);
    }
    return load();
  }
}

final class MemoryEntitlementCache implements engine.EntitlementCache {
  engine.EntitlementSnapshot value = engine.EntitlementSnapshot();

  @override
  Future<engine.EntitlementSnapshot> load() async => value;

  @override
  Future<engine.EntitlementSnapshot> merge(
    engine.EntitlementSnapshot additions,
  ) async =>
      value = value.mergedWith(additions);
}
