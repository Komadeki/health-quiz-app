// lib/screens/review_test_setup_screen.dart
import 'package:flutter/material.dart';
import '../models/deck.dart';
import '../services/attempt_store.dart';
import '../services/deck_loader.dart';
import '../services/review_test_builder.dart';
import 'quiz_screen.dart';

class ReviewTestSetupScreen extends StatefulWidget {
  const ReviewTestSetupScreen({super.key});

  @override
  State<ReviewTestSetupScreen> createState() => _ReviewTestSetupScreenState();
}

class _ReviewTestSetupScreenState extends State<ReviewTestSetupScreen> {
  final _sizes = const [10, 20, 30, 50];
  int _selected = 10;
  bool _busy = false;
  int _available = -1; // 誤答データ件数（ロード後表示）

  @override
  void initState() {
    super.initState();
    _probeAvailable();
  }

  Future<void> _probeAvailable() async {
    final store = AttemptStore();
    final m = await store.getWrongFrequencyMap();
    if (!mounted) return;
    setState(() => _available = m.length);
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final attempts = AttemptStore();
      final loader = DeckLoader();
      final builder = ReviewTestBuilder(attempts: attempts, loader: loader);

      // ハング保険：10秒でタイムアウト
      final cards = await builder.buildTopN(topN: _selected)
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (cards.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('復習対象がありません')),
        );
        Navigator.of(context).pop();
        return;
      }

      final fakeDeck = Deck(
        id: 'review',
        title: '復習テスト',
        isPurchased: true,
        units: const [],
      );

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuizScreen(
            deck: fakeDeck,
            overrideCards: cards,
            type: 'review_test',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('復習テストの準備に失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = _busy || (_available == 0);

    return Scaffold(
      appBar: AppBar(title: const Text('復習テストの設定')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('出題数を選択', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: _sizes.map((n) {
                final selected = n == _selected;
                return ChoiceChip(
                  label: Text('$n問'),
                  selected: selected,
                  onSelected: (_) => setState(() => _selected = n),
                );
              }).toList(),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: disabled ? null : _start,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('開始'),
              ),
            ),
            const SizedBox(height: 16),
            if (_available >= 0)
              Text(
                '誤答データ：$_available 件',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
            const SizedBox(height: 12),
            const Text(
              'これまでの誤答が多かった問題から優先的に出題します。',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
