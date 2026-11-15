// Retain Flutter 3.47 compatibility while Flutter 3.50 deprecates this import.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';

/// Presentation only: scoring and persisted history remain in ExamSession.
class ExamScoreSummary extends StatelessWidget {
  const ExamScoreSummary(
      {super.key,
      required this.correct,
      required this.total,
      required this.unanswered});
  final int correct;
  final int total;
  final int unanswered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final points = total == 0 ? 0 : (correct * 100 / total).round();
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('今回の得点', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Semantics(
            label: '得点: $points点 / 100点',
            excludeSemantics: true,
            child: Text.rich(TextSpan(children: [
              TextSpan(
                  text: '$points',
                  style: theme.textTheme.displayLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold)),
              TextSpan(text: ' 点 / 100点', style: theme.textTheme.titleMedium),
            ])),
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
              value: total == 0 ? 0 : correct / total,
              semanticsLabel: '正答率',
              semanticsValue: '$points%'),
          const SizedBox(height: 12),
          Text('正解: $correct / $total問  ($points%)',
              style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 12, runSpacing: 8, children: [
            _Count(icon: Icons.check_circle_outline, label: '正解 $correct問'),
            _Count(
                icon: Icons.cancel_outlined,
                label: '不正解 ${total - correct - unanswered}問'),
            _Count(
                icon: Icons.remove_circle_outline, label: '未回答 $unanswered問'),
          ]),
          const SizedBox(height: 12),
          Text('1問ずつ採点し、100点満点に換算（四捨五入）。未回答は不正解として採点。',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          const Row(children: [
            Icon(Icons.bookmark_added_outlined, size: 18),
            SizedBox(width: 6),
            Flexible(child: Text('成績を保存しました'))
          ]),
        ]),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [Icon(icon, size: 18), const SizedBox(width: 4), Text(label)]);
}
