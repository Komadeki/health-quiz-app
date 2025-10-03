// lib/screens/score_detail_screen.dart
import 'package:flutter/material.dart';
import '../models/score_record.dart';

// mm:ss 表記
String formatSec(int s) {
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}

class ScoreDetailScreen extends StatelessWidget {
  final ScoreRecord record;
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
                child: ListView.separated(
                  itemCount: tags.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final key = tags.keys.elementAt(i);
                    final stat = tags[key]!;
                    final total = stat.correct + stat.wrong;
                    final acc = total == 0 ? 0 : stat.correct / total;
                    return ListTile(
                      title: Text(key),
                      subtitle: Text(
                        '${stat.correct}/$total（${(acc * 100).toStringAsFixed(0)}%）',
                      ),
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
