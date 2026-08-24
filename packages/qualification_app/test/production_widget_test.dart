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
    await tester.tap(find.byKey(const Key('unit-fixture_safety')));
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
