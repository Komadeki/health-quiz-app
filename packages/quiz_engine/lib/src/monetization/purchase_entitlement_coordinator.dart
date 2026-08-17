import 'dart:async';

import 'entitlement.dart';
import 'monetization_definition.dart';
import 'purchase_gateway.dart';

/// Applies verified store results to a non-destructive entitlement cache.
class PurchaseEntitlementCoordinator {
  PurchaseEntitlementCoordinator({
    required PurchaseGateway gateway,
    required MonetizationDefinition definition,
    required EntitlementCache cache,
  })  : _gateway = gateway,
        _definition = definition,
        _cache = cache;

  final PurchaseGateway _gateway;
  final MonetizationDefinition _definition;
  final EntitlementCache _cache;

  EntitlementSnapshot? _snapshot;
  Future<void> _resultQueue = Future.value();

  EntitlementSnapshot? get snapshot => _snapshot;

  Future<EntitlementSnapshot> loadCachedEntitlements() async {
    return _snapshot = await _cache.load();
  }

  Future<ProductQueryResult> queryProducts() {
    return _gateway.queryProducts(_definition.productCatalog.productIds);
  }

  Future<void> purchase(String productId) {
    if (!_definition.productCatalog.recognizes(productId)) {
      throw ArgumentError.value(productId, 'productId', 'Unknown product');
    }
    return _gateway.purchase(productId);
  }

  Future<void> restore() => _gateway.restore();

  Future<EntitlementSnapshot> handlePurchaseResult(
    PurchaseResult result,
  ) {
    final completer = Completer<EntitlementSnapshot>();
    _resultQueue = _resultQueue.then((_) async {
      try {
        completer.complete(await _handlePurchaseResult(result));
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<EntitlementSnapshot> _handlePurchaseResult(
    PurchaseResult result,
  ) async {
    var current = _snapshot ?? await _cache.load();
    try {
      final grantsEntitlement =
          result.status == PurchaseResultStatus.purchased ||
              result.status == PurchaseResultStatus.restored;
      if (grantsEntitlement &&
          _definition.productCatalog.recognizes(result.productId)) {
        current = await _cache.merge(
          EntitlementSnapshot(ownedProductIds: {result.productId}),
        );
      }
      return _snapshot = current;
    } finally {
      if (result.pendingCompletePurchase &&
          result.status != PurchaseResultStatus.pending) {
        await _gateway.complete(result);
      }
    }
  }
}
