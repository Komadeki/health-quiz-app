// lib/screens/score_detail_screen.dart
import 'package:flutter/material.dart';
import '../models/score_record.dart';

// mm:ss 表記
String formatSec(int s) {
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}

// 正答率に応じた色
Color accuracyColor(BuildContext context, double acc) {
  // acc は 0.0〜1.0
  final cs = Theme.of(context).colorScheme;
  if (acc >= 0.80) return Colors.green; // 良い
  if (acc >= 0.50) return Colors.orange; // まあまあ
  return cs.error; // 要改善（赤）
}

// 正答率に応じたアイコン
IconData accuracyIcon(double acc) {
  if (acc >= 0.80) return Icons.check_circle;
  if (acc >= 0.50) return Icons.error_outline;
  return Icons.cancel;
}

class ScoreDetailScreen extends StatelessWidget {
  final sr.ScoreRecord record;
  const ScoreDetailScreen({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final tags = record.tags;
    return Scaffold(
      appBar: AppBar(title: const Text('成績の詳細')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.deckTitle.isEmpty ? record.deckId : record.deckTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'スコア: ${record.score}/${record.total}（${(record.accuracy * 100).toStringAsFixed(0)}%）',
            ),
            if (record.durationSec != null)
              Text('所要時間: ${formatSec(record.durationSec!)}'),
            const SizedBox(height: 16),
            const Text('タグ別'),
            const SizedBox(height: 8),

            if (tags == null || tags.isEmpty)
              const Text('タグ集計なし')
            else
              Expanded(
                child: Builder(
                  builder: (context) {
                    // ① tags を配列に展開して精度を計算
                    final items = tags.entries.map((e) {
                      final name = e.key;
                      final stat = e.value;
                      final total = stat.correct + stat.wrong;
                      final acc = total == 0 ? 0.0 : stat.correct / total;
                      return (name: name, stat: stat, total: total, acc: acc);
                    }).toList();

                    // ② 弱い順（精度の低い順）にソート
                    items.sort((a, b) => a.acc.compareTo(b.acc));

                    // ③ 表示
                    return ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final it = items[i];
                        final pct = (it.acc * 100).round();
                        final color = accuracyColor(context, it.acc);
                        final icon = accuracyIcon(it.acc);

                        return ListTile(
                          title: Text(
                            it.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text('${it.stat.correct}/${it.total}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '（$pct%）',
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(icon, color: color),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
