// Retain Flutter 3.47 compatibility while Flutter 3.50 deprecates this import.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'exam_question.dart';

class ResultQuestionCard extends StatelessWidget {
  const ResultQuestionCard(
      {super.key,
      required this.index,
      required this.question,
      required this.response});
  final int index;
  final ExamQuestion question;
  final String? response;

  String get _responseLabel {
    if (response == null || response!.trim().isEmpty) return '未回答';
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
    final theme = Theme.of(context);
    final correct = question.isCorrect(response);
    final missing = response?.trim().isNotEmpty != true;
    final status = missing
        ? '未回答'
        : correct
            ? '正解'
            : '不正解';
    final color = correct
        ? theme.colorScheme.primary
        : missing
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.error;
    return Card.outlined(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(
                spacing: 12,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        missing
                            ? Icons.remove_circle_outline
                            : correct
                                ? Icons.check_circle_outline
                                : Icons.cancel_outlined,
                        color: color,
                        size: 20),
                    const SizedBox(width: 6),
                    Text(status,
                        style:
                            theme.textTheme.titleSmall?.copyWith(color: color)),
                  ]),
                  Text('問題 $index · ${question.typeLabel}',
                      style: theme.textTheme.labelLarge),
                ]),
            const SizedBox(height: 12),
            Text(question.question, style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            LayoutBuilder(builder: (context, constraints) {
              final answers = [
                _Answer(
                    label: 'あなたの回答',
                    text: _responseLabel,
                    background: theme.colorScheme.surfaceContainerHighest),
                _Answer(
                    label: '正解',
                    text: question.answerLabel,
                    background: theme.colorScheme.primaryContainer),
              ];
              if (constraints.maxWidth >= 520) {
                return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: answers[0]),
                      const SizedBox(width: 12),
                      Expanded(child: answers[1])
                    ]);
              }
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    answers[0],
                    const SizedBox(height: 8),
                    answers[1]
                  ]);
            }),
            const SizedBox(height: 16),
            Text('解説', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(question.explanation),
          ])),
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer(
      {required this.label, required this.text, required this.background});
  final String label;
  final String text;
  final Color background;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(12)),
        child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(text, style: Theme.of(context).textTheme.titleMedium),
            ])),
      );
}
