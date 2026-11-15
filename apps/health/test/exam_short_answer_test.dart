// Retain Flutter 3.47 compatibility while Flutter 3.50 deprecates this import.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/features/exam/exam_question.dart';
import 'package:health_quiz_app/features/exam/exam_runner_screen.dart';
import 'package:health_quiz_app/features/exam/exam_session.dart';
import 'package:health_quiz_app/features/exam/exam_session_store.dart';
import 'package:health_quiz_app/services/score_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const shortAnswer = ExamQuestion(
  id: 'short',
  unitId: 'u',
  question: 'ウイルスの略称を英字3文字で答えなさい。',
  type: ExamQuestionType.shortAnswer,
  answer: 'HIV',
  explanation: 'ウイルスの略称。',
);
const questions = [
  ExamQuestion(
      id: 'choice',
      unitId: 'u',
      question: '選択問題',
      type: ExamQuestionType.choice,
      answer: '0',
      choices: ['A', 'B', 'C', 'D'],
      explanation: '解説'),
  ExamQuestion(
      id: 'fill',
      unitId: 'u',
      question: '体の組織の材料は（　）',
      type: ExamQuestionType.fill,
      answer: 'たんぱく質',
      acceptedAnswers: ['タンパク質'],
      explanation: '解説'),
  ExamQuestion(
      id: 'tf',
      unitId: 'u',
      question: '正誤判断',
      type: ExamQuestionType.trueFalse,
      answer: '○',
      explanation: '解説'),
  shortAnswer,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('short answers use explicit aliases and never keyword containment', () {
    const q = ExamQuestion(
        id: 'short-ja',
        unitId: 'u',
        question: '名称を答える',
        type: ExamQuestionType.shortAnswer,
        answer: '健康寿命',
        acceptedAnswers: ['けんこうじゅみょう'],
        explanation: '解説');
    expect(q.isCorrect('　けんこうじゅみょう '), isTrue);
    expect(q.isCorrect('健康寿命ではない'), isFalse);
    expect(q.isCorrect('健康寿命または平均寿命'), isFalse);
    expect(q.isCorrect('平均寿命'), isFalse);
    expect(q.isCorrect(''), isFalse);
    expect(shortAnswer.isCorrect(' ＨｉＶ '), isTrue);
    expect(shortAnswer.isCorrect('AIDS'), isFalse);
    expect(q.typeLabel, '短答記述');
    expect(
        ExamQuestion.fromJson(q.toJson()).type, ExamQuestionType.shortAnswer);
    expect(
        () => ExamQuestion.fromJson({
              ...q.toJson(),
              'choices': ['hint']
            }),
        throwsFormatException);
  });

  test(
      'old three-format checkpoints and new short answers retain separate stats',
      () {
    final old = ExamSession(
        id: 'old',
        questions: questions.take(3).toList(),
        unitTitles: const {'u': '単元'},
        startedAt: DateTime(2026));
    final loaded = ExamSession.fromJson({...old.toJson(), 'schemaVersion': 1});
    expect(loaded.questions[1].type, ExamQuestionType.fill);
    expect(loaded.questions[1].typeLabel, '穴埋め');
    final exam = ExamSession(
        id: 'new',
        questions: questions,
        unitTitles: const {'u': '単元'},
        startedAt: DateTime(2026),
        responses: const {
          'choice': '0',
          'fill': 'タンパク質',
          'tf': '○',
          'short': 'ＨＩＶ'
        },
        submittedAt: DateTime(2026, 1, 2));
    final restored = ExamSession.fromJson(exam.toJson());
    expect(exam.toJson()['schemaVersion'], 2);
    expect(restored.toScoreRecord().examProfileVersion, 'health-term-exam-v2');
    expect(restored.score, 4);
    expect(restored.toScoreRecord().tags!['形式:穴埋め']!.correct, 1);
    expect(restored.toScoreRecord().tags!['形式:短答記述']!.correct, 1);
  });

  testWidgets(
      'four formats resume short text, grade separately and retry only the error',
      (tester) async {
    Widget runner({ExamSession? session}) => MaterialApp(
        home: ExamRunnerScreen(
            questions: session?.questions ?? questions,
            unitTitles: const {'u': '単元'},
            session: session));
    await tester.pumpWidget(runner());
    await tester.pumpAndSettle();
    await tester.tap(find.text('A'));
    await tester.tap(find.text('次の問題へ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'タンパク質');
    await tester.tap(find.text('次の問題へ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('○'));
    await tester.tap(find.text('次の問題へ'));
    await tester.pumpAndSettle();
    expect(find.text('単元 · 短答記述'), findsOneWidget);
    expect(find.text('用語・短い語句で回答'), findsOneWidget);
    await tester.enterText(find.byType(TextField), ' ＨｉＶ ');
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final saved = (await ExamSessionStore().loadActive())!;
    expect(saved.index, 3);
    expect(saved.responses['short'], ' ＨｉＶ ');
    await tester.pumpWidget(runner(session: saved));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        ' ＨｉＶ ');
    await tester.enterText(find.byType(TextField), 'AIDS');
    await tester.tap(find.text('採点する'));
    await tester.pumpAndSettle();
    expect(find.textContaining('正解: 3 / 4問'), findsOneWidget);
    expect(find.text('得点: 75点 / 100点'), findsOneWidget);
    final result = (await ScoreStore.instance.loadAll()).single;
    expect(result.tags!['形式:短答記述']!.wrong, 1);
    expect(result.tags!['形式:穴埋め']!.correct, 1);
    final retry = find.text('間違い・未回答の1問をもう一度');
    await tester.scrollUntilVisible(retry, 300);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('テスト 1/1'), findsOneWidget);
    expect(find.text('単元 · 短答記述'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'hiv');
    await tester.tap(find.text('採点する'));
    await tester.pumpAndSettle();
    expect(find.textContaining('正解: 1 / 1問'), findsOneWidget);
    expect(await ScoreStore.instance.loadAll(), hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
