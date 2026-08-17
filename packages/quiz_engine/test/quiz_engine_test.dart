import 'dart:io';

import 'package:quiz_engine/quiz_engine.dart';
import 'package:test/test.dart';

void main() {
  test('decodes nested decks and quiz cards', () {
    final deck = Deck.fromJson({
      'id': 'deck_sample',
      'title': 'Sample',
      'units': [
        {
          'id': 'unit_sample',
          'title': 'Unit',
          'cards': [
            {
              'question': 'Question',
              'choices': ['A', 'B', 'C'],
              'answerIndex': 1,
              'unitTags': ['tag'],
            },
          ],
        },
      ],
    });

    expect(deck.cards, hasLength(1));
    expect(deck.cards.single.choices, hasLength(3));
    expect(deck.cards.single.tags, ['tag']);
    expect(deck.cardsFromUnits(['unit_sample']), deck.cards);
  });

  test('reorders choices without changing the correct answer', () {
    const card = QuizCard(
      question: 'Question',
      choices: ['A', 'B', 'C', 'D'],
      answerIndex: 2,
      stableId: 'question-001',
    );

    final reordered = card.withChoiceOrder([2, 0, 3, 1]);

    expect(reordered.choices, ['C', 'A', 'D', 'B']);
    expect(reordered.answerIndex, 0);
    expect(reordered.stableId, card.stableId);
  });

  test('round-trips legacy-compatible quiz sessions', () {
    final session = QuizSession.fromJson({
      'sessionId': 'session-001',
      'deckId': 'deck_sample',
      'itemIds': ['question-001'],
      'currentIndex': 0,
      'isFinished': false,
    });

    expect(session.type, 'normal');
    expect(QuizSession.decode(session.encode())?.itemIds, session.itemIds);
  });

  test('keeps attempt and score serialization compatible', () {
    final attempt = AttemptEntry.fromMap({
      'sessionId': 'session-001',
      'questionNumber': 1,
      'unit_id': 'unit_sample',
      'card_id': 'question-001',
      'question': 'Question',
      'selectedIndex': 0,
      'correctIndex': 1,
      'isCorrect': false,
      'durationMs': 1000,
      'timestamp': '2026-01-01T00:00:00.000Z',
    });
    final score = ScoreRecord(
      id: 'score-001',
      deckId: 'deck_sample',
      deckTitle: 'Sample',
      score: 0,
      total: 1,
      timestamp: 1,
      sessionId: attempt.sessionId,
    );

    expect(attempt.stableId, 'question-001');
    expect(AttemptEntry.fromJson(attempt.toJson()).cardId, attempt.cardId);
    expect(ScoreRecord.decodeList(ScoreRecord.encodeList([score])).single.id,
        score.id);
  });

  test('does not depend on the health app package', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      expect(
        file.readAsStringSync(),
        isNot(contains('package:health_quiz_app/')),
        reason: file.path,
      );
    }
  });
}
