import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'test_support.dart';

void main() {
  testWidgets('optional Home supplement composes without changing shared runtime', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1600);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

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
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
        homeSupplementBuilder: (context, sharedController) {
          expect(identical(sharedController, controller), isTrue);
          return const Card(
            key: Key('fixture-home-supplement'),
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('Qualification-specific guidance'),
            ),
          );
        },
      ),
    );

    expect(find.byKey(const Key('home-supplement')), findsOneWidget);
    expect(find.byKey(const Key('fixture-home-supplement')), findsOneWidget);
    expect(find.text('Qualification-specific guidance'), findsOneWidget);
    expect(find.byKey(const Key('primary-learning-action')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
