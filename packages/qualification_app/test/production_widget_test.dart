import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'test_support.dart';

void main() {
  Future<QualificationProductionController> createController({
    QualificationAppDefinition? definition,
    EntitlementSnapshot? entitlement,
  }) async {
    final resolvedDefinition = definition ?? fixtureDefinition;
    final cache = MemoryEntitlementCache();
    if (entitlement != null) cache.value = entitlement;
    final controller = QualificationProductionController(
      definition: resolvedDefinition,
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

  testWidgets('shared Material 3 shell exposes standard learning surfaces', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await createController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );

    expect(find.byKey(const Key('overall-progress')), findsOneWidget);
    expect(find.byKey(const Key('home-hero')), findsOneWidget);
    expect(find.byKey(const Key('overall-progress-ring')), findsOneWidget);
    expect(find.byKey(const Key('unit-performance-chart')), findsOneWidget);
    for (final metricKey in [
      'progress-metric-completed',
      'progress-metric-accuracy',
      'progress-metric-review',
      'progress-metric-mock-best',
    ]) {
      expect(find.byKey(Key(metricKey)), findsOneWidget);
    }
    expect(find.byKey(const Key('unit-fixture_safety')), findsOneWidget);
    expect(find.byKey(const Key('start-random')), findsOneWidget);
    expect(find.byKey(const Key('start-unanswered')), findsOneWidget);
    expect(find.byKey(const Key('start-incorrect')), findsOneWidget);
    expect(find.byKey(const Key('start-mock-exam')), findsOneWidget);
    expect(find.byKey(const Key('weakness-summary')), findsOneWidget);
    expect(find.byKey(const Key('recommendation')), findsOneWidget);
    expect(find.byKey(const Key('session-history')), findsOneWidget);
    expect(find.byKey(const Key('mock-exam-locked')), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('start-mock-exam')))
          .onPressed,
      isNull,
    );

    for (final unsupported in ['合格可能性', 'AI合否', '本番力']) {
      expect(find.textContaining(unsupported), findsNothing);
    }
  });

  testWidgets('learning status action explains progress by unit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await createController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );

    final action = find.byKey(const Key('show-learning-status'));
    await tester.scrollUntilVisible(action, 160);
    await tester.tap(action);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('learning-status-sheet')), findsOneWidget);
    expect(find.text('学習状況'), findsOneWidget);
    final sheet = find.byKey(const Key('learning-status-sheet'));
    expect(
      find.descendant(of: sheet, matching: find.text('架空の安全原則')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.text('架空の運用原則')),
      findsOneWidget,
    );
  });

  testWidgets('progress dashboard shows review count and best mock score', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await createController(
      entitlement: EntitlementSnapshot(
        ownedProductIds: const {'fixture_full_unlock'},
      ),
    );
    addTearDown(controller.dispose);

    await controller.startMockExam();
    while (controller.activeSession != null) {
      await controller.commitAnswer(controller.currentCard!.answerIndex);
      await controller.advance();
    }
    controller.returnHome();

    await controller.startUnit('fixture_safety');
    final card = controller.currentCard!;
    final wrongAnswer = (card.answerIndex + 1) % card.choices.length;
    await controller.commitAnswer(wrongAnswer);
    controller.returnHome();

    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );

    final review = find.byKey(const Key('progress-metric-review'));
    final mockBest = find.byKey(const Key('progress-metric-mock-best'));
    expect(
      find.descendant(of: review, matching: find.text('1問')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: mockBest, matching: find.text('2/2')),
      findsOneWidget,
    );
  });

  testWidgets('actionable and informational Home cards use distinct colors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await createController(
      entitlement: EntitlementSnapshot(
        ownedProductIds: const {'fixture_full_unlock'},
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );

    final recommendation = find.byKey(const Key('recommendation'));
    await tester.scrollUntilVisible(recommendation, 160);
    final history = find.byKey(const Key('session-history'));
    await tester.scrollUntilVisible(history, 160);
    final colors = Theme.of(tester.element(history)).colorScheme;

    expect(tester.widget<Card>(recommendation).color, colors.primaryContainer);
    expect(tester.widget<Card>(history).color, colors.surfaceContainerLow);
    expect(
      tester.widget<ListTile>(find.byKey(const Key('show-session-history')))
          .onTap,
      isNull,
    );
  });

  testWidgets('weakness starts its unit and completed history opens details', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = await createController();
    addTearDown(controller.dispose);
    await controller.startUnit('fixture_safety');
    final card = controller.currentCard!;
    final wrongAnswer = (card.answerIndex + 1) % card.choices.length;
    await controller.commitAnswer(wrongAnswer);
    await controller.advance();
    controller.returnHome();
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );

    final history = find.byKey(const Key('show-session-history'));
    await tester.scrollUntilVisible(history, 160);
    await tester.tap(history);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-history-sheet')), findsOneWidget);
    expect(find.textContaining('1回の完了記録'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final weakness = find.byKey(const Key('weakness-summary'));
    await tester.scrollUntilVisible(weakness, 160);
    await tester.tap(weakness);
    await tester.pump();

    expect(controller.view, QualificationProductionView.quiz);
    expect(controller.activeSession?.unitId, 'fixture_safety');
  });

  testWidgets('answer commit locks feedback and shows explanation', (
    tester,
  ) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );
    final unit = find.byKey(const Key('unit-fixture_safety'));
    await tester.scrollUntilVisible(unit, 200);
    await tester.ensureVisible(unit);
    await tester.pumpAndSettle();
    await tester.tap(unit);
    await tester.pump();
    final correctIndex = controller.currentCard!.answerIndex;
    await tester.tap(find.byKey(Key('choice-$correctIndex')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('commit-answer')));
    await tester.pump();

    expect(find.text('正解'), findsOneWidget);
    expect(find.text('解説（Explanation）'), findsOneWidget);
    expect(find.byKey(const Key('commit-answer')), findsNothing);
  });

  testWidgets(
      'support and privacy links use definition URLs without fatal failure', (
    tester,
  ) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    final opened = <Uri>[];
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
        urlLauncher: (url) async {
          opened.add(url);
          return false;
        },
      ),
    );

    final support = find.byKey(const Key('support-link'));
    await tester.scrollUntilVisible(support, 100);
    await tester.ensureVisible(support);
    await tester.pumpAndSettle();
    await tester.tap(support);
    await tester.pump();
    final privacy = find.byKey(const Key('privacy-link'));
    await tester.ensureVisible(privacy);
    await tester.pumpAndSettle();
    await tester.tap(privacy);
    await tester.pump();

    expect(opened, [
      Uri.parse('https://example.invalid/support'),
      Uri.parse('https://example.invalid/privacy'),
    ]);
    expect(controller.fatalError, isNull);
    expect(controller.view, QualificationProductionView.home);
  });

  testWidgets('null support and privacy URLs hide their in-app links', (
    tester,
  ) async {
    final definition = fixtureDefinitionWith(
      urls: const QualificationUrls(support: null, privacy: null),
    );
    final controller = await createController(definition: definition);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      QualificationProductionApp(
          definition: definition, controller: controller),
    );

    expect(find.byKey(const Key('support-link')), findsNothing);
    expect(find.byKey(const Key('privacy-link')), findsNothing);
  });

  testWidgets('timed mock shows remaining time and completes at its deadline', (
    tester,
  ) async {
    final profile = MockExamProfileV1(
      profileVersion: 'fixture-timed-v1',
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
    final cache = MemoryEntitlementCache()
      ..value = EntitlementSnapshot(
        ownedProductIds: const {'fixture_full_unlock'},
      );
    final learning = InMemoryLearningRepository();
    final controller = QualificationProductionController(
      definition: definition,
      bankLoader: FixedBankLoader(loadFixtureBank()),
      sessionStore: MemoryQualificationSessionStore(),
      learningRepository: learning,
      purchaseGateway: FakePurchaseGateway(),
      entitlementCache: cache,
      now: () => tester.binding.clock.now().toUtc(),
      randomizer: const IdentityQuestionRandomizer(),
    );
    await controller.initialize();
    await controller.startMockExam();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      QualificationProductionApp(
          definition: definition, controller: controller),
    );

    expect(find.text('残り 1:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 18));
    expect(find.text('残り 0:42'), findsOneWidget);
    await tester.pump(const Duration(seconds: 42));
    await tester.pump();

    expect(controller.view, QualificationProductionView.result);
    expect(await learning.loadAllEvents(), isEmpty);
    expect(find.byKey(const Key('mock-no-pass-rule')), findsOneWidget);
  });

  testWidgets('untimed mock does not show a remaining-time UI', (tester) async {
    final controller = await createController(
      entitlement: EntitlementSnapshot(
        ownedProductIds: const {'fixture_full_unlock'},
      ),
    );
    addTearDown(controller.dispose);
    await controller.startMockExam();
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );

    expect(find.byKey(const Key('mock-exam-remaining')), findsNothing);
  });

  testWidgets(
      'mock result without a pass rule explains that score is reference only', (
    tester,
  ) async {
    final controller = await createController(
      entitlement: EntitlementSnapshot(
        ownedProductIds: const {'fixture_full_unlock'},
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );
    await controller.startMockExam();
    while (controller.activeSession != null) {
      await controller.commitAnswer(controller.currentCard!.answerIndex);
      await controller.advance();
    }
    await tester.pump();

    expect(find.byKey(const Key('session-result')), findsOneWidget);
    expect(find.byKey(const Key('mock-no-pass-rule')), findsOneWidget);
    expect(find.text('合格'), findsNothing);
    expect(find.text('不合格'), findsNothing);
  });

  testWidgets('configured pass rules keep the existing pass result',
      (tester) async {
    final profile = MockExamProfileV1(
      profileVersion: 'fixture-pass-v1',
      questionCount: 2,
      timeLimitMinutes: null,
      allocations: const [
        ExamUnitAllocationV1(unitId: 'fixture_operations', questionCount: 1),
        ExamUnitAllocationV1(unitId: 'fixture_safety', questionCount: 1),
      ],
      overallPassPercent: 50,
      sectionPassRules: const [],
      shuffleQuestions: false,
    );
    final definition = fixtureDefinitionWith(examProfile: profile);
    final controller = await createController(
      definition: definition,
      entitlement: EntitlementSnapshot(
        ownedProductIds: const {'fixture_full_unlock'},
      ),
    );
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      QualificationProductionApp(
          definition: definition, controller: controller),
    );
    await controller.startMockExam();
    while (controller.activeSession != null) {
      await controller.commitAnswer(controller.currentCard!.answerIndex);
      await controller.advance();
    }
    await tester.pump();

    expect(find.text('合格'), findsOneWidget);
    expect(find.byKey(const Key('mock-no-pass-rule')), findsNothing);
  });
}
