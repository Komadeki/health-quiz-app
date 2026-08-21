import 'dart:async';
import 'dart:io';

import 'package:drone_second_class/generated/app_manifest.g.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

QualificationBank loadProductionBank() {
  return QualificationBank.decode(
    File(
      'assets/question_bank/drone_second_class_bank.json',
    ).readAsStringSync(),
    GeneratedAppManifest.definition,
  );
}

final class FixedProductionBankLoader implements QualificationBankLoader {
  FixedProductionBankLoader(this.bank);

  final QualificationBank bank;

  @override
  Future<QualificationBank> load() async => bank;
}

final class FakeProductionPurchaseGateway implements LifecyclePurchaseGateway {
  final _results = StreamController<PurchaseResult>.broadcast(sync: true);
  var sequence = 0;

  @override
  Stream<PurchaseResult> get purchaseResults => _results.stream;

  @override
  void startListening() {}

  @override
  Future<ProductQueryResult> queryProducts(Set<String> productIds) async {
    return ProductQueryResult(
      storeAvailable: true,
      products: [
        for (final id in productIds)
          PurchaseProduct(
            id: id,
            title: 'Full unlock',
            description: 'All questions',
            price: '¥1,000',
          ),
      ],
    );
  }

  @override
  Future<void> purchase(String productId) async {
    _results.add(
      PurchaseResult(
        eventId: 'purchase-${sequence++}',
        productId: productId,
        status: PurchaseResultStatus.purchased,
      ),
    );
  }

  @override
  Future<void> restore() async {}

  @override
  Future<void> complete(PurchaseResult result) async {}

  @override
  Future<void> dispose() => _results.close();
}

QualificationProductionController createProductionController({
  MemoryEntitlementCache? entitlementCache,
}) {
  return QualificationProductionController(
    definition: GeneratedAppManifest.definition,
    bankLoader: FixedProductionBankLoader(loadProductionBank()),
    sessionStore: MemoryQualificationSessionStore(),
    learningRepository: InMemoryLearningRepository(),
    purchaseGateway: FakeProductionPurchaseGateway(),
    entitlementCache: entitlementCache ?? MemoryEntitlementCache(),
    randomizer: const IdentityQuestionRandomizer(),
  );
}
