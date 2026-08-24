import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'test_support.dart';

void main() {
  Future<QualificationProductionController> createController({
    bool fullUnlock = false,
  }) async {
    final cache = MemoryEntitlementCache();
    if (fullUnlock) {
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

  testWidgets('correct practice commit explicitly labels selected and correct answer',
      (tester) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await controller.startUnit('fixture_safety');
    final card = controller.currentCard!;
    await controller.commitAnswer(card.answerIndex);

    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );

    final selected = tester.widget<Text>(
      find.byKey(const Key('practice-selected-answer')),
    );
    final correct = tester.widget<Text>(
      find.byKey(const Key('practice-correct-answer')),
    );

    expect(find.text('正解'), findsOneWidget);
    expect(selected.data, 'あなたの回答: ${card.choices[card.answerIndex]}');
    expect(correct.data, '正解: ${card.choices[card.answerIndex]}');
    expect(find.byKey(const Key('commit-answer')), findsNothing);
  });

  testWidgets('incorrect practice commit names the learner answer and correct answer',
      (tester) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await controller.startUnit('fixture_safety');
    final card = controller.currentCard!;
    final selectedIndex = card.answerIndex == 0 ? 1 : 0;
    await controller.commitAnswer(selectedIndex);

    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );

    final selected = tester.widget<Text>(
      find.byKey(const Key('practice-selected-answer')),
    );
    final correct = tester.widget<Text>(
      find.byKey(const Key('practice-correct-answer')),
    );

    expect(find.text('不正解'), findsOneWidget);
    expect(selected.data, 'あなたの回答: ${card.choices[selectedIndex]}');
    expect(correct.data, '正解: ${card.choices[card.answerIndex]}');
    expect(selected.data, isNot(correct.data));
  });

  testWidgets('active mock still hides selected/correct practice feedback',
      (tester) async {
    final controller = await createController(fullUnlock: true);
    addTearDown(controller.dispose);
    await controller.startMockExam();
    final card = controller.currentCard!;
    final selectedIndex = card.answerIndex == 0 ? 1 : 0;
    await controller.commitAnswer(selectedIndex);

    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );

    expect(find.byKey(const Key('mock-answer-committed')), findsOneWidget);
    expect(find.byKey(const Key('answer-feedback')), findsNothing);
    expect(find.byKey(const Key('practice-selected-answer')), findsNothing);
    expect(find.byKey(const Key('practice-correct-answer')), findsNothing);
    expect(find.text('解説（Explanation）'), findsNothing);
  });
}
