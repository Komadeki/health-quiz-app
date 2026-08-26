import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'test_support.dart';

void main() {
  Future<QualificationProductionController> createController() async {
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
    return controller;
  }

  Future<void> pumpHome(
    WidgetTester tester,
    QualificationProductionController controller,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );
  }

  OutlinedButton practiceButton(WidgetTester tester, String key) {
    return tester.widget<OutlinedButton>(find.byKey(Key(key)));
  }

  testWidgets('empty incorrect practice is disabled with a stable reason', (
    tester,
  ) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await pumpHome(tester, controller);

    expect(practiceButton(tester, 'start-unanswered').onPressed, isNotNull);
    expect(practiceButton(tester, 'start-incorrect').onPressed, isNull);
    expect(
      find.byKey(const Key('start-incorrect-unavailable')),
      findsOneWidget,
    );
    expect(find.text('直近で間違えた問題はありません。'), findsOneWidget);
  });

  testWidgets('answered-all state disables unanswered instead of no-op', (
    tester,
  ) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await pumpHome(tester, controller);

    await controller.startUnit('fixture_safety');
    await controller.commitAnswer(controller.currentCard!.answerIndex);
    await controller.advance();
    controller.returnHome();
    await tester.pump();

    expect(practiceButton(tester, 'start-unanswered').onPressed, isNull);
    expect(
      find.byKey(const Key('start-unanswered-unavailable')),
      findsOneWidget,
    );
    expect(find.text('未回答の問題はありません。'), findsOneWidget);
    expect(practiceButton(tester, 'start-incorrect').onPressed, isNull);
  });

  testWidgets('incorrect practice becomes enabled when an item is eligible', (
    tester,
  ) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await pumpHome(tester, controller);

    await controller.startUnit('fixture_safety');
    final correctIndex = controller.currentCard!.answerIndex;
    final incorrectIndex = correctIndex == 0 ? 1 : 0;
    await controller.commitAnswer(incorrectIndex);
    await controller.advance();
    controller.returnHome();
    await tester.pump();

    expect(practiceButton(tester, 'start-unanswered').onPressed, isNull);
    expect(practiceButton(tester, 'start-incorrect').onPressed, isNotNull);
    expect(
      find.byKey(const Key('start-incorrect-unavailable')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('start-incorrect')));
    await tester.pumpAndSettle();
    expect(controller.view, QualificationProductionView.home);
    expect(
      find.byKey(const Key('practice-count-sheet-incorrect')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('practice-count-incorrect-all')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('practice-count-incorrect-all')));
    await tester.pumpAndSettle();
    expect(controller.view, QualificationProductionView.quiz);
    expect(
      controller.bank!.stableId(controller.currentCard!),
      'FIXTURE-Q-000001',
    );
  });
}
