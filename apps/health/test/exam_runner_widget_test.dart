// Retain Flutter 3.47 compatibility while Flutter 3.50 deprecates this import.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/features/exam/exam_question.dart';
import 'package:health_quiz_app/features/exam/exam_runner_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_quiz_app/features/exam/exam_session_store.dart';
import 'package:health_quiz_app/features/exam/exam_result_screen.dart';
import 'package:health_quiz_app/features/exam/exam_session.dart';
import 'package:health_quiz_app/features/exam/exam_setup_screen.dart';
import 'package:health_quiz_app/services/deck_loader.dart';
import 'package:health_quiz_app/services/score_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('holds correctness until end and grades both formats',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const questions = [
      ExamQuestion(
        id: 'tf1',
        unitId: 'u1',
        question: '朝の光は体内時計を整える。',
        type: ExamQuestionType.trueFalse,
        answer: '○',
        explanation: '朝の光が役立つ。',
      ),
      ExamQuestion(
        id: 'fill1',
        unitId: 'u1',
        question: 'アルコールを主に代謝する臓器は？',
        type: ExamQuestionType.fill,
        answer: '肝臓',
        explanation: 'アルコールの多くは肝臓で代謝される。',
      ),
    ];
    await tester.pumpWidget(const MaterialApp(
      home: ExamRunnerScreen(
        questions: questions,
        unitTitles: {'u1': '保健'},
      ),
    ));
    expect(find.textContaining('正解:'), findsNothing);

    await tester.tap(find.text('○'));
    await tester.tap(find.text('次の問題へ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('正解:'), findsNothing);

    await tester.enterText(find.byType(TextField), '肝臓');
    await tester.tap(find.text('採点する'));
    await tester.pumpAndSettle();
    expect(find.textContaining('正解: 2 / 2問'), findsOneWidget);
    expect(find.text('間違えた問題をもう一度'), findsNothing);
  });
  testWidgets('reopens all three formats and preserves answer edits',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const questions = [
      ExamQuestion(
          id: 'c',
          unitId: 'u1',
          question: '選択問題',
          type: ExamQuestionType.choice,
          choices: ['A', 'B', 'C', 'D'],
          answer: '1',
          explanation: '選択の解説'),
      ExamQuestion(
          id: 'f',
          unitId: 'u2',
          question: '空欄問題',
          type: ExamQuestionType.fill,
          answer: 'たんぱく質',
          acceptedAnswers: ['タンパク質'],
          explanation: '穴埋めの解説'),
      ExamQuestion(
          id: 't',
          unitId: 'u2',
          question: '正誤問題',
          type: ExamQuestionType.trueFalse,
          answer: '○',
          explanation: '正誤の解説'),
    ];
    await tester.pumpWidget(const MaterialApp(
        home: ExamRunnerScreen(
            questions: questions, unitTitles: {'u1': '単元1', 'u2': '単元2'})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B'));
    await tester.tap(find.text('次の問題へ'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'タンパク質');
    await tester.pumpAndSettle();
    final saved = (await ExamSessionStore().loadActive())!;
    expect(saved.responses['c'], '1');
    expect(saved.responses['f'], 'タンパク質');
    expect(saved.index, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(MaterialApp(
        home: ExamRunnerScreen(
            questions: saved.questions,
            unitTitles: saved.unitTitles,
            session: saved)));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'タンパク質');
    await tester.tap(find.text('前の問題'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    await tester.tap(find.text('次の問題へ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('次の問題へ'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('○'));
    expect(find.text('正誤の解説'), findsNothing);
    await tester.tap(find.text('採点する'));
    await tester.tap(find.text('採点する'));
    await tester.pumpAndSettle();
    expect(find.textContaining('正解: 3 / 3問'), findsOneWidget);
    expect(find.text('単元別'), findsOneWidget);
    expect(find.text('形式別'), findsOneWidget);
    expect(await ScoreStore.instance.loadAll(), hasLength(1));
    expect(await ExamSessionStore().loadActive(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester
        .pumpWidget(MaterialApp(home: ExamHistoryScreen(sessionId: saved.id)));
    await tester.pumpAndSettle();
    expect(find.textContaining('正解: 3 / 3問'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unanswered questions require confirmation and support retry',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const q = ExamQuestion(
        id: 'blank',
        unitId: 'u',
        question: '回答は空欄',
        type: ExamQuestionType.fill,
        answer: '肝臓',
        explanation: '解説');
    await tester.pumpWidget(const MaterialApp(
        home: ExamRunnerScreen(questions: [q], unitTitles: {'u': '保健'})));
    await tester.pumpAndSettle();
    await tester.tap(find.text('採点する'));
    await tester.pumpAndSettle();
    expect(find.text('未回答が1問あります。不正解として採点しますか？'), findsOneWidget);
    await tester.tap(find.text('戻る'));
    await tester.pumpAndSettle();
    expect(await ScoreStore.instance.loadAll(), isEmpty);
    await tester.tap(find.text('採点する'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '採点する').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('正解: 0 / 1問'), findsOneWidget);
    final retry = find.text('間違い・未回答の1問をもう一度');
    await tester.scrollUntilVisible(retry, 300);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '肝臓');
    await tester.tap(find.text('採点する'));
    await tester.pumpAndSettle();
    expect(find.textContaining('正解: 1 / 1問'), findsOneWidget);
    expect(await ScoreStore.instance.loadAll(), hasLength(2));
    expect(tester.takeException(), isNull);
  });

  for (final count in [10, 20, 30]) {
    testWidgets('$count questions finish without duplicate scores',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final questions = List.generate(
          count,
          (i) => ExamQuestion(
              id: 'tf-$i',
              unitId: 'u',
              question: '設問$i',
              type: ExamQuestionType.trueFalse,
              answer: '○',
              explanation: '解説$i'));
      await tester.pumpWidget(MaterialApp(
          home: ExamRunnerScreen(
              questions: questions, unitTitles: const {'u': '保健'})));
      await tester.pumpAndSettle();
      for (var i = 0; i < count; i++) {
        await tester.tap(find.text('○'));
        await tester.tap(find.text(i == count - 1 ? '採点する' : '次の問題へ'));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('正解: $count / $count問'), findsOneWidget);
      expect(await ScoreStore.instance.loadAll(), hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('small screen with large text and dark theme remains scrollable',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const q = ExamQuestion(
        id: 'accessibility',
        unitId: 'u',
        question: '長い問題文が画面に収まり、文字を大きくしても回答できることを確認する。',
        type: ExamQuestionType.fill,
        answer: '回答',
        explanation: '説明');
    Widget wrap(Widget child) => MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!),
        home: child);
    await tester.pumpWidget(
        wrap(const ExamRunnerScreen(questions: [q], unitTitles: {'u': '保健'})));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final session = ExamSession(
        id: 'a11y',
        questions: const [q],
        unitTitles: const {'u': '保健'},
        startedAt: DateTime(2026),
        submittedAt: DateTime(2026, 2),
        responses: const {'accessibility': '回答'});
    await tester.pumpWidget(wrap(ExamResultScreen(session: session)));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('戻る'), 200);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unreadable active exam offers a preserving recovery action',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ExamSessionStore.activeKey: 'broken',
      ExamSessionStore.sessionKey('broken'): '{bad',
    });
    final loader = await tester.runAsync(DeckLoader.instance);
    final decks = await loader!.loadAll();
    await tester.pumpWidget(MaterialApp(home: ExamSetupScreen(decks: decks)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('途中経過を退避して新しく始める'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('退避して続ける'));
    await tester.pumpAndSettle();
    expect(find.text('試験範囲を選択'), findsOneWidget);
    expect(find.text('途中経過を退避して新しく始める'), findsNothing);
    expect(
        (await SharedPreferences.getInstance())
            .getString(ExamSessionStore.sessionKey('broken')),
        '{bad');
    expect(tester.takeException(), isNull);
  });
}
