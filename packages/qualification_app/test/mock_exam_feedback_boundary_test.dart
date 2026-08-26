import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'test_support.dart';

void main() {
  testWidgets(
    'mock answers stay feedback-free and can be reviewed, revised, then submitted',
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
      expect(find.byKey(const Key('next-question')), findsOneWidget);
      expect(
        tester
            .widget<RadioListTile<int>>(find.byKey(Key('choice-$firstChoice')))
            .enabled,
        isTrue,
      );

      await tester.tap(find.byKey(const Key('next-question')));
      await tester.pump();
      expect(controller.activeSession!.currentIndex, 1);
      expect(find.byKey(const Key('previous-question')), findsOneWidget);

      // A mock can be reviewed before answering the current question.
      await tester.tap(find.byKey(const Key('previous-question')));
      await tester.pump();
      expect(controller.activeSession!.currentIndex, 0);

      final revisedChoice = firstChoice == 0 ? 1 : 0;
      await tester.tap(find.byKey(Key('choice-$revisedChoice')));
      await tester.pump();
      expect(find.byKey(const Key('revise-answer')), findsOneWidget);
      await tester.tap(find.byKey(const Key('revise-answer')));
      await tester.pump();
      expect(controller.currentResponse, revisedChoice);
      expect(find.byKey(const Key('answer-feedback')), findsNothing);

      await tester.tap(find.byKey(const Key('next-question')));
      await tester.pump();
      final secondChoice = controller.currentCard!.answerIndex;
      await tester.tap(find.byKey(Key('choice-$secondChoice')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('commit-answer')));
      await tester.pump();

      expect(find.byKey(const Key('submit-mock-exam')), findsOneWidget);
      await tester.tap(find.byKey(const Key('submit-mock-exam')));
      await tester.pumpAndSettle();
      expect(find.text('模擬試験を提出しますか？'), findsOneWidget);
      expect(find.byKey(const Key('review-before-submit')), findsOneWidget);
      expect(find.byKey(const Key('confirm-submit-mock-exam')), findsOneWidget);

      await tester.tap(find.byKey(const Key('review-before-submit')));
      await tester.pumpAndSettle();
      expect(controller.view, QualificationProductionView.quiz);

      await tester.tap(find.byKey(const Key('submit-mock-exam')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-submit-mock-exam')));
      await tester.pumpAndSettle();

      expect(controller.view, QualificationProductionView.result);
      expect(find.byKey(const Key('session-result')), findsOneWidget);
      expect(controller.events.length, 2);
    },
  );
}
