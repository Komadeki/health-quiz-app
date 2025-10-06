import 'package:flutter/material.dart';

class ResultScreen extends StatelessWidget {
  final int total;
  final int correct;
  const ResultScreen({super.key, required this.total, required this.correct});

  @override
  Widget build(BuildContext context) {
    final rate = (correct / total * 100).toStringAsFixed(1);
    return Scaffold(
      appBar: AppBar(title: const Text('結果')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'スコア: $correct / $total',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('正答率: $rate %'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              },
              icon: const Icon(Icons.home),
              label: const Text('ホームへ'),
            ),
          ],
        ),
      ),
    );
  }
}
