import 'package:drone_second_class/generated/app_manifest.g.dart';
import 'package:drone_second_class/production/production_app.dart';
import 'package:flutter/material.dart';
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

  testWidgets(
    'Drone mock exam allows previous-question review and answer revision',
    (tester) async {
      final controller = createProductionController(
        entitlementCache: fullUnlockCache(),
      );
      await controller.initialize();
      expect(await controller.startMockExam(), isTrue);
      addTearDown(controller.dispose);

      await tester.pumpWidget(DroneProductionApp(controller: controller));

      final firstCard = controller.currentCard!;
      final firstChoice = firstCard.answerIndex == 0 ? 1 : 0;
      await tester.tap(find.byKey(Key('choice-$firstChoice')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('commit-answer')));
      await tester.pump();

      expect(controller.currentResponse, firstChoice);
      expect(find.byKey(const Key('mock-answer-committed')), findsOneWidget);
      expect(find.byKey(const Key('answer-feedback')), findsNothing);
      expect(find.text('解説（Explanation）'), findsNothing);
      expect(
        tester
            .widget<RadioListTile<int>>(find.byKey(Key('choice-$firstChoice')))
            .enabled,
        isTrue,
      );

      await tester.tap(find.byKey(const Key('next-question')));
      await tester.pump();
      final secondChoice = controller.currentCard!.answerIndex;
      await tester.tap(find.byKey(Key('choice-$secondChoice')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('commit-answer')));
      await tester.pump();

      expect(find.byKey(const Key('previous-question')), findsOneWidget);
      expect(find.byKey(const Key('submit-mock-exam')), findsOneWidget);
      await tester.tap(find.byKey(const Key('previous-question')));
      await tester.pump();
      expect(controller.activeSession!.currentIndex, 0);

      final revisedChoice = firstChoice == 0 ? 1 : 0;
      await tester.tap(find.byKey(Key('choice-$revisedChoice')));
      await tester.pump();
      expect(find.byKey(const Key('revise-answer')), findsOneWidget);
      expect(
        find.byKey(const Key('pending-answer-change')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('revise-answer')));
      await tester.pump();

      expect(controller.currentResponse, revisedChoice);
      expect(find.byKey(const Key('answer-feedback')), findsNothing);
      expect(controller.events.length, 2);
    },
  );

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
