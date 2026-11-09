import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/features/exam/exam_question.dart';
import 'package:health_quiz_app/features/exam/exam_runner_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('holds correctness until end and grades both formats', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const questions = [
      ExamQuestion(
        id: 'tf1', unitId: 'u1', question: '朝の光は体内時計を整える。',
        type: ExamQuestionType.trueFalse, answer: '○',
        explanation: '朝の光が役立つ。',
      ),
      ExamQuestion(
        id: 'fill1', unitId: 'u1', question: 'アルコールを主に代謝する臓器は？',
        type: ExamQuestionType.fill, answer: '肝臓',
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
}
