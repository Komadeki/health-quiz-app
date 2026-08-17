import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/data/quiz_session_local_repository.dart';
import 'package:health_quiz_app/models/attempt_entry.dart';
import 'package:health_quiz_app/models/quiz_session.dart';
import 'package:health_quiz_app/models/score_record.dart';
import 'package:health_quiz_app/services/attempt_store.dart';
import 'package:health_quiz_app/services/score_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixture = jsonDecode(
    File(
      'test/fixtures/legacy_persistence_contracts.json',
    ).readAsStringSync(),
  ) as Map<String, dynamic>;

  Map<String, dynamic> fixtureMap(String key) =>
      Map<String, dynamic>.from(fixture[key] as Map);

  List<Map<String, dynamic>> fixtureList(String key) =>
      (fixture[key] as List<dynamic>)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

  test('legacy QuizSession decodes and defaults its missing type', () {
    final sessionJson = fixtureMap('session');
    final session = QuizSession.decode(jsonEncode(sessionJson));

    expect(session, isNotNull);
    expect(session!.sessionId, 'session-legacy-001');
    expect(session.deckId, 'deck_M01');
    expect(session.currentIndex, 1);
    expect(session.type, 'normal');
    expect(session.itemIds, [
      '7e15c4eadaac46dc91dd259e08704a9f',
      'de6009e05a4245df5fd1ce59645205b9',
    ]);
    expect(session.answers, {
      '7e15c4eadaac46dc91dd259e08704a9f': 1,
    });

    final roundTrip = QuizSession.decode(session.encode());
    expect(roundTrip?.sessionId, session.sessionId);
    expect(roundTrip?.itemIds, session.itemIds);
    expect(roundTrip?.type, 'normal');
  });

  test('active session loads from the published storage key', () async {
    SharedPreferences.setMockInitialValues({
      'active_quiz_session_v1': jsonEncode(fixtureMap('session')),
      'stable_id_version': '2',
    });
    final preferences = await SharedPreferences.getInstance();
    final repository = QuizSessionLocalRepository(preferences);

    await repository.migrateIfNeeded();
    final session = await repository.loadActive();

    expect(session?.sessionId, 'session-legacy-001');
    expect(session?.itemIds.first, '7e15c4eadaac46dc91dd259e08704a9f');
  });

  test('legacy attempt aliases preserve review question identity', () async {
    SharedPreferences.setMockInitialValues({
      'attempts.v1': jsonEncode(fixtureList('attempts')),
    });

    final attempts = await AttemptStore().recent();
    final byId = {for (final attempt in attempts) attempt.attemptId: attempt};
    final wrongIds = await AttemptStore().getWrongStableIdsUnique(
      onlySessionIds: const ['session-legacy-001'],
    );

    expect(attempts, hasLength(2));
    expect(byId['attempt-legacy-001']?.questionNumber, 1);
    expect(byId['attempt-legacy-001']?.durationMs, 1250);
    expect(
      byId['attempt-legacy-001']?.stableId,
      '7e15c4eadaac46dc91dd259e08704a9f',
    );
    expect(wrongIds, ['7e15c4eadaac46dc91dd259e08704a9f']);
  });

  test('current and legacy score storage formats remain readable', () async {
    SharedPreferences.setMockInitialValues({
      'scores_v2': jsonEncode(fixtureList('scoresV2')),
      'scores.v2': jsonEncode(fixtureList('scoresLegacyV2')),
      'scores.v1': jsonEncode(fixtureList('scoresLegacyV1')),
    });

    final scores = await ScoreStore.instance.loadAll();
    final byId = {for (final score in scores) score.id: score};

    expect(scores, hasLength(3));
    expect(byId['score-current-001']?.sessionId, 'session-legacy-001');
    expect(byId['score-current-001']?.unitBreakdown, {
      'unit_health_concepts': 2,
    });
    expect(byId['score-legacy-v2-001']?.durationSec, isNull);
    expect(
      byId['deck_M03_2026-01-04T03:04:10.000Z']?.score,
      7,
    );
  });

  test('new attempts and scores still write the published storage keys',
      () async {
    SharedPreferences.setMockInitialValues({});
    final attempt = AttemptEntry.fromMap(fixtureList('attempts').first);
    final score = ScoreRecord.fromJson(fixtureList('scoresV2').first);

    expect(attempt.questionVersion, isNull);
    expect(attempt.bankRevision, isNull);
    expect(score.bankRevision, isNull);
    expect(score.examProfileVersion, isNull);

    await AttemptStore().add(attempt);
    await AttemptStore().addScore(score);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('attempts_v1'), isNotNull);
    expect(preferences.getString('scores_v2'), isNotNull);
  });
}
