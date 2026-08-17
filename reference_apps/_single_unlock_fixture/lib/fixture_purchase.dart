import 'dart:async';

import 'package:quiz_engine/quiz_engine.dart';

final class FixturePurchaseGateway implements PurchaseGateway {
  final StreamController<PurchaseResult> _results =
      StreamController<PurchaseResult>.broadcast(sync: true);
  var _eventSequence = 0;

  @override
  Stream<PurchaseResult> get purchaseResults => _results.stream;

  @override
  Future<ProductQueryResult> queryProducts(Set<String> productIds) async {
    return ProductQueryResult(
      storeAvailable: true,
      products: productIds
          .map(
            (id) => PurchaseProduct(
              id: id,
              title: 'Fixture full unlock',
              description: 'Deterministic fixture purchase',
              price: 'Fixture',
            ),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<void> purchase(String productId) async {
    _eventSequence += 1;
    _results.add(
      PurchaseResult(
        eventId: 'fixture-purchase-$_eventSequence',
        productId: productId,
        status: PurchaseResultStatus.purchased,
      ),
    );
  }

  @override
  Future<void> restore() async {}

  @override
  Future<void> complete(PurchaseResult result) async {}

  Future<void> dispose() => _results.close();
}

final class InMemoryEntitlementCache implements EntitlementCache {
  EntitlementSnapshot _snapshot = EntitlementSnapshot();

  @override
  Future<EntitlementSnapshot> load() async => _snapshot;

  @override
  Future<EntitlementSnapshot> merge(EntitlementSnapshot additions) async {
    return _snapshot = _snapshot.mergedWith(additions);
  }
}
