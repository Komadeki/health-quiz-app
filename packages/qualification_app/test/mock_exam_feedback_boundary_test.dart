import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'test_support.dart';

void main() {
  testWidgets(
    'mock commit records and locks the answer without revealing feedback',
    (tester) async {
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
      await controller.startMockExam();
      addTearDown(controller.dispose);

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

      expect(controller.currentResponse, selectedIndex);
      expect(find.byKey(const Key('mock-answer-committed')), findsOneWidget);
      expect(find.byKey(const Key('answer-feedback')), findsNothing);
      expect(find.text('解説（Explanation）'), findsNothing);
      expect(find.byKey(const Key('next-question')), findsOneWidget);
      expect(find.byKey(const Key('commit-answer')), findsNothing);

      final committedChoice = tester.widget<RadioListTile<int>>(
        find.byKey(Key('choice-$selectedIndex')),
      );
      expect(committedChoice.enabled, isFalse);
    },
  );
}
