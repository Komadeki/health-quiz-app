import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory directory;
  late JsonLinesLearningRepository repository;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('factory-learning-');
    repository = JsonLinesLearningRepository(
      appKey: 'fixture_app',
      directoryProvider: () async => directory,
    );
  });

  tearDown(() async {
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('inserts events and enforces duplicate and attempt numbering', () async {
    final first = _event('attempt-1', attemptNumber: 1);
    await repository.recordAnswer(first);
    await repository.recordAnswer(first);

    expect(await repository.countAttempts('Q-1'), 1);
    expect(
      () => repository.recordAnswer(_event('attempt-1', attemptNumber: 2)),
      throwsStateError,
    );
    expect(
      () => repository.recordAnswer(_event('attempt-2', attemptNumber: 3)),
      throwsStateError,
    );

    await repository.recordAnswer(
      _event(
        'attempt-2',
        attemptNumber: 2,
        correct: false,
        answeredAt: DateTime.utc(2026, 1, 2),
      ),
    );
    expect(await repository.countAttempts('Q-1'), 2);
    expect(
      (await repository.loadRecentEvents(limit: 1)).single.attemptId,
      'attempt-2',
    );
  });

  test('queries unanswered and most-recent incorrect question IDs', () async {
    await repository.recordAnswer(_event('a1', questionId: 'Q-1'));
    await repository.recordAnswer(
      _event('a2', questionId: 'Q-2', correct: false),
    );
    await repository.recordAnswer(
      _event(
        'a3',
        questionId: 'Q-2',
        correct: true,
        attemptNumber: 2,
        answeredAt: DateTime.utc(2026, 1, 2),
      ),
    );
    await repository.recordAnswer(
      _event('a4', questionId: 'Q-3', correct: false),
    );

    expect(
      await repository.loadUnansweredQuestionIds(['Q-1', 'Q-2', 'Q-3', 'Q-4']),
      {'Q-4'},
    );
    expect(await repository.loadIncorrectQuestionIds(['Q-1', 'Q-2', 'Q-3']), {
      'Q-3',
    });
    expect(await repository.loadEventsByUnit('unit-b'), hasLength(1));
  });

  test('persists practice and mock history separately', () async {
    await repository.recordSessionHistory(
      _history('practice-1', LearningModeV1.unitPractice),
    );
    await repository.recordSessionHistory(
      _history('mock-1', LearningModeV1.mockExam),
    );

    expect(await repository.loadSessionHistory(), hasLength(2));
    expect((await repository.loadMockExamHistory()).single.sessionId, 'mock-1');
    await repository.recordSessionHistory(
      _history('mock-1', LearningModeV1.mockExam),
    );
    expect(await repository.loadSessionHistory(), hasLength(2));
    expect(
      () => repository.recordSessionHistory(
        _history(
          'mock-1',
          LearningModeV1.mockExam,
          correctCount: 0,
        ),
      ),
      throwsStateError,
    );
  });

  test('fails closed for unsupported journal schema', () async {
    final namespace = Directory(
      '${directory.path}${Platform.pathSeparator}qualification_factory'
      '${Platform.pathSeparator}fixture_app',
    );
    await namespace.create(recursive: true);
    final file = File(
      '${namespace.path}${Platform.pathSeparator}learning.v1.jsonl',
    );
    await file.writeAsString(
      '${jsonEncode({
            'record_type': 'schema',
            'schema_version': 99,
            'app_key': 'fixture_app'
          })}\n',
    );

    expect(repository.loadAllEvents, throwsFormatException);
  });

  test('active session and entitlement caches are app-key namespaced',
      () async {
    SharedPreferences.setMockInitialValues({});
    const sessionStore = SharedPreferencesQualificationSessionStore(
      appKey: 'fixture_app',
    );
    final session = QualificationSessionV1(
      sessionId: 'session-1',
      appKey: 'fixture_app',
      bankRevision: 'bank-v1',
      mode: LearningModeV1.unitPractice,
      questionIds: const ['Q-1'],
      currentIndex: 0,
      committedResponses: const {},
      startedAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    await sessionStore.save(session);
    expect((await sessionStore.load())!.sessionId, 'session-1');

    const cache = SharedPreferencesFullUnlockEntitlementCache(
      appKey: 'fixture_app',
      productId: 'fixture_full_unlock',
    );
    await cache.merge(
      EntitlementSnapshot(
        ownedProductIds: const {'fixture_full_unlock'},
      ),
    );
    expect((await cache.load()).ownedProductIds, {'fixture_full_unlock'});

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.containsKey(
        'qualification_factory.fixture_app.active_session.v1',
      ),
      isTrue,
    );
    expect(
      preferences.containsKey(
        'qualification_factory.fixture_app.full_unlock.v1',
      ),
      isTrue,
    );
  });
}

LearningEventV1 _event(
  String attemptId, {
  String questionId = 'Q-1',
  bool correct = true,
  int attemptNumber = 1,
  DateTime? answeredAt,
}) {
  return LearningEventV1(
    appKey: 'fixture_app',
    sessionId: 'session-1',
    attemptId: attemptId,
    questionId: questionId,
    questionVersion: 1,
    bankRevision: 'bank-v1',
    unitId: questionId == 'Q-3' ? 'unit-b' : 'unit-a',
    knowledgeTarget: null,
    selectedChoice: 0,
    correct: correct,
    answeredAt: answeredAt ?? DateTime.utc(2026, 1, 1),
    responseDurationMs: 10,
    attemptNumber: attemptNumber,
    mode: LearningModeV1.unitPractice,
    appVersion: '1.0.0',
  );
}

SessionHistoryV1 _history(
  String id,
  LearningModeV1 mode, {
  int correctCount = 1,
}) {
  return SessionHistoryV1(
    appKey: 'fixture_app',
    sessionId: id,
    mode: mode,
    questionIds: const ['Q-1'],
    correctCount: correctCount,
    completedAt: DateTime.utc(2026),
    examProfileVersion: mode == LearningModeV1.mockExam ? 'exam-v1' : null,
  );
}
