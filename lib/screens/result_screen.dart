import 'package:flutter/material.dart';
import 'attempt_history_screen.dart'; // ★追加：履歴画面への遷移用

class ResultScreen extends StatelessWidget {
  final int total;
  final int correct;
  final String? sessionId; // ★追加：今回のセッションIDを受け取る

  const ResultScreen({
    super.key,
    required this.total,
    required this.correct,
    this.sessionId,
  });

  @override
  Widget build(BuildContext context) {
    final rate = (correct / total * 100).toStringAsFixed(1);
    return Scaffold(
      appBar: AppBar(title: const Text('結果')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
              const SizedBox(height: 32),

              // ★「今回の履歴を見る」ボタンを追加
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

              // ホームへ戻るボタン（既存の仕様を保持）
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
