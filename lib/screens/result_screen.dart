import 'package:flutter/material.dart';
import 'attempt_history_screen.dart'; // 履歴画面への遷移用

class ResultScreen extends StatelessWidget {
  final int total;
  final int correct;
  final String? sessionId;                 // 今回のセッションID
  final Map<String, int>? unitBreakdown;   // ★追加：ユニット別内訳（null許容）

  const ResultScreen({
    super.key,
    required this.total,
    required this.correct,
    this.sessionId,
    this.unitBreakdown, // ★追加
  });

  @override
  Widget build(BuildContext context) {
    final rate = total == 0 ? '0.0' : (correct / total * 100).toStringAsFixed(1);
    final ub = unitBreakdown ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('結果')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 成績サマリ
              Text(
                'スコア: $correct / $total',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '正答率: $rate %',
                style: const TextStyle(fontSize: 18),
              ),

              // ★ 出題内訳（unitBreakdown がある場合のみ表示）
              if (ub.isNotEmpty) ...[
                const SizedBox(height: 24),
                _UnitBreakdownCard(
                  unitBreakdown: ub,
                  totalQuestions: total,
                ),
              ],

              const SizedBox(height: 24),

              // 「今回の履歴を見る」ボタン（sessionId があるときのみ）
              if (sessionId != null) ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.history),
                  label: const Text('今回の履歴を見る'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            AttemptHistoryScreen(sessionId: sessionId!),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
              ],

              // ホームへ戻る（既存）
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/', (route) => false);
                },
                icon: const Icon(Icons.home),
                label: const Text('ホームへ'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ★ 出題内訳カード（ユニットID: 件数［割合%］）
class _UnitBreakdownCard extends StatelessWidget {
  final Map<String, int> unitBreakdown;
  final int totalQuestions;

  const _UnitBreakdownCard({
    required this.unitBreakdown,
    required this.totalQuestions,
  });

  @override
  Widget build(BuildContext context) {
    final entries = unitBreakdown.entries.toList()
      ..sort((a, b) {
        // 件数降順 → 件数同率ならキー昇順で安定化
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '出題内訳',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...entries.map((e) {
              final count = e.value;
              final pct = totalQuestions == 0
                  ? '0'
                  : ((count / totalQuestions) * 100).toStringAsFixed(0);
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(e.key),                 // ここは unitId。表示名にしたい場合は差し替え可
                trailing: Text('$count問（$pct%）'),
              );
            }),
          ],
        ),
      ),
    );
  }
}
