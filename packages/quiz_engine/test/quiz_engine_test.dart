import 'dart:convert';
import 'dart:io';

import 'package:quiz_engine/quiz_engine.dart';
import 'package:test/test.dart';

void main() {
  group('question identity policies', () {
    test('legacy v1 preserves the published health hashes', () {
      const policy = LegacyHashQuestionIdentityV1();
      const card = QuizCard(
        stableId: 'EXPLICIT-ID-MUST-NOT-WIN',
        question: 'WHO憲章で定義されている健康の意味はどれか？',
        choices: [
          '病気でない状態',
          '心身ともに良好な状態',
          '体だけが丈夫な状態',
          '社会的に孤立していない状態',
        ],
        answerIndex: 1,
      );

      expect(policy.stableIdFor(card), '7e15c4eadaac46dc91dd259e08704a9f');
    });

    test('explicit v1 requires an authored ID without hash fallback', () {
      const policy = ExplicitQuestionIdentityV1();
      const identified = QuizCard(
        stableId: ' FIXTURE-Q-000001 ',
        question: 'Question',
        choices: ['A', 'B', 'C'],
        answerIndex: 0,
      );
      const missing = QuizCard(
        question: 'Question',
        choices: ['A', 'B', 'C'],
        answerIndex: 0,
      );

      expect(policy.stableIdFor(identified), 'FIXTURE-Q-000001');
      expect(
        () => policy.stableIdFor(missing),
        throwsA(isA<QuestionIdentityException>()),
      );
    });
  });

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

  test('decodes a fifth CSV choice and preserves answer E', () {
    final card = QuizCard.fromRowWithHeader(
      const {
        'question': 0,
        'choice1': 1,
        'choice2': 2,
        'choice3': 3,
        'choice4': 4,
        'choice5': 5,
        'answer_index': 6,
      },
      const ['Question', 'A', 'B', 'C', 'D', 'E', '5'],
    );

    expect(card.choices, ['A', 'B', 'C', 'D', 'E']);
    expect(card.answerIndex, 4);
  });

  test('qualification fixture runtime decodes with explicit identity', () {
    final runtime = jsonDecode(
      File(
        '../../question_banks/qualification_fixture/generated/'
        'qualification_fixture_bank.json',
      ).readAsStringSync(),
    ) as Map<String, dynamic>;
    final deck = Deck.fromJson(
      Map<String, dynamic>.from(
          (runtime['decks'] as List<dynamic>).single as Map),
    );
    const identity = ExplicitQuestionIdentityV1();

    expect(deck.cards, hasLength(2));
    expect(
      deck.cards.map(identity.stableIdFor),
      containsAll(['FIXTURE-Q-000001', 'FIXTURE-Q-000002']),
    );
    final versioned = deck.cards.singleWhere(
      (card) => card.stableId == 'FIXTURE-Q-000002',
    );
    expect(versioned.questionVersion, 2);
    expect(versioned.sourceId, 'FIXTURE-SRC-001');
    expect(versioned.sourceVersion, '2026.1');
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
      bankRevision: 'fixture-bank-v1',
      examProfileVersion: 'fixture-exam-v1',
    );

    expect(attempt.stableId, 'question-001');
    expect(attempt.questionVersion, isNull);
    expect(attempt.bankRevision, isNull);
    expect(AttemptEntry.fromJson(attempt.toJson()).cardId, attempt.cardId);
    final decodedScore =
        ScoreRecord.decodeList(ScoreRecord.encodeList([score])).single;
    expect(decodedScore.id, score.id);
    expect(decodedScore.bankRevision, 'fixture-bank-v1');
    expect(decodedScore.examProfileVersion, 'fixture-exam-v1');
  });

  test('round-trips nullable question provenance', () {
    final attempt = AttemptEntry.fromMap({
      'sessionId': 'session-002',
      'questionNumber': 1,
      'unitId': 'unit_sample',
      'cardId': 'FIXTURE-Q-000001',
      'question': 'Question',
      'selectedIndex': 0,
      'correctIndex': 0,
      'isCorrect': true,
      'durationMs': 100,
      'timestamp': '2026-01-01T00:00:00.000Z',
      'stableId': 'FIXTURE-Q-000001',
      'questionVersion': 2,
      'bankRevision': 'fixture-bank-v2',
    });

    final decoded = AttemptEntry.fromJson(attempt.toJson());
    expect(decoded.questionVersion, 2);
    expect(decoded.bankRevision, 'fixture-bank-v2');
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
