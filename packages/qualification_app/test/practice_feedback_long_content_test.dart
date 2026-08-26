import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'test_support.dart';

const _longSelectedAnswer =
    '作業を開始したあとで必要になった時点で手順書を確認し、記録は作業終了後にまとめて作成する。';
const _longCorrectAnswer =
    '作業を開始する前に手順書の該当箇所を確認し、必要な点検と記録を所定の様式に沿って実施する。';

QualificationBank _loadLongChoiceBank() {
  return QualificationBank.decode(
    '''
{
  "schemaVersion": 2,
  "appKey": "qualification_fixture",
  "bankRevision": "practice-feedback-long-content-v1",
  "examProfileVersion": "fixture-exam-v1",
  "decks": [
    {
      "id": "feedback_fixture",
      "isPurchased": false,
      "title": "長文フィードバック Fixture",
      "units": [
        {
          "id": "fixture_safety",
          "title": "長文の安全原則",
          "cards": [
            {
              "stableId": "FIXTURE-Q-900001",
              "questionVersion": 1,
              "question": "長い日本語の選択肢を含む場合に、作業前の対応として適切なものはどれか？",
              "choices": [
                "$_longSelectedAnswer",
                "$_longCorrectAnswer"
              ],
              "answerIndex": 1,
              "explanation": "作業開始前に手順書を確認し、所定の点検と記録を行います。",
              "difficulty": 1,
              "importance": 1,
              "isPremium": false,
              "unitId": "fixture_safety",
              "unitTags": ["安全", "長文"]
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
}

void main() {
  testWidgets(
    'long Japanese practice answers remain readable and reachable at 2x text scale',
    (tester) async {
      tester.view.physicalSize = const Size(640, 1600);
      tester.view.devicePixelRatio = 2;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final controller = QualificationProductionController(
        definition: fixtureDefinition,
        bankLoader: FixedBankLoader(_loadLongChoiceBank()),
        sessionStore: MemoryQualificationSessionStore(),
        learningRepository: InMemoryLearningRepository(),
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

      final selectedChoice = find.byKey(const Key('choice-0'));
      await tester.scrollUntilVisible(selectedChoice, 200);
      await tester.pumpAndSettle();
      await tester.tap(selectedChoice);
      await tester.pump();
      final commit = find.byKey(const Key('commit-answer'));
      await tester.scrollUntilVisible(commit, 200);
      await tester.pumpAndSettle();
      await tester.tap(commit);
      await tester.pump();

      await tester.scrollUntilVisible(
        find.byKey(const Key('correct-answer-feedback')),
        200,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('あなたの回答: $_longSelectedAnswer'),
        findsOneWidget,
      );
      expect(find.text('正解: $_longCorrectAnswer'), findsOneWidget);

      final next = find.byKey(const Key('next-question'));
      await tester.scrollUntilVisible(next, 200);
      await tester.pumpAndSettle();
      expect(next, findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
