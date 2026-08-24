import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'test_support.dart';

void main() {
  Future<QualificationProductionController> createController() async {
    final cache = MemoryEntitlementCache()
      ..value = EntitlementSnapshot(
        ownedProductIds: const {'fixture_full_unlock'},
      );
    final controller = QualificationProductionController(
      definition: fixtureDefinition,
      bankLoader: FixedBankLoader(loadFixtureBank()),
      sessionStore: MemoryQualificationSessionStore(),
      learningRepository: InMemoryLearningRepository(),
      purchaseGateway: FakePurchaseGateway(),
      entitlementCache: cache,
      now: TestClock().call,
      randomizer: const IdentityQuestionRandomizer(),
    );
    await controller.initialize();
    return controller;
  }

  Future<void> completeMixedMock(
    QualificationProductionController controller,
  ) async {
    await controller.startMockExam();
    final firstCard = controller.currentCard!;
    await controller.commitAnswer(firstCard.answerIndex);
    await controller.advance();
    final secondCard = controller.currentCard!;
    final wrongIndex = secondCard.answerIndex == 0 ? 1 : 0;
    await controller.commitAnswer(wrongIndex);
    await controller.advance();
  }

  Future<void> pumpCompact(
    WidgetTester tester,
    QualificationProductionController controller,
  ) async {
    tester.view.physicalSize = const Size(640, 1600);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );
  }

  testWidgets(
    'completed mock review exposes recorded answer correct answer explanation and source read-only',
    (tester) async {
      final controller = await createController();
      addTearDown(controller.dispose);
      await completeMixedMock(controller);
      final result = controller.result!;
      final beforeEvents = List<LearningEventV1>.of(controller.events);
      final completedHistory = controller.history.singleWhere(
        (item) => item.sessionId == result.sessionId,
      );
      final firstQuestionId = completedHistory.questionIds.first;
      final firstCard = controller.bank!.cardsById[firstQuestionId]!;
      final firstEvent = controller.events.singleWhere(
        (event) =>
            event.sessionId == result.sessionId &&
            event.questionId == firstQuestionId,
      );

      await pumpCompact(tester, controller);

      final toggle = find.byKey(const Key('mock-review-toggle'));
      await tester.scrollUntilVisible(toggle, 200);
      await tester.pumpAndSettle();
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      final firstItem = find.byKey(const Key('mock-review-item-0'));
      await tester.scrollUntilVisible(firstItem, 200);
      await tester.pumpAndSettle();
      expect(firstItem, findsOneWidget);
      expect(
        find.text('あなたの回答: ${firstCard.choices[firstEvent.selectedChoice]}'),
        findsOneWidget,
      );
      expect(
        find.text('正解: ${firstCard.choices[firstCard.answerIndex]}'),
        findsOneWidget,
      );
      expect(find.text(firstCard.explanation!), findsOneWidget);
      expect(find.text(firstCard.sourceTitle!), findsWidgets);

      expect(find.byKey(const Key('commit-answer')), findsNothing);
      expect(controller.activeSession, isNull);
      expect(controller.events, beforeEvents);
      expect(find.byKey(const Key('retry-session')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('practice result does not expose mock review', (tester) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await controller.startUnit('fixture_safety');
    await controller.commitAnswer(controller.currentCard!.answerIndex);
    await controller.advance();

    await pumpCompact(tester, controller);

    expect(find.byKey(const Key('mock-review-toggle')), findsNothing);
    expect(find.byKey(const Key('mock-review-item-0')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
