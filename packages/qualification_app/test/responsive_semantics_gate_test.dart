import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'test_support.dart';

void main() {
  Future<QualificationProductionController> createController({
    QualificationAppDefinition? definition,
    bool unlocked = false,
    DateTime Function()? now,
  }) async {
    final resolvedDefinition = definition ?? fixtureDefinition;
    final cache = MemoryEntitlementCache();
    if (unlocked) {
      cache.value = EntitlementSnapshot(
        ownedProductIds: const {'fixture_full_unlock'},
      );
    }
    final controller = QualificationProductionController(
      definition: resolvedDefinition,
      bankLoader: FixedBankLoader(loadFixtureBank()),
      sessionStore: MemoryQualificationSessionStore(),
      learningRepository: InMemoryLearningRepository(),
      purchaseGateway: FakePurchaseGateway(),
      entitlementCache: cache,
      now: now ?? TestClock().call,
      randomizer: const IdentityQuestionRandomizer(),
    );
    await controller.initialize();
    return controller;
  }

  Future<void> pumpCompact(
    WidgetTester tester,
    QualificationProductionController controller, {
    QualificationAppDefinition? definition,
  }) async {
    tester.view.physicalSize = const Size(640, 1600);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: definition ?? fixtureDefinition,
        controller: controller,
      ),
    );
  }

  testWidgets('compact large-text Home keeps primary and unlock actions reachable', (
    tester,
  ) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await pumpCompact(tester, controller);

    expect(find.byKey(const Key('primary-learning-action')), findsOneWidget);
    expect(tester.takeException(), isNull);

    final purchase = find.byKey(const Key('purchase-full-unlock'));
    await tester.scrollUntilVisible(purchase, 240);
    await tester.pumpAndSettle();
    expect(purchase, findsOneWidget);
    expect(tester.takeException(), isNull);

    final support = find.byKey(const Key('support-link'));
    await tester.scrollUntilVisible(support, 240);
    await tester.pumpAndSettle();
    expect(support, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact large-text timed mock header remains usable', (
    tester,
  ) async {
    final profile = MockExamProfileV1(
      profileVersion: 'fixture-responsive-timed-v1',
      questionCount: 2,
      timeLimitMinutes: 1,
      allocations: const [
        ExamUnitAllocationV1(unitId: 'fixture_operations', questionCount: 1),
        ExamUnitAllocationV1(unitId: 'fixture_safety', questionCount: 1),
      ],
      overallPassPercent: null,
      sectionPassRules: const [],
      shuffleQuestions: false,
    );
    final definition = fixtureDefinitionWith(examProfile: profile);
    final controller = await createController(
      definition: definition,
      unlocked: true,
      now: () => tester.binding.clock.now().toUtc(),
    );
    addTearDown(controller.dispose);
    await controller.startMockExam();
    await pumpCompact(tester, controller, definition: definition);

    expect(find.byKey(const Key('leave-session')), findsOneWidget);
    expect(find.byKey(const Key('mock-exam-remaining')), findsOneWidget);
    expect(find.textContaining('1 / 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact large-text Result keeps Home action reachable', (
    tester,
  ) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await controller.startUnit('fixture_safety');
    await controller.commitAnswer(controller.currentCard!.answerIndex);
    await controller.advance();
    await pumpCompact(tester, controller);

    expect(find.byKey(const Key('session-result')), findsOneWidget);
    expect(find.byKey(const Key('return-home')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('practice correctness feedback is a semantic live region', (
    tester,
  ) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await controller.startUnit('fixture_safety');
    final semantics = tester.ensureSemantics();
    await pumpCompact(tester, controller);

    final correctIndex = controller.currentCard!.answerIndex;
    await tester.tap(find.byKey(Key('choice-$correctIndex')));
    await tester.pump();
    final commit = find.byKey(const Key('commit-answer'));
    await tester.scrollUntilVisible(commit, 200);
    await tester.pumpAndSettle();
    await tester.tap(commit);
    await tester.pump();

    final feedback = find.byKey(const Key('answer-feedback'));
    await tester.scrollUntilVisible(feedback, 200);
    await tester.pumpAndSettle();
    final node = tester.getSemantics(feedback);
    expect(node.label, contains('正解'));
    expect(node.hasFlag(SemanticsFlag.isLiveRegion), isTrue);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
