import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'test_support.dart';

void main() {
  Future<QualificationProductionController> createController(
    QualificationBank bank, {
    bool unlocked = false,
  }) async {
    final cache = MemoryEntitlementCache();
    if (unlocked) {
      cache.value = EntitlementSnapshot(
        ownedProductIds: const {'fixture_full_unlock'},
      );
    }
    final controller = QualificationProductionController(
      definition: fixtureDefinition,
      bankLoader: FixedBankLoader(bank),
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

  Future<void> pumpQuiz(
    WidgetTester tester,
    QualificationProductionController controller,
  ) async {
    tester.view.physicalSize = const Size(640, 1600);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );
  }

  Future<void> commitChoice(WidgetTester tester, int index) async {
    await tester.tap(find.byKey(Key('choice-$index')));
    await tester.pump();
    final commit = find.byKey(const Key('commit-answer'));
    await tester.scrollUntilVisible(commit, 200);
    await tester.pumpAndSettle();
    await tester.tap(commit);
    await tester.pump();
  }

  testWidgets('practice shows per-question source metadata after commit', (
    tester,
  ) async {
    final controller = await createController(loadFixtureBank());
    addTearDown(controller.dispose);
    await controller.startUnit('fixture_safety');
    final card = controller.currentCard!;
    await pumpQuiz(tester, controller);

    await commitChoice(tester, card.answerIndex);
    final source = find.byKey(const Key('question-source-provenance'));
    await tester.scrollUntilVisible(source, 200);
    await tester.pumpAndSettle();

    expect(source, findsOneWidget);
    expect(find.text('出典'), findsOneWidget);
    expect(find.text(card.sourceTitle!), findsOneWidget);
    expect(find.text('版: ${card.sourceVersion}'), findsOneWidget);
    expect(find.text('箇所: ${card.sourceSection}'), findsOneWidget);
    expect(find.text(card.sourceId!), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active mock does not reveal source provenance', (tester) async {
    final controller = await createController(loadFixtureBank(), unlocked: true);
    addTearDown(controller.dispose);
    await controller.startMockExam();
    final card = controller.currentCard!;
    final selectedIndex = card.answerIndex == 0 ? 1 : 0;
    await pumpQuiz(tester, controller);

    await commitChoice(tester, selectedIndex);

    expect(find.byKey(const Key('mock-answer-committed')), findsOneWidget);
    expect(find.byKey(const Key('question-source-provenance')), findsNothing);
    expect(find.byKey(const Key('question-source-title')), findsNothing);
    expect(find.byKey(const Key('question-source-version')), findsNothing);
    expect(find.byKey(const Key('question-source-section')), findsNothing);
    expect(find.text(card.sourceTitle!), findsNothing);
  });

  testWidgets('missing source metadata is a normal nonfatal state', (tester) async {
    final bank = QualificationBank.decode(
      '''
{
  "schemaVersion": 2,
  "appKey": "qualification_fixture",
  "bankRevision": "source-provenance-missing-v1",
  "examProfileVersion": "fixture-exam-v1",
  "decks": [
    {
      "id": "fixture_missing_source",
      "isPurchased": false,
      "title": "Missing source fixture",
      "units": [
        {
          "id": "fixture_safety",
          "title": "架空の安全原則",
          "cards": [
            {
              "stableId": "FIXTURE-Q-900003",
              "questionVersion": 1,
              "question": "出典metadataがない問題でも通常演習を継続できるか？",
              "choices": ["継続できる", "継続できない"],
              "answerIndex": 0,
              "explanation": "出典metadataは任意であり、欠落時は出典表示だけを省略します。",
              "isPremium": false,
              "unitId": "fixture_safety"
            }
          ]
        }
      ]
    }
  ]
}
''',
      fixtureDefinition,
    );
    final controller = await createController(bank);
    addTearDown(controller.dispose);
    await controller.startUnit('fixture_safety');
    await pumpQuiz(tester, controller);

    await commitChoice(tester, 0);

    expect(find.byKey(const Key('question-source-provenance')), findsNothing);
    expect(find.text('出典'), findsNothing);
    expect(find.byKey(const Key('answer-feedback')), findsOneWidget);
    final next = find.byKey(const Key('next-question'));
    await tester.scrollUntilVisible(next, 200);
    await tester.pumpAndSettle();
    expect(next, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
