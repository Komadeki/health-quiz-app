// Retain Flutter 3.47 compatibility while Flutter 3.50 deprecates this import.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/features/exam/exam_question.dart';
import 'package:health_quiz_app/features/exam/exam_result_question_card.dart';
import 'package:health_quiz_app/features/exam/exam_result_screen.dart';
import 'package:health_quiz_app/features/exam/exam_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

const questions = [
  ExamQuestion(
      id: 'choice',
      unitId: 'u',
      question: '正しい選択肢を選ぶ',
      type: ExamQuestionType.choice,
      choices: ['誤った選択肢', '正しい選択肢'],
      answer: '1',
      explanation: '意味を確認する説明。'),
  ExamQuestion(
      id: 'short',
      unitId: 'u',
      question: '英字で答える',
      type: ExamQuestionType.shortAnswer,
      answer: 'HIV',
      explanation: 'HIVの説明。'),
  ExamQuestion(
      id: 'fill',
      unitId: 'u',
      question: '生活の質は（　）。',
      type: ExamQuestionType.fill,
      answer: 'QOL',
      explanation: 'QOLの説明。'),
];

ExamSession session({bool allCorrect = false}) => ExamSession(
    id: 'result',
    questions: questions,
    unitTitles: {'u': '単元'},
    responses: allCorrect
        ? {'choice': '1', 'short': 'hiv', 'fill': 'QOL'}
        : {'choice': '0', 'short': 'ｈｉｖ'},
    startedAt: DateTime(2026),
    submittedAt: DateTime(2026, 1, 1, 0, 1));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      'counts distinguish wrong and unanswered; filtering preserves score and question numbers',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: ExamResultScreen(session: session())));
    expect(find.text('正解 1問'), findsOneWidget);
    expect(find.text('不正解 1問'), findsOneWidget);
    expect(find.text('未回答 1問'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('得点: 33点 / 100点')), findsOneWidget);
    final toggle = find.byType(SwitchListTile);
    await tester.scrollUntilVisible(toggle, 250);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    final cards = tester
        .widgetList<ResultQuestionCard>(find.byType(ResultQuestionCard))
        .toList();
    expect(cards.map((c) => c.index), [1, 3]);
    expect(cards.map((c) => c.question.id), ['choice', 'fill']);
    await tester.scrollUntilVisible(find.text('今回の得点'), -350);
    expect(find.bySemanticsLabel(RegExp('得点: 33点 / 100点')), findsOneWidget);
    expect(session().responses, {'choice': '0', 'short': 'ｈｉｖ'});
    expect(tester.takeException(), isNull);
  });

  testWidgets('all-correct filter explains empty result without retry',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: ExamResultScreen(session: session(allCorrect: true))));
    expect(find.bySemanticsLabel(RegExp('得点: 100点 / 100点')), findsOneWidget);
    expect(find.textContaining('問をもう一度'), findsNothing);
    final toggle = find.byType(SwitchListTile);
    await tester.scrollUntilVisible(toggle, 250);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(find.text('全問正解です。見直す問題はありません。'), findsOneWidget);
    expect(find.byType(ResultQuestionCard), findsNothing);
  });

  testWidgets('result summary fits a narrow dark screen with large text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: ExamResultScreen(session: session())));
    expect(find.text('正解 1問'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.byType(SwitchListTile), 250);
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('問題 3 · 穴埋め'), 250);
    expect(find.text('問題 3 · 穴埋め'), findsOneWidget);
    expect(
        tester
            .widgetList<ResultQuestionCard>(find.byType(ResultQuestionCard))
            .any((card) => card.question.id == 'short'),
        isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 900.0]) {
    testWidgets('long answers at large text fit width $width', (tester) async {
      tester.view.physicalSize = Size(width, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const longAnswer = '健康に関する情報の根拠と条件を確認し、自分に合う方法を考えて相談する';
      const q = ExamQuestion(
          id: 'long',
          unitId: 'u',
          type: ExamQuestionType.shortAnswer,
          question: '内容を説明してください。',
          answer: longAnswer,
          explanation: '説明も複数行で表示します。');
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!),
          home: const Scaffold(
              body: SingleChildScrollView(
                  child: ResultQuestionCard(
                      index: 30, question: q, response: longAnswer)))));
      expect(find.text('あなたの回答'), findsOneWidget);
      expect(find.text(longAnswer), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      final answer = tester.getTopLeft(find.text('あなたの回答'));
      final correct = tester.getTopLeft(find.text('正解').last);
      if (width < 520) {
        expect(correct.dy, greaterThan(answer.dy));
      } else {
        expect(correct.dy, answer.dy);
        expect(correct.dx, greaterThan(answer.dx));
      }
    });
  }
}
