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

  testWidgets(
    'incorrect practice feedback identifies selected and correct answers at large text scale',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final controller = await createController();
      addTearDown(controller.dispose);
      expect(await controller.startUnit('fixture_operations'), isTrue);
      await tester.pumpWidget(
        QualificationProductionApp(
          definition: fixtureDefinition,
          controller: controller,
        ),
      );

      final card = controller.currentCard!;
      final selectedIndex = card.answerIndex == card.choices.length - 1
          ? 0
          : card.choices.length - 1;
      final selectedText = card.choices[selectedIndex];
      final correctText = card.choices[card.answerIndex];
      expect(selectedIndex, isNot(card.answerIndex));

      await tester.ensureVisible(find.byKey(Key('choice-$selectedIndex')));
      await tester.tap(find.byKey(Key('choice-$selectedIndex')));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('commit-answer')),
        120,
      );
      await tester.tap(find.byKey(const Key('commit-answer')));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const Key('practice-answer-summary')),
        120,
      );
      await tester.pump();

      expect(find.text('不正解'), findsOneWidget);
      expect(find.text('あなたの回答'), findsOneWidget);
      expect(find.text('正解の選択肢'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('selected-answer'))).data,
        selectedText,
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('correct-answer'))).data,
        correctText,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('correct practice feedback still identifies both answers',
      (tester) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    expect(await controller.startUnit('fixture_safety'), isTrue);
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );

    final card = controller.currentCard!;
    final correctIndex = card.answerIndex;
    final correctText = card.choices[correctIndex];
    await tester.tap(find.byKey(Key('choice-$correctIndex')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('commit-answer')),
      120,
    );
    await tester.tap(find.byKey(const Key('commit-answer')));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.byKey(const Key('practice-answer-summary')),
      120,
    );
    await tester.pump();

    expect(find.text('正解'), findsOneWidget);
    expect(find.text('あなたの回答'), findsOneWidget);
    expect(find.text('正解の選択肢'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const Key('selected-answer'))).data,
      correctText,
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('correct-answer'))).data,
      correctText,
    );
  });

  testWidgets('mock commit does not reveal practice answer summary',
      (tester) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    expect(await controller.startMockExam(), isTrue);
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );

    final correctIndex = controller.currentCard!.answerIndex;
    final selectedIndex = correctIndex == 0 ? 1 : 0;
    await tester.tap(find.byKey(Key('choice-$selectedIndex')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('commit-answer')));
    await tester.pump();

    expect(find.byKey(const Key('mock-answer-committed')), findsOneWidget);
    expect(find.byKey(const Key('practice-answer-summary')), findsNothing);
    expect(find.byKey(const Key('selected-answer')), findsNothing);
    expect(find.byKey(const Key('correct-answer')), findsNothing);
  });
}
