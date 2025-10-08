// lib/widgets/quiz_analytics.dart
import 'package:flutter/material.dart';


/// 出題・誤答の簡易モデル（既に同名クラスがある場合は、こちらを削除して既存を import してください）
class UnitStat {
  final int asked;
  final int wrong;
  const UnitStat({required this.asked, required this.wrong});
}

// ──────────────── 共通ユーティリティ ────────────────
class TopUnits {
  final List<_Seg> top;
  final _Seg? others;
  TopUnits({required this.top, this.others});
}

class _Seg {
  final String unitId;
  final String displayTitle;
  final int asked;
  final double ratio; // 0..1
  _Seg({required this.unitId, required this.displayTitle, required this.asked, required this.ratio});
}

TopUnits computeTopUnits({
  required Map<String, UnitStat> unitBreakdown,
  required Map<String, String>? unitTitleMap,
  int topN = 4,
}) {
  final totalAsked = unitBreakdown.values.fold<int>(0, (a, b) => a + b.asked);
  final safeTotal = totalAsked == 0 ? 1 : totalAsked;

  final segs = unitBreakdown.entries
      .where((e) => e.value.asked > 0)
      .map((e) => _Seg(
            unitId: e.key,
            displayTitle: (unitTitleMap?[e.key]?.trim().isNotEmpty ?? false)
                ? unitTitleMap![e.key]!
                : e.key,
            asked: e.value.asked,
            ratio: e.value.asked / safeTotal,
          ))
      .toList()
    ..sort((a, b) => b.ratio.compareTo(a.ratio));

  if (segs.length <= topN) return TopUnits(top: segs);
  final top = segs.take(topN).toList();
  final othersAsked = segs.skip(topN).fold<int>(0, (a, s) => a + s.asked);
  final others = _Seg(
    unitId: '_others',
    displayTitle: 'その他',
    asked: othersAsked,
    ratio: othersAsked / safeTotal,
  );
  return TopUnits(top: top, others: others);
}

String pct(double v) => '${(v * 100).toStringAsFixed(v >= 0.995 ? 0 : 1)}%';

const _palette = <Color>[
  Color(0xFF4F46E5), // indigo-600
  Color(0xFF06B6D4), // cyan-500
  Color(0xFFF59E0B), // amber-500
  Color(0xFF10B981), // emerald-500
  Color(0xFFE11D48), // rose-600
  Color(0xFF8B5CF6), // violet-500
];
Color segmentColor(int index) => _palette[index % _palette.length];

// ──────────────── 1) サマリバー（Result 用） ────────────────
class SummaryStackedBar extends StatelessWidget {
  final TopUnits data;
  final double height;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;

  const SummaryStackedBar({
    super.key,
    required this.data,
    this.height = 16,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  Widget build(BuildContext context) {
    final segs = [...data.top, if (data.others != null) data.others!];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: padding,
          child: ClipRRect(
            borderRadius: borderRadius,
            child: Row(
              children: [
                for (var i = 0; i < segs.length; i++)
                  Expanded(
                    flex: (segs[i].ratio * 10000).round().clamp(1, 10000),
                    child: Container(
                      height: height,
                      color: segs[i].unitId == '_others'
                          ? Colors.grey.shade300
                          : segmentColor(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          children: [
            for (var i = 0; i < segs.length; i++)
              _LegendItem(
                color: segs[i].unitId == '_others'
                    ? Colors.grey.shade400
                    : segmentColor(i),
                label: '${segs[i].displayTitle} ${pct(segs[i].ratio)}',
              ),
          ],
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendItem({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(right: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ──────────────── 3) 主要ユニットチップ（Scores 用） ────────────────
class UnitRatioChips extends StatelessWidget {
  final Map<String, UnitStat> unitBreakdown;
  final Map<String, String>? unitTitleMap;
  final int topK;
  final EdgeInsetsGeometry padding;
  const UnitRatioChips({
    super.key,
    required this.unitBreakdown,
    this.unitTitleMap,
    this.topK = 2,
    this.padding = const EdgeInsets.only(top: 6),
  });

  @override
  Widget build(BuildContext context) {
    final top = computeTopUnits(
      unitBreakdown: unitBreakdown,
      unitTitleMap: unitTitleMap,
      topN: topK,
    );
    final segs = top.top.take(topK).toList();
    if (segs.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: padding,
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < segs.length; i++)
            Chip(
              label: Text('${segs[i].displayTitle} ${pct(segs[i].ratio)}'),
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: segmentColor(i).withOpacity(0.3)),
              backgroundColor: segmentColor(i).withOpacity(0.08),
              labelStyle: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

// ──────────────── 2) 誤答率タグ（AttemptHistory 用） ────────────────
class ErrorRateTag extends StatelessWidget {
  final int asked;
  final int wrong;
  final EdgeInsetsGeometry padding;
  final bool compact;

  const ErrorRateTag({
    super.key,
    required this.asked,
    required this.wrong,
    this.padding = EdgeInsets.zero,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final rate = asked > 0 ? wrong / asked : 0.0;
    final text = '誤答率 ${pct(rate)}  ($wrong/$asked)';
    if (compact) {
      return Padding(
        padding: padding,
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: Colors.grey[700],
              ),
        ),
      );
    }
    return Padding(
      padding: padding,
      child: Chip(
        label: Text(text),
        visualDensity: VisualDensity.compact,
        backgroundColor: Colors.red.withOpacity(0.06),
        side: BorderSide(color: Colors.red.withOpacity(0.2)),
        labelStyle: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
