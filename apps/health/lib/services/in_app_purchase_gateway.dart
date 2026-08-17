import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:quiz_engine/quiz_engine.dart' as engine;

/// Health app adapter that keeps the store plugin outside quiz_engine.
class InAppPurchaseGateway implements engine.PurchaseGateway {
  InAppPurchaseGateway({InAppPurchase? inAppPurchase})
      : _iap = inAppPurchase ?? InAppPurchase.instance;

  final InAppPurchase _iap;
  final StreamController<engine.PurchaseResult> _results =
      StreamController<engine.PurchaseResult>.broadcast();
  final Map<String, PurchaseDetails> _pendingCompletions = {};

  StreamSubscription<List<PurchaseDetails>>? _nativeSubscription;
  var _nextEventId = 0;

  final Map<String, ProductDetails> products = {};

  @override
  Stream<engine.PurchaseResult> get purchaseResults => _results.stream;

  void startListening() {
    if (_nativeSubscription != null) return;
    _nativeSubscription = _iap.purchaseStream.listen(
      _onNativePurchases,
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
    final available = await _iap.isAvailable();
    if (!available) {
      return engine.ProductQueryResult(storeAvailable: false);
    }

    final response = await _iap.queryProductDetails(productIds);
    products
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
    final product = products[productId];
    if (product == null) {
      throw StateError('Product not loaded: $productId');
    }
    await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  @override
  Future<void> restore() => _iap.restorePurchases();

  @override
  Future<void> complete(engine.PurchaseResult result) async {
    final purchase = _pendingCompletions.remove(result.eventId);
    if (purchase != null && purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }
  }

  Future<void> dispose() async {
    await _nativeSubscription?.cancel();
    _nativeSubscription = null;
    await _results.close();
  }

  void _onNativePurchases(List<PurchaseDetails> purchases) {
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

  String _newEventId() => 'store-event-${_nextEventId++}';

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
