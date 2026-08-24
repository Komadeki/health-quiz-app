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

  testWidgets('recommendation is the initial primary action', (tester) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await pumpHome(tester, controller);

    expect(find.byKey(const Key('primary-learning-action')), findsOneWidget);
    expect(find.byKey(const Key('primary-action-recommendation')), findsOneWidget);
    expect(find.textContaining('おすすめ'), findsWidgets);
  });

  testWidgets('incorrect review outranks recommendation after a mistake', (
    tester,
  ) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await pumpHome(tester, controller);

    await controller.startUnit('fixture_safety');
    final correct = controller.currentCard!.answerIndex;
    await controller.commitAnswer(correct == 0 ? 1 : 0);
    await controller.advance();
    controller.returnHome();
    await tester.pump();

    expect(find.byKey(const Key('primary-action-incorrect')), findsOneWidget);
    expect(find.text('間違えた問題を復習'), findsOneWidget);
  });

  testWidgets('resumable session outranks incorrect review and recommendation', (
    tester,
  ) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await pumpHome(tester, controller);

    await controller.startUnit('fixture_safety');
    final correct = controller.currentCard!.answerIndex;
    await controller.commitAnswer(correct == 0 ? 1 : 0);
    await controller.advance();
    await controller.startUnit('fixture_operations');
    controller.returnHome();
    await tester.pump();

    expect(find.byKey(const Key('resume-session')), findsOneWidget);
    expect(find.byKey(const Key('primary-action-incorrect')), findsNothing);
    expect(find.text('続きから'), findsOneWidget);
  });
}
