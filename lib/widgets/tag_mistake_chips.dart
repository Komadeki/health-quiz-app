// lib/widgets/tag_mistake_chips.dart
import 'package:flutter/material.dart';
import '../models/tag_stat.dart' as ts;

class TagMistakeChips extends StatelessWidget {
  final Map<String, ts.TagStat> tagStats;
  final int maxTags;            // 表示上限
  final int minTotalThreshold;  // 信頼できる最低回答数
  final void Function(String tag)? onTapTag;

  const TagMistakeChips({
    super.key,
    required this.tagStats,
    this.maxTags = 5,
    this.minTotalThreshold = 3,
    this.onTapTag,
  });

  @override
  Widget build(BuildContext context) {
    final entries = tagStats.entries
        .where((e) => e.value.total >= minTotalThreshold)
        .toList()
      ..sort((a, b) {
        final c = b.value.wrongRate.compareTo(a.value.wrongRate);
        if (c != 0) return c;
        return b.value.total.compareTo(a.value.total);
      });

    final display = entries.take(maxTags).toList();

    if (display.isEmpty) {
      return Text(
        '記録が増えると「よく間違えるテーマ」を表示します',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).hintColor,
            ),
      );
    }

    String pct(num v) => '${(v * 100).toStringAsFixed(0)}%';

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final e in display)
          InkWell(
            onTap: onTapTag == null ? null : () => onTapTag!(e.key),
            borderRadius: BorderRadius.circular(20),
            child: Chip(
              label: Text(
                '${e.key}｜${pct(e.value.wrongRate)}（${e.value.correct}/${e.value.total}）',
                overflow: TextOverflow.ellipsis,
              ),
              backgroundColor: Colors.red.shade50,
              side: BorderSide(color: Colors.red.shade100),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      ],
    );
  }
}
