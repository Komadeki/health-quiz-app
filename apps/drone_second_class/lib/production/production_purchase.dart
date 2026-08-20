import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:quiz_engine/quiz_engine.dart' as engine;

abstract interface class DronePurchaseGateway
    implements engine.PurchaseGateway {
  void startListening();
  Future<void> dispose();
}

final class StoreDronePurchaseGateway implements DronePurchaseGateway {
  StoreDronePurchaseGateway({InAppPurchase? inAppPurchase})
      : _inAppPurchase = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _inAppPurchase;
  final _results = StreamController<engine.PurchaseResult>.broadcast();
  final _pendingCompletions = <String, PurchaseDetails>{};
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  final _products = <String, ProductDetails>{};
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
      Set<String> productIds) async {
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

  String _newEventId() => 'drone-store-${_nextEventId++}';

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
