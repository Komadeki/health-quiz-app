import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/models/attempt_entry.dart';
import 'package:health_quiz_app/models/score_record.dart';
import 'package:health_quiz_app/models/quiz_session.dart';
import 'package:health_quiz_app/services/attempt_store.dart';
import 'package:health_quiz_app/services/score_saver.dart';
import 'package:health_quiz_app/services/score_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScoreRecord record({
  required String id,
  String? sessionId,
  int score = 2,
}) =>
    ScoreRecord(
      id: id,
      deckId: 'deck_m02',
      deckTitle: '現代社会と健康',
      score: score,
      total: 3,
      timestamp: 1794210000000,
      sessionId: sessionId,
      selectedUnitIds: const ['unit_alcohol_and_health'],
      unitBreakdown: const {'unit_alcohol_and_health': 3},
      tags: const {'alcohol': TagStat(correct: 2, wrong: 1)},
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('score saver retains detail and one score per session', () async {
    await ScoreSaver.save(record(id: 'one', sessionId: 'session-1'));
    final saved = await ScoreStore.instance.loadAll();
    expect(saved, hasLength(1));
    expect(saved.first.id, 'one');
    expect(saved.first.unitBreakdown, {'unit_alcohol_and_health': 3});
    expect(saved.first.selectedUnitIds, ['unit_alcohol_and_health']);
    expect(saved.first.tags?['alcohol']?.correct, 2);

    // A second save with the same ID/session updates, not duplicates.
    await ScoreSaver.save(record(id: 'one', sessionId: 'session-1'));
    expect(await ScoreStore.instance.loadAll(), hasLength(1));
  });

  test('records lacking legacy session IDs do not overwrite each other',
      () async {
    await AttemptStore().addScore(record(id: 'legacy-a'));
    await AttemptStore().addScore(record(id: 'legacy-b'));
    final saved = await ScoreStore.instance.loadAll();
    expect(saved.map((r) => r.id).toSet(), {'legacy-a', 'legacy-b'});
  });

  test('active session clear removes only the matching type', () async {
    const first = QuizSession(
      sessionId: 'a',
      deckId: 'mixed',
      itemIds: ['one'],
      currentIndex: 0,
      isFinished: false,
      type: 'review_test',
    );
    const second = QuizSession(
      sessionId: 'b',
      deckId: 'mixed',
      itemIds: ['two'],
      currentIndex: 0,
      isFinished: false,
      type: 'mix',
    );
    await ScoreSaver.saveActive(first);
    await ScoreSaver.saveActive(second);
    await ScoreSaver.clearActive('review_test');
    expect(await ScoreSaver.loadActive('review_test'), isNull);
    expect((await ScoreSaver.loadActive('mix'))?.sessionId, 'b');
  });
  test('retrying an answer checkpoint does not duplicate wrong history',
      () async {
    final entry = AttemptEntry(
      attemptId: 'same-answer',
      sessionId: 's',
      questionNumber: 1,
      unitId: 'u',
      cardId: 'c',
      question: 'Q',
      selectedIndex: 1,
      correctIndex: 2,
      isCorrect: false,
      durationMs: 1,
      timestamp: DateTime(2026),
      stableId: 'c',
    );
    await AttemptStore().add(entry);
    await AttemptStore().add(entry);
    expect(await AttemptStore().bySession('s'), hasLength(1));
    expect(await AttemptStore().getWrongFrequencyByStableId(), {'c': 1});
  });
}
