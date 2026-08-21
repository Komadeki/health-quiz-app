import 'dart:io';

import 'package:quiz_engine/quiz_engine.dart';
import 'package:test/test.dart';

void main() {
  test('Factory domain remains UI and device independent', () {
    for (final file in Directory('lib/src/factory')
        .listSync(recursive: true)
        .whereType<File>()) {
      final source = file.readAsStringSync();
      expect(source, isNot(contains('package:flutter/')), reason: file.path);
      expect(source, isNot(contains('package:shared_preferences/')),
          reason: file.path);
      expect(source, isNot(contains('package:path_provider/')),
          reason: file.path);
    }
  });

  group('LearningEventV1', () {
    test('round trips permanent identity, version, revision and namespace', () {
      final event = _event(
        attemptId: 'attempt-1',
        questionId: 'FIXTURE-Q-000001',
        questionVersion: 3,
        bankRevision: 'bank-v2',
      );

      final decoded = LearningEventV1.fromJson(event.toJson());

      expect(decoded.toJson(), event.toJson());
      expect(decoded.toJson()['schema_version'], 1);
      expect(decoded.questionId, 'FIXTURE-Q-000001');
      expect(decoded.questionVersion, 3);
      expect(decoded.bankRevision, 'bank-v2');
      expect(decoded.appKey, 'fixture_app');
    });

    test('rejects negative duration and non-UTC timestamp', () {
      expect(() => _event(responseDurationMs: -1), throwsArgumentError);
      expect(
        () => _event(answeredAt: DateTime(2026, 1, 1)),
        throwsArgumentError,
      );
    });
  });

  group('qualification session', () {
    test('round trips immutable sequence and committed response', () {
      final session = QualificationSessionV1(
        sessionId: 'session-1',
        appKey: 'fixture_app',
        bankRevision: 'bank-v1',
        mode: LearningModeV1.unitPractice,
        questionIds: const ['Q-1', 'Q-2'],
        currentIndex: 1,
        committedResponses: {
          'Q-1': SessionResponseV1(
            choiceIndex: 0,
            attemptId: 'attempt-1',
            answeredAt: DateTime.utc(2026),
          ),
        },
        startedAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026, 1, 1, 0, 1),
        unitId: 'unit-a',
      );

      final decoded = QualificationSessionV1.fromJson(session.toJson());

      expect(decoded.questionIds, ['Q-1', 'Q-2']);
      expect(decoded.currentQuestionId, 'Q-2');
      expect(decoded.committedResponses['Q-1']!.choiceIndex, 0);
      expect(decoded.toJson()['schema_version'], 1);
    });

    test('rejects duplicate questions and out-of-range index', () {
      expect(
        () => QualificationSessionV1(
          sessionId: 'session-1',
          appKey: 'fixture_app',
          bankRevision: 'bank-v1',
          mode: LearningModeV1.randomPractice,
          questionIds: const ['Q-1', 'Q-1'],
          currentIndex: 3,
          committedResponses: const {},
          startedAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
        throwsArgumentError,
      );
    });
  });

  group('practice selection', () {
    const questions = [
      QuestionCandidate(questionId: 'Q-1', unitId: 'unit-a', isPremium: false),
      QuestionCandidate(questionId: 'Q-2', unitId: 'unit-a', isPremium: true),
      QuestionCandidate(questionId: 'Q-3', unitId: 'unit-b', isPremium: false),
    ];
    final engine = PracticeSelectionEngine(
      canAccess: (question) => !question.isPremium,
      randomizer: const IdentityQuestionRandomizer(),
    );

    test(
      'unit and deterministic random filter inaccessible premium content',
      () {
        expect(engine.selectUnit(questions, 'unit-a'), ['Q-1']);
        expect(engine.selectRandom(questions, count: 2), ['Q-1', 'Q-3']);
      },
    );

    test('unanswered, incorrect-most-recent and retry are shared', () {
      final incorrect = _event(
        attemptId: 'attempt-1',
        questionId: 'Q-1',
        correct: false,
        answeredAt: DateTime.utc(2026, 1, 1),
      );
      final corrected = _event(
        attemptId: 'attempt-2',
        questionId: 'Q-1',
        correct: true,
        attemptNumber: 2,
        answeredAt: DateTime.utc(2026, 1, 2),
      );
      final latestIncorrect = _event(
        attemptId: 'attempt-3',
        questionId: 'Q-3',
        correct: false,
        answeredAt: DateTime.utc(2026, 1, 3),
      );

      expect(engine.selectUnanswered(questions, [incorrect]), ['Q-3']);
      expect(
        engine.selectIncorrect(questions, [
          incorrect,
          corrected,
          latestIncorrect,
        ]),
        ['Q-3'],
      );
      expect(engine.selectRetry(questions, ['Q-2', 'Q-3']), ['Q-3']);
    });
  });

  test(
    'progress uses permanent IDs and repeated attempts do not inflate completion',
    () {
      const questions = [
        QuestionCandidate(
          questionId: 'Q-1',
          unitId: 'unit-a',
          isPremium: false,
        ),
        QuestionCandidate(
          questionId: 'Q-2',
          unitId: 'unit-a',
          isPremium: false,
        ),
      ];
      final snapshot = const ProgressCalculatorV1().calculate(questions, [
        _event(attemptId: 'a1', questionId: 'Q-1', correct: false),
        _event(
          attemptId: 'a2',
          questionId: 'Q-1',
          correct: true,
          attemptNumber: 2,
          answeredAt: DateTime.utc(2026, 1, 2),
        ),
      ]);

      expect(snapshot.overall.completedQuestions, 1);
      expect(snapshot.overall.attemptCount, 2);
      expect(snapshot.overall.unansweredCount, 1);
      expect(snapshot.byUnit['unit-a']!.accuracy, .5);
    },
  );

  group('mock exam', () {
    final profile = MockExamProfileV1(
      profileVersion: 'exam-v1',
      questionCount: 2,
      timeLimitMinutes: null,
      allocations: const [
        ExamUnitAllocationV1(unitId: 'unit-a', questionCount: 1),
        ExamUnitAllocationV1(unitId: 'unit-b', questionCount: 1),
      ],
      overallPassPercent: null,
      sectionPassRules: const [],
      shuffleQuestions: false,
    );
    final engine = MockExamEngineV1(
      randomizer: const IdentityQuestionRandomizer(),
    );

    test('selection follows allocation and deterministic order', () {
      final sequence = engine.createQuestionSequence(
        profile: profile,
        accessibleQuestions: const [
          QuestionCandidate(
            questionId: 'A-1',
            unitId: 'unit-a',
            isPremium: false,
          ),
          QuestionCandidate(
            questionId: 'B-1',
            unitId: 'unit-b',
            isPremium: false,
          ),
        ],
      );
      expect(sequence, ['A-1', 'B-1']);
    });

    test('scores sections without fabricating pass/fail', () {
      final result = engine.score(
        profile: profile,
        questions: const [
          MockExamQuestionV1(
            questionId: 'A-1',
            unitId: 'unit-a',
            correctChoiceIndex: 0,
          ),
          MockExamQuestionV1(
            questionId: 'B-1',
            unitId: 'unit-b',
            correctChoiceIndex: 1,
          ),
        ],
        responses: const {'A-1': 0, 'B-1': 0},
      );
      expect(result.correctCount, 1);
      expect(result.sections['unit-a']!.correctCount, 1);
      expect(result.passed, isNull);
    });

    test('reports pass only when rules are configured', () {
      final ruled = MockExamProfileV1(
        profileVersion: 'exam-v2',
        questionCount: 1,
        timeLimitMinutes: 10,
        allocations: const [],
        overallPassPercent: 70,
        sectionPassRules: const [],
        shuffleQuestions: true,
      );
      final result = engine.score(
        profile: ruled,
        questions: const [
          MockExamQuestionV1(
            questionId: 'Q-1',
            unitId: 'unit-a',
            correctChoiceIndex: 0,
          ),
        ],
        responses: const {'Q-1': 0},
      );
      expect(result.passed, isTrue);
    });
  });

  test('weakness and recommendation fall back to units deterministically', () {
    const questions = [
      QuestionCandidate(questionId: 'Q-1', unitId: 'unit-a', isPremium: false),
      QuestionCandidate(questionId: 'Q-2', unitId: 'unit-b', isPremium: false),
    ];
    final weakness = const WeaknessCalculatorV1().calculate(questions, [
      _event(attemptId: 'a1', questionId: 'Q-1', correct: false),
    ]);
    final recommendation = const DeterministicRecommendationEngine().recommend(
      questions: questions,
      weakness: weakness,
    );

    expect(weakness.byKnowledgeTarget, isEmpty);
    expect(weakness.byUnit['unit-a']!.correctness, 0);
    expect(recommendation!.unitId, 'unit-b');
    expect(recommendation.reasonCode, 'unanswered_unit');
  });

  test(
    'empty history recommendation and prediction remain safe/unavailable',
    () {
      final weakness = const WeaknessCalculatorV1().calculate(
        const [],
        const [],
      );
      final recommendation = const DeterministicRecommendationEngine()
          .recommend(questions: const [], weakness: weakness);
      final progress = const ProgressCalculatorV1().calculate(
        const [],
        const [],
      );
      final prediction = const UnavailablePredictionEngine().evaluate(
        LearningFeatureSnapshot(
          createdAt: DateTime.utc(2026),
          progress: progress,
          weakness: weakness,
        ),
      );

      expect(recommendation, isNull);
      expect(prediction.available, isFalse);
      expect(prediction.value, isNull);
    },
  );
}

LearningEventV1 _event({
  String attemptId = 'attempt-1',
  String questionId = 'Q-1',
  int questionVersion = 1,
  String bankRevision = 'bank-v1',
  bool correct = true,
  DateTime? answeredAt,
  int responseDurationMs = 100,
  int attemptNumber = 1,
}) {
  return LearningEventV1(
    appKey: 'fixture_app',
    sessionId: 'session-1',
    attemptId: attemptId,
    questionId: questionId,
    questionVersion: questionVersion,
    bankRevision: bankRevision,
    unitId: questionId == 'Q-3' ? 'unit-b' : 'unit-a',
    knowledgeTarget: null,
    selectedChoice: 0,
    correct: correct,
    answeredAt: answeredAt ?? DateTime.utc(2026, 1, 1),
    responseDurationMs: responseDurationMs,
    attemptNumber: attemptNumber,
    mode: LearningModeV1.unitPractice,
    appVersion: '1.0.0',
  );
}
