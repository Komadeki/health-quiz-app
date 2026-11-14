import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:health_quiz_app/features/exam/exam_question.dart';
import 'package:health_quiz_app/features/exam/exam_session.dart';
import 'package:health_quiz_app/features/exam/exam_session_store.dart';
import 'package:health_quiz_app/services/score_store.dart';

const questions = [
  ExamQuestion(
      id: 'choice',
      unitId: 'u1',
      question: '4択',
      type: ExamQuestionType.choice,
      answer: '1',
      choices: ['b', 'a', 'c', 'd'],
      explanation: 'A'),
  ExamQuestion(
      id: 'fill',
      unitId: 'u2',
      question: '穴埋め',
      type: ExamQuestionType.fill,
      answer: 'たんぱく質',
      acceptedAnswers: ['タンパク質'],
      explanation: 'B'),
  ExamQuestion(
      id: 'tf',
      unitId: 'u2',
      question: '正誤',
      type: ExamQuestionType.trueFalse,
      answer: '×',
      explanation: 'C'),
];
ExamSession session({String id = 'exam-test', bool submitted = false}) =>
    ExamSession(
      id: id,
      questions: questions,
      unitTitles: const {'u1': '単元1', 'u2': '単元2'},
      startedAt: DateTime(2026, 11, 14),
      index: 1,
      elapsedSeconds: 42,
      responses: const {'choice': '1', 'fill': ' タンパク質　', 'tf': ''},
      submittedAt: submitted ? DateTime(2026, 11, 14, 21) : null,
    );

class FailingPreferences extends InMemorySharedPreferencesStore {
  FailingPreferences() : super.withData({});
  bool failScores = false;
  bool failSnapshots = false;
  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if ((failScores && key.endsWith('scores_v2')) ||
        (failSnapshots && key.contains('health_term_exam_session_v1'))) {
      return Future.value(false);
    }
    return super.setValue(valueType, key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('round-trip preserves answers, choice order, elapsed time and position',
      () {
    final original = session();
    final decoded =
        ExamSession.fromJson(jsonDecode(jsonEncode(original.toJson())));
    expect(decoded.questions.first.choices, ['b', 'a', 'c', 'd']);
    expect(decoded.responses, original.responses);
    expect(decoded.index, 1);
    expect(decoded.elapsedSeconds, 42);
    expect(decoded.score, 2);
    expect(decoded.submitted, isFalse);
    expect(() => decoded.toScoreRecord(), throwsStateError);
  });

  test('rapid checkpoints persist newest answer, including a blank edit',
      () async {
    final store = ExamSessionStore();
    final first = session();
    final last =
        first.progress(responses: {'fill': ''}, index: 2, elapsedSeconds: 50);
    await Future.wait([store.save(first), store.save(last)]);
    final loaded = (await store.loadActive())!;
    expect(loaded.responses, {'fill': ''});
    expect(loaded.index, 2);
    expect(loaded.elapsedSeconds, 50);
    expect(
        (await SharedPreferences.getInstance())
            .getString('active_quiz_session_v1'),
        isNull);
  });

  test('finalization is idempotent and history retains all answer formats',
      () async {
    final store = ExamSessionStore();
    final submitted = session(submitted: true);
    await store.finish(submitted);
    await store.finish(submitted);
    expect(await store.loadActive(), isNull);
    final saved = (await ScoreStore.instance.loadAll()).single;
    expect(saved.score, 2);
    expect(saved.total, 3);
    expect(saved.unitBreakdown, {'u1': 1, 'u2': 2});
    expect(saved.tags!['形式:穴埋め']!.correct, 1);
    expect(saved.tags!['形式:○×']!.wrong, 1);
    expect((await store.load(submitted.id))!.responses['tf'], '');
  });

  test('failed result save keeps submitted checkpoint for retry', () async {
    final platform = FailingPreferences()..failScores = true;
    SharedPreferencesStorePlatform.instance = platform;
    SharedPreferences.resetStatic();
    final store = ExamSessionStore();
    await expectLater(store.finish(session(submitted: true)), throwsStateError);
    expect((await store.loadActive())!.submitted, isTrue);
    platform.failScores = false;
    await store.finish((await store.loadActive())!);
    expect(await store.loadActive(), isNull);
    expect(await ScoreStore.instance.loadAll(), hasLength(1));
  });

  test('failed checkpoint can be retried without a poisoned queue', () async {
    final platform = FailingPreferences()..failSnapshots = true;
    SharedPreferencesStorePlatform.instance = platform;
    SharedPreferences.resetStatic();
    final store = ExamSessionStore();
    await expectLater(store.save(session()), throwsStateError);
    platform.failSnapshots = false;
    await store.save(session());
    expect((await store.loadActive())!.id, 'exam-test');
  });

  test('corrupt progress is rejected and never erased', () async {
    SharedPreferences.setMockInitialValues({
      ExamSessionStore.activeKey: 'corrupt',
      ExamSessionStore.sessionKey('corrupt'): '{bad json',
    });
    await expectLater(ExamSessionStore().loadActive(), throwsFormatException);
    expect(
        (await SharedPreferences.getInstance())
            .getString(ExamSessionStore.activeKey),
        'corrupt');
    final json = session().toJson()..['index'] = 30;
    expect(() => ExamSession.fromJson(json), throwsFormatException);
    json['index'] = 0;
    json['responses'] = {'choice': '4'};
    expect(() => ExamSession.fromJson(json), throwsFormatException);
  });

  test('clearing an older exam does not remove another active exam', () async {
    final store = ExamSessionStore();
    await store.save(session(id: 'one'));
    await store.save(session(id: 'two'));
    await store.clearActive('one');
    expect((await store.loadActive())!.id, 'two');
  });
  test('deleting an exam result preserves an unrelated active checkpoint',
      () async {
    final store = ExamSessionStore();
    await store.finish(session(submitted: true));
    await store.save(session(id: 'active'));
    await store.deleteResult('exam-test');
    expect(await store.load('exam-test'), isNull);
    expect((await store.loadActive())!.id, 'active');
    await store.deleteResult('active');
    expect((await store.loadActive())!.id, 'active');
  });
  test('unreadable progress is retained before starting another exam',
      () async {
    SharedPreferences.setMockInitialValues({
      ExamSessionStore.activeKey: 'corrupt',
      ExamSessionStore.sessionKey('corrupt'): '{broken',
      'owned_deck_ids': <String>['deck_m01'],
    });
    await ExamSessionStore().archiveUnreadableActive();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ExamSessionStore.sessionKey('corrupt')), '{broken');
    final backupKey = prefs
        .getKeys()
        .singleWhere((k) => k.startsWith('health_term_exam_recovery_v1__'));
    final backup = jsonDecode(prefs.getString(backupKey)!);
    expect(backup['snapshot'], '{broken');
    expect(prefs.getStringList('owned_deck_ids'), ['deck_m01']);
    expect(await ExamSessionStore().loadActive(), isNull);
  });
}
