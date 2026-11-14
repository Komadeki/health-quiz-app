import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/models/attempt_entry.dart';
import 'package:health_quiz_app/models/card.dart';
import 'package:health_quiz_app/models/quiz_session.dart';
import 'package:health_quiz_app/services/quiz_resume_progress.dart';

void main() {
  const cards = <QuizCard>[
    QuizCard(
      question: '問題A',
      choices: ['正解', '誤答'],
      answerIndex: 0,
      unitId: 'u',
      unitTags: ['health'],
    ),
    QuizCard(
      question: '問題B',
      choices: ['正解', '誤答'],
      answerIndex: 1,
      unitId: 'u',
      unitTags: ['health', 'sleep'],
    ),
    QuizCard(
      question: '問題C',
      choices: ['正解', '誤答'],
      answerIndex: 0,
      unitId: 'u',
      unitTags: ['food'],
    ),
  ];

  QuizSession session({
    int currentIndex = 2,
    Map<String, dynamic>? answers,
  }) =>
      QuizSession(
        sessionId: 'session-one',
        deckId: 'deck_m02',
        itemIds: const ['a', 'b', 'c'],
        currentIndex: currentIndex,
        isFinished: false,
        answers: answers,
      );

  AttemptEntry attempt({
    required int number,
    required String stableId,
    required bool correct,
    String sessionId = 'session-one',
  }) =>
      AttemptEntry(
        sessionId: sessionId,
        questionNumber: number,
        unitId: 'u',
        cardId: stableId,
        question: cards[number - 1].question,
        selectedIndex: correct ? cards[number - 1].answerIndex + 1 : 1,
        correctIndex: cards[number - 1].answerIndex + 1,
        isCorrect: correct,
        durationMs: 900,
        timestamp: DateTime(2026, 11, 9),
        stableId: stableId,
      );

  test('restores score and tag stats from saved answers', () {
    final result = restoreQuizProgress(
      session: session(answers: {
        'a': {'selectedIndex': 0, 'isCorrect': true},
        'b': {'selectedIndex': 0, 'isCorrect': false},
      }),
      sequence: cards,
      stableOrder: const ['a', 'b', 'c'],
      attempts: const [],
    );
    expect(result.correctCount, 1);
    expect(result.tagCorrect, {'health': 1});
    expect(result.tagWrong, {'health': 1, 'sleep': 1});
    expect(result.answers, contains('a'));
    expect(result.answers, contains('b'));
  });

  test('legacy answerless session restores from matching attempts', () {
    final result = restoreQuizProgress(
      session: session(answers: const {}),
      sequence: cards,
      stableOrder: const ['a', 'b', 'c'],
      attempts: [
        attempt(number: 2, stableId: 'b', correct: false),
        attempt(number: 1, stableId: 'a', correct: true),
        attempt(number: 1, stableId: 'a', correct: false, sessionId: 'other'),
      ],
    );
    expect(result.correctCount, 1);
    expect(result.tagWrong, {'health': 1, 'sleep': 1});
  });

  test('missing past answer prevents inaccurate zero-score resume', () {
    expect(
      () => restoreQuizProgress(
        session: session(),
        sequence: cards,
        stableOrder: const ['a', 'b', 'c'],
        attempts: [attempt(number: 1, stableId: 'a', correct: true)],
      ),
      throwsFormatException,
    );
  });

  test('inconsistent saved answer is rejected', () {
    expect(
      () => restoreQuizProgress(
        session: session(answers: {
          'a': {'selectedIndex': 0, 'isCorrect': false},
          'b': {'selectedIndex': 0, 'isCorrect': false},
        }),
        sequence: cards,
        stableOrder: const ['a', 'b', 'c'],
        attempts: const [],
      ),
      throwsFormatException,
    );
  });

  test('fully answered but unfinished session preserves last mark', () {
    final result = restoreQuizProgress(
      session: session(
        currentIndex: 3,
        answers: {
          'a': {'selectedIndex': 0, 'isCorrect': true},
          'b': {'selectedIndex': 0, 'isCorrect': false},
          'c': {'selectedIndex': 0, 'isCorrect': true},
        },
      ),
      sequence: cards,
      stableOrder: const ['a', 'b', 'c'],
      attempts: const [],
    );
    expect(result.correctCount, 2);
  });
  test('legacy correctness remains valid through a second resume', () {
    final first = restoreQuizProgress(
      session: session(),
      sequence: cards,
      stableOrder: const ['a', 'b', 'c'],
      attempts: [
        attempt(number: 1, stableId: 'a', correct: true),
        attempt(number: 2, stableId: 'b', correct: false)
      ],
    );
    expect((first.answers['a'] as Map).containsKey('selectedIndex'), isFalse);
    final second = restoreQuizProgress(
      session: session(answers: first.answers),
      sequence: cards,
      stableOrder: const ['a', 'b', 'c'],
      attempts: const [],
    );
    expect(second.correctCount, 1);
  });
}
