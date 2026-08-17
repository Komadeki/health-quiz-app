import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/models/card.dart';
import 'package:health_quiz_app/utils/stable_id.dart';

void main() {
  test('QuizCard preserves qualification metadata', () {
    final card = QuizCard.fromJson({
      'stableId': 'DRONE-LAW-0001',
      'question': 'テスト問題',
      'choices': ['A', 'B', 'C'],
      'answerIndex': 1,
      'explanation': '解説',
      'unitId': 'law',
      'sourceTitle': '教則第5版',
      'sourceSection': '3.1.2',
      'difficulty': 3,
      'importance': 2,
      'revisionTag': 'v5_changed',
    });

    expect(card.stableId, 'DRONE-LAW-0001');
    expect(card.sourceSection, '3.1.2');
    expect(card.difficulty, 3);
    expect(card.importance, 2);
    expect(card.revisionTag, 'v5_changed');

    final shuffled = card.shuffled(randomize: false);
    expect(shuffled.stableId, card.stableId);
    expect(shuffled.sourceSection, card.sourceSection);
  });

  test('current health app keeps legacy content hash identity', () {
    const card = QuizCard(
      stableId: 'HEALTH-EXPLICIT-ID',
      question: 'Question',
      choices: ['A', 'B'],
      answerIndex: 0,
    );

    expect(stableIdForOriginal(card), isNot('HEALTH-EXPLICIT-ID'));
    expect(stableIdForOriginal(card), legacyStableIdForOriginal(card));
  });
}
