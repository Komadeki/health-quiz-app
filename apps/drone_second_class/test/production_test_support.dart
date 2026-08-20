import 'dart:async';
import 'dart:io';

import 'package:drone_second_class/production/production_bank.dart';
import 'package:drone_second_class/production/production_persistence.dart';
import 'package:drone_second_class/production/production_purchase.dart';
import 'package:drone_second_class/production/production_session.dart';
import 'package:quiz_engine/quiz_engine.dart';

DroneProductionBank loadProductionBank() {
  return DroneProductionBank.decode(
    File('assets/question_bank/drone_second_class_bank.json')
        .readAsStringSync(),
  );
}

final class FixedDroneBankLoader implements DroneBankLoader {
  FixedDroneBankLoader(this.bank);

  final DroneProductionBank bank;

  @override
  Future<DroneProductionBank> load() async => bank;
}

final class MemoryDroneSessionStore implements DroneSessionStore {
  DroneQuizSession? session;
  var saveCount = 0;
  var clearCount = 0;

  @override
  Future<DroneQuizSession?> load() async => session;

  @override
  Future<void> save(DroneQuizSession value) async {
    saveCount += 1;
    session = DroneQuizSession.decode(value.encode());
  }

  @override
  Future<void> clear() async {
    clearCount += 1;
    session = null;
  }
}

final class MemoryDroneEntitlementCache implements EntitlementCache {
  MemoryDroneEntitlementCache([Iterable<String> productIds = const []])
      : snapshot = EntitlementSnapshot(ownedProductIds: productIds);

  EntitlementSnapshot snapshot;

  @override
  Future<EntitlementSnapshot> load() async => snapshot;

  @override
  Future<EntitlementSnapshot> merge(EntitlementSnapshot additions) async {
    return snapshot = snapshot.mergedWith(additions);
  }
}

final class FakeDronePurchaseGateway implements DronePurchaseGateway {
  FakeDronePurchaseGateway({
    this.storeAvailable = true,
    this.includeProduct = true,
    this.purchaseStatus,
    this.restoreStatus,
  });

  final bool storeAvailable;
  final bool includeProduct;
  PurchaseResultStatus? purchaseStatus;
  PurchaseResultStatus? restoreStatus;
  final purchasedProductIds = <String>[];
  final completedEventIds = <String>[];
  final _results = StreamController<PurchaseResult>.broadcast(sync: true);
  var _sequence = 0;

  @override
  Stream<PurchaseResult> get purchaseResults => _results.stream;

  @override
  void startListening() {}

  @override
  Future<ProductQueryResult> queryProducts(Set<String> productIds) async {
    return ProductQueryResult(
      storeAvailable: storeAvailable,
      products: includeProduct && storeAvailable
          ? productIds.map(
              (id) => PurchaseProduct(
                id: id,
                title: 'Full unlock',
                description: 'All questions',
                price: '¥1,000',
              ),
            )
          : const [],
      notFoundProductIds: includeProduct ? const [] : productIds,
    );
  }

  @override
  Future<void> purchase(String productId) async {
    purchasedProductIds.add(productId);
    final status = purchaseStatus;
    if (status != null) emit(productId: productId, status: status);
  }

  @override
  Future<void> restore() async {
    final status = restoreStatus;
    if (status != null) {
      emit(
        productId: 'drone_second_class_full_unlock',
        status: status,
      );
    }
  }

  void emit({required String productId, required PurchaseResultStatus status}) {
    _results.add(
      PurchaseResult(
        eventId: 'fake-${_sequence++}',
        productId: productId,
        status: status,
      ),
    );
  }

  @override
  Future<void> complete(PurchaseResult result) async {
    completedEventIds.add(result.eventId);
  }

  @override
  Future<void> dispose() async {
    await _results.close();
  }
}

Future<void> settleAsyncEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
