import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'test_support.dart';

void main() {
  Future<QualificationProductionController> createPracticeController() async {
    final controller = QualificationProductionController(
      definition: fixtureDefinition,
      bankLoader: FixedBankLoader(loadFixtureBank()),
      sessionStore: MemoryQualificationSessionStore(),
      learningRepository: InMemoryLearningRepository(),
      purchaseGateway: FakePurchaseGateway(),
      entitlementCache: MemoryEntitlementCache(),
      now: TestClock().call,
      randomizer: const IdentityQuestionRandomizer(),
    );
    await controller.initialize();
    await controller.startUnit('fixture_safety');
    return controller;
  }

  Future<void> pumpQuiz(
    WidgetTester tester,
    QualificationProductionController controller,
  ) async {
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );
  }

  testWidgets('practice feedback explicitly names selected and correct answers', (
    tester,
  ) async {
    final controller = await createPracticeController();
    addTearDown(controller.dispose);
    await pumpQuiz(tester, controller);

    final card = controller.currentCard!;
    final correctIndex = card.answerIndex;
    final selectedIndex = correctIndex == 0 ? 1 : 0;
    final selectedAnswer = card.choices[selectedIndex];
    final correctAnswer = card.choices[correctIndex];

    await tester.tap(find.byKey(Key('choice-$selectedIndex')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('commit-answer')));
    await tester.pump();

    expect(find.byKey(const Key('answer-feedback')), findsOneWidget);
    expect(find.text('不正解'), findsOneWidget);
    expect(find.byKey(const Key('selected-answer-text')), findsOneWidget);
    expect(find.byKey(const Key('correct-answer-text')), findsOneWidget);
    expect(find.text('あなたの回答: $selectedAnswer'), findsOneWidget);
    expect(find.text('正答: $correctAnswer'), findsOneWidget);
    expect(find.byKey(const Key('next-question')), findsOneWidget);
  });

  testWidgets('practice feedback names the answer after a correct response', (
    tester,
  ) async {
    final controller = await createPracticeController();
    addTearDown(controller.dispose);
    await pumpQuiz(tester, controller);

    final card = controller.currentCard!;
    final correctIndex = card.answerIndex;
    final answer = card.choices[correctIndex];

    await tester.tap(find.byKey(Key('choice-$correctIndex')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('commit-answer')));
    await tester.pump();

    expect(find.text('正解'), findsOneWidget);
    expect(find.text('あなたの回答: $answer'), findsOneWidget);
    expect(find.text('正答: $answer'), findsOneWidget);
  });
}
