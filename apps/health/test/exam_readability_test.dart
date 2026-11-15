// Retain Flutter 3.47 compatibility while Flutter 3.50 deprecates this import.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/utils/app_text_scaler.dart';
import 'package:health_quiz_app/features/exam/exam_runner_screen.dart';
import 'package:health_quiz_app/features/exam/exam_question.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SystemCurve extends TextScaler {
  const _SystemCurve();
  @override
  double scale(double size) => size < 20 ? size * 2 : size * 1.5;
  @override
  double get textScaleFactor => 2;
}

void main() {
  test('system enlargement remains when app preference is normal', () {
    const normal = AppTextScaler(TextScaler.linear(2), 1);
    expect(normal.scale(18), 36);
    const large = AppTextScaler(TextScaler.linear(2), 1.15);
    expect(large.scale(18), closeTo(41.4, .001));
    const small = AppTextScaler(TextScaler.linear(2), .9);
    expect(small.scale(18), closeTo(32.4, .001));
  });
  test('per-size system scaling is not flattened to a fixed multiplier', () {
    const scaler = AppTextScaler(_SystemCurve(), 1.15);
    expect(scaler.scale(14), closeTo(32.2, .001));
    expect(scaler.scale(22), closeTo(37.95, .001));
  });
  testWidgets(
      'large Japanese choices and input remain usable on narrow dark screen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const long = '健康情報の根拠と条件を確かめて、分からないことは専門家に相談する';
    const questions = [
      ExamQuestion(
          id: 'choice',
          unitId: 'u',
          type: ExamQuestionType.choice,
          question: '健康に関する情報を利用する際の、適切な行動を選んでください。',
          choices: [long, '情報を確認しない'],
          answer: '0',
          explanation: '説明'),
      ExamQuestion(
          id: 'fill',
          unitId: 'u',
          type: ExamQuestionType.fill,
          question: '生活の質を表す用語は（　）である。',
          answer: 'QOL',
          explanation: '説明'),
    ];
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                textScaler: const AppTextScaler(TextScaler.linear(2), 1.15)),
            child: child!),
        home: const ExamRunnerScreen(
            questions: questions, unitTitles: {'u': '単元'})));
    await tester.pumpAndSettle();
    final choice = find.text(long);
    await tester.scrollUntilVisible(choice, 200);
    await tester.ensureVisible(choice);
    final tile = tester.getRect(find.widgetWithText(ListTile, long));
    final viewport = tester.getRect(find.byType(ListView));
    await tester.tapAt(tile.intersect(viewport).center);
    await tester.pumpAndSettle();
    expect(
        tester.widget<ListTile>(find.widgetWithText(ListTile, long)).selected,
        isTrue);
    expect(find.textContaining('正解:'), findsNothing);
    await tester.tap(find.text('次の問題へ'));
    await tester.pumpAndSettle();
    expect(find.text('前の問題'), findsOneWidget);
    expect(find.text('採点する'), findsOneWidget);
    final input = find.byType(TextField);
    await tester.ensureVisible(input);
    await tester.enterText(input, 'ＱＯＬ');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).maxLines, 3);
    expect(tester.takeException(), isNull);
  });
}
