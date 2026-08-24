import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'test_support.dart';

void main() {
  Future<QualificationProductionController> createController({
    bool unlocked = false,
  }) async {
    final cache = MemoryEntitlementCache();
    if (unlocked) {
      cache.value = EntitlementSnapshot(
        ownedProductIds: const {'fixture_full_unlock'},
      );
    }
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

  Future<void> pumpQuiz(
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

  Future<void> commitChoice(
    WidgetTester tester,
    int selectedIndex,
  ) async {
    await tester.tap(find.byKey(Key('choice-$selectedIndex')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('commit-answer')));
    await tester.pump();
  }

  testWidgets('correct practice explicitly identifies selected and correct answer', (
    tester,
  ) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await controller.startUnit('fixture_safety');
    final card = controller.currentCard!;
    final correctIndex = card.answerIndex;
    await pumpQuiz(tester, controller);

    await commitChoice(tester, correctIndex);

    expect(find.text('正解'), findsOneWidget);
    expect(
      find.text('あなたの回答: ${card.choices[correctIndex]}'),
      findsOneWidget,
    );
    expect(
      find.text('正解: ${card.choices[correctIndex]}'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('selected-answer-feedback')), findsOneWidget);
    expect(find.byKey(const Key('correct-answer-feedback')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('next-question')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('next-question')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('incorrect practice explicitly distinguishes selected from correct', (
    tester,
  ) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await controller.startUnit('fixture_safety');
    final card = controller.currentCard!;
    final correctIndex = card.answerIndex;
    final selectedIndex = correctIndex == 0 ? 1 : 0;
    await pumpQuiz(tester, controller);

    await commitChoice(tester, selectedIndex);

    expect(find.text('不正解'), findsOneWidget);
    expect(
      find.text('あなたの回答: ${card.choices[selectedIndex]}'),
      findsOneWidget,
    );
    expect(
      find.text('正解: ${card.choices[correctIndex]}'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('selected-answer-feedback')), findsOneWidget);
    expect(find.byKey(const Key('correct-answer-feedback')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('next-question')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('next-question')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active mock still hides explicit answer feedback', (tester) async {
    final controller = await createController(unlocked: true);
    addTearDown(controller.dispose);
    await controller.startMockExam();
    final correctIndex = controller.currentCard!.answerIndex;
    final selectedIndex = correctIndex == 0 ? 1 : 0;
    await pumpQuiz(tester, controller);

    await commitChoice(tester, selectedIndex);

    expect(find.byKey(const Key('mock-answer-committed')), findsOneWidget);
    expect(find.byKey(const Key('answer-feedback')), findsNothing);
    expect(find.byKey(const Key('selected-answer-feedback')), findsNothing);
    expect(find.byKey(const Key('correct-answer-feedback')), findsNothing);
    expect(find.text('解説（Explanation）'), findsNothing);
    expect(find.byKey(const Key('next-question')), findsOneWidget);
  });
}
