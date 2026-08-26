import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'generated/app_manifest.g.dart';
import 'production/production_app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DroneCaptureBootstrap());
}

final class DroneCaptureBootstrap extends StatefulWidget {
  const DroneCaptureBootstrap({super.key});

  @override
  State<DroneCaptureBootstrap> createState() => _DroneCaptureBootstrapState();
}

final class _DroneCaptureBootstrapState extends State<DroneCaptureBootstrap> {
  late final QualificationProductionController controller;

  @override
  void initState() {
    super.initState();
    final definition = GeneratedAppManifest.definition;
    final productId = definition.monetization.productCatalog.fullUnlockProductId!;
    controller = QualificationProductionController(
      definition: definition,
      bankLoader: AssetQualificationBankLoader(
        definition: definition,
        assetBundle: rootBundle,
      ),
      sessionStore: MemoryQualificationSessionStore(),
      learningRepository: InMemoryLearningRepository(),
      purchaseGateway: CapturePurchaseGateway(),
      entitlementCache: MemoryEntitlementCache(),
      randomizer: const IdentityQuestionRandomizer(),
    )..initialize();
    // Keep the product ID referenced so capture setup fails fast if monetization changes.
    assert(productId == 'drone_second_class_full_unlock');
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return QualificationProductionApp(
      definition: GeneratedAppManifest.definition,
      controller: controller,
      homeSupplementBuilder: buildDroneHomeSupplement,
    );
  }
}

final class CapturePurchaseGateway implements LifecyclePurchaseGateway {
  final StreamController<PurchaseResult> _results =
      StreamController<PurchaseResult>.broadcast(sync: true);

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
            title: '全386問を解放',
            description: '全386問と模擬試験を利用できます。',
            // The price is deliberately not used in the captured screens.
            price: '¥1,000',
          ),
      ],
    );
  }

  @override
  Future<void> purchase(String productId) async {}

  @override
  Future<void> restore() async {}

  @override
  Future<void> complete(PurchaseResult result) async {}

  @override
  Future<void> dispose() async {
    await _results.close();
  }
}
