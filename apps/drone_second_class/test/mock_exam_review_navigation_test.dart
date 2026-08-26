import 'package:drone_second_class/generated/app_manifest.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'production_test_support.dart';

void main() {
  MemoryEntitlementCache fullUnlockCache() {
    final productId = GeneratedAppManifest
        .definition.monetization.productCatalog.fullUnlockProductId!;
    return MemoryEntitlementCache()
      ..value = EntitlementSnapshot(ownedProductIds: {productId});
  }

  testWidgets('full unlock hero describes available questions', (tester) async {
    final controller = createProductionController(
      entitlementCache: fullUnlockCache(),
    );
    await controller.initialize();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      QualificationProductionApp(
        definition: GeneratedAppManifest.definition,
        controller: controller,
      ),
    );

    final total = controller.bank!.cards.length;
    expect(find.text('全$total問を利用できます'), findsOneWidget);
    expect(find.text('全$total問を収録'), findsNothing);
  });

  test(
    'reviewed mock position and later answers remain resumable after reload',
    () async {
      final store = MemoryQualificationSessionStore();
      final repository = InMemoryLearningRepository();
      final cache = fullUnlockCache();
      final firstController = QualificationProductionController(
        definition: GeneratedAppManifest.definition,
        bankLoader: FixedProductionBankLoader(loadProductionBank()),
        sessionStore: store,
        learningRepository: repository,
        purchaseGateway: FakeProductionPurchaseGateway(),
        entitlementCache: cache,
        randomizer: const IdentityQuestionRandomizer(),
      );
      await firstController.initialize();
      expect(await firstController.startMockExam(), isTrue);
      expect(
        await firstController.commitAnswer(
          firstController.currentCard!.answerIndex,
        ),
        isTrue,
      );
      expect(await firstController.advance(), isTrue);
      expect(
        await firstController.commitAnswer(
          firstController.currentCard!.answerIndex,
        ),
        isTrue,
      );
      expect(await firstController.moveToPreviousMockQuestion(), isTrue);
      expect(firstController.activeSession!.currentIndex, 0);
      expect(firstController.activeSession!.committedResponses.length, 2);
      firstController.dispose();

      final secondController = QualificationProductionController(
        definition: GeneratedAppManifest.definition,
        bankLoader: FixedProductionBankLoader(loadProductionBank()),
        sessionStore: store,
        learningRepository: repository,
        purchaseGateway: FakeProductionPurchaseGateway(),
        entitlementCache: cache,
        randomizer: const IdentityQuestionRandomizer(),
      );
      await secondController.initialize();
      addTearDown(secondController.dispose);

      expect(secondController.activeSession, isNotNull);
      expect(secondController.activeSession!.currentIndex, 0);
      expect(secondController.activeSession!.committedResponses.length, 2);
    },
  );
}
