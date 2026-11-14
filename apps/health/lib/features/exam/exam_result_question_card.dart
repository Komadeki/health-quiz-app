import 'package:flutter/material.dart';
import 'exam_question.dart';

class ResultQuestionCard extends StatelessWidget {
  const ResultQuestionCard({
    super.key,
    required this.index,
    required this.question,
    required this.response,
  });
  final int index;
  final ExamQuestion question;
  final String? response;

  String get _responseLabel {
    if (response == null || response!.isEmpty) return '未回答';
    if (question.type == ExamQuestionType.choice) {
      final value = int.tryParse(response!);
      if (value == null || value < 0 || value >= question.choices.length) {
        return '不明な回答';
      }
      return question.choices[value];
    }
    return response!;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${question.isCorrect(response) ? '正解' : '不正解'}  問題 $index',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(question.question),
            const SizedBox(height: 8),
            Text('あなたの回答: $_responseLabel'),
            Text('正解: ${question.answerLabel}'),
            Text(question.explanation),
          ],
        ),
      ),
    );
  }
}
