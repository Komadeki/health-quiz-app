import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/models/card.dart';
import 'package:health_quiz_app/quiz_app_definition.dart';
import 'package:health_quiz_app/utils/stable_id.dart';

void main() {
  test('QuizCard preserves qualification metadata', () {
    final card = QuizCard.fromJson({
      'stableId': 'DRONE-Q-000001',
      'questionVersion': 2,
      'question': 'テスト問題',
      'choices': ['A', 'B', 'C'],
      'answerIndex': 1,
      'explanation': '解説',
      'unitId': 'law',
      'sourceId': 'DRONE-SRC-001',
      'sourceTitle': '教則第5版',
      'sourceSection': '3.1.2',
      'sourceVersion': '5.0',
      'difficulty': 3,
      'importance': 2,
      'revisionTag': 'v5_changed',
    });

    expect(card.stableId, 'DRONE-Q-000001');
    expect(card.questionVersion, 2);
    expect(card.sourceId, 'DRONE-SRC-001');
    expect(card.sourceSection, '3.1.2');
    expect(card.sourceVersion, '5.0');
    expect(card.difficulty, 3);
    expect(card.importance, 2);
    expect(card.revisionTag, 'v5_changed');

    final shuffled = card.shuffled(randomize: false);
    expect(shuffled.stableId, card.stableId);
    expect(shuffled.sourceSection, card.sourceSection);
  });

  test('QuizCard keeps existing JSON fields without qualification metadata',
      () {
    final card = QuizCard.fromJson({
      'question': '既存問題',
      'choices': ['A', 'B', 'C', 'D'],
      'answerIndex': 3,
      'explanation': '既存解説',
      'isPremium': true,
      'unitTags': ['tag-a', 'tag-b'],
      'unitId': 'health-unit',
    });

    expect(card.question, '既存問題');
    expect(card.choices, ['A', 'B', 'C', 'D']);
    expect(card.answerIndex, 3);
    expect(card.explanation, '既存解説');
    expect(card.isPremium, isTrue);
    expect(card.unitTags, ['tag-a', 'tag-b']);
    expect(card.unitId, 'health-unit');
    expect(card.stableId, isNull);
    expect(card.questionVersion, isNull);
    expect(card.sourceId, isNull);
    expect(card.sourceTitle, isNull);
    expect(card.sourceSection, isNull);
    expect(card.sourceVersion, isNull);
    expect(card.difficulty, isNull);
    expect(card.importance, isNull);
    expect(card.revisionTag, isNull);
  });

  test('current health app keeps legacy content hash identity', () {
    const card = QuizCard(
      stableId: 'HEALTH-EXPLICIT-ID',
      question: 'Question',
      choices: ['A', 'B'],
      answerIndex: 0,
    );

    expect(currentQuizApp.preferExplicitStableIds, isFalse);
    expect(stableIdForOriginal(card), '7590baaf53476d485545fe607ea0eb83');
    expect(stableIdForOriginal(card), legacyStableIdForOriginal(card));
  });
}
