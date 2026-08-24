import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'test_support.dart';

void main() {
  testWidgets(
    'practice can leave to Home and resume committed state without completion',
    (tester) async {
      final learning = InMemoryLearningRepository();
      final controller = QualificationProductionController(
        definition: fixtureDefinition,
        bankLoader: FixedBankLoader(loadFixtureBank()),
        sessionStore: MemoryQualificationSessionStore(),
        learningRepository: learning,
        purchaseGateway: FakePurchaseGateway(),
        entitlementCache: MemoryEntitlementCache(),
        now: TestClock().call,
        randomizer: const IdentityQuestionRandomizer(),
      );
      await controller.initialize();
      await controller.startUnit('fixture_safety');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        QualificationProductionApp(
          definition: fixtureDefinition,
          controller: controller,
        ),
      );

      final questionId = controller.activeSession!.currentQuestionId;
      final answerIndex = controller.currentCard!.answerIndex;
      await tester.tap(find.byKey(Key('choice-$answerIndex')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('commit-answer')));
      await tester.pump();

      expect(controller.currentResponse, answerIndex);
      expect(find.text('正解'), findsOneWidget);

      await tester.tap(find.byKey(const Key('leave-session')));
      await tester.pump();

      expect(controller.view, QualificationProductionView.home);
      expect(controller.activeSession, isNotNull);
      expect(controller.activeSession!.currentQuestionId, questionId);
      expect(controller.currentResponse, answerIndex);
      expect(await learning.loadSessionHistory(), isEmpty);
      expect(find.byKey(const Key('resume-session')), findsOneWidget);

      await tester.tap(find.byKey(const Key('resume-session')));
      await tester.pump();

      expect(controller.view, QualificationProductionView.quiz);
      expect(controller.activeSession!.currentQuestionId, questionId);
      expect(controller.currentResponse, answerIndex);
      expect(find.text('正解'), findsOneWidget);
    },
  );

  testWidgets(
    'timed mock warns before leave and wall clock continues while on Home',
    (tester) async {
      final profile = MockExamProfileV1(
        profileVersion: 'fixture-leave-resume-v1',
        questionCount: 2,
        timeLimitMinutes: 1,
        allocations: const [
          ExamUnitAllocationV1(
            unitId: 'fixture_operations',
            questionCount: 1,
          ),
          ExamUnitAllocationV1(
            unitId: 'fixture_safety',
            questionCount: 1,
          ),
        ],
        overallPassPercent: null,
        sectionPassRules: const [],
        shuffleQuestions: false,
      );
      final definition = fixtureDefinitionWith(examProfile: profile);
      final cache = MemoryEntitlementCache()
        ..value = EntitlementSnapshot(
          ownedProductIds: const {'fixture_full_unlock'},
        );
      final controller = QualificationProductionController(
        definition: definition,
        bankLoader: FixedBankLoader(loadFixtureBank()),
        sessionStore: MemoryQualificationSessionStore(),
        learningRepository: InMemoryLearningRepository(),
        purchaseGateway: FakePurchaseGateway(),
        entitlementCache: cache,
        now: () => tester.binding.clock.now().toUtc(),
        randomizer: const IdentityQuestionRandomizer(),
      );
      await controller.initialize();
      await controller.startMockExam();

      await tester.pumpWidget(
        QualificationProductionApp(
          definition: definition,
          controller: controller,
        ),
      );

      final beforeLeave = controller.remainingMockExamDuration!;
      await tester.tap(find.byKey(const Key('leave-session')));
      await tester.pumpAndSettle();

      expect(find.text('模擬試験を中断しますか？'), findsOneWidget);
      expect(
        find.text('ホームに戻っても制限時間は止まりません。後で「続きから」再開できます。'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('stay-in-session')));
      await tester.pumpAndSettle();
      expect(controller.view, QualificationProductionView.quiz);

      await tester.tap(find.byKey(const Key('leave-session')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-leave-session')));
      await tester.pumpAndSettle();

      expect(controller.view, QualificationProductionView.home);
      expect(controller.activeSession, isNotNull);
      expect(find.byKey(const Key('resume-session')), findsOneWidget);

      await tester.pump(const Duration(seconds: 20));
      await tester.tap(find.byKey(const Key('resume-session')));
      await tester.pump();

      final afterResume = controller.remainingMockExamDuration!;
      expect(controller.view, QualificationProductionView.quiz);
      expect(afterResume, lessThan(beforeLeave));
      expect(
        beforeLeave.inSeconds - afterResume.inSeconds,
        greaterThanOrEqualTo(19),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    },
  );
}
