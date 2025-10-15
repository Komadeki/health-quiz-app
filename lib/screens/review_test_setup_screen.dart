// lib/screens/review_test_setup_screen.dart
import 'package:flutter/material.dart';
import '../models/deck.dart';
import '../services/attempt_store.dart';
import '../services/deck_loader.dart';
import '../services/review_test_builder.dart';
import '../services/session_scope.dart'; // ★追加：成績スコープ収集
import 'quiz_screen.dart';

class ReviewTestSetupScreen extends StatefulWidget {
  const ReviewTestSetupScreen({super.key});

  @override
  State<ReviewTestSetupScreen> createState() => _ReviewTestSetupScreenState();
}

class _ReviewTestSetupScreenState extends State<ReviewTestSetupScreen> {
  // 出題数プリセット
  final _sizes = const [10, 20, 30, 50];
  int _selected = 10;

  // セッションスコープ（将来UIで変更可能）
  int? _days = 30;        // 直近30日（nullなら全期間）
  String? _type;          // 'normal' | 'mixed' | 'review_test' など（nullなら全タイプ）

  bool _busy = false;
  int _available = -1;    // スコープ内のユニーク誤答候補数
  List<String>? _scopedSessionIds; // 収集済みセッションID（キャッシュ）

  @override
  void initState() {
    super.initState();
    _probeAvailable();
  }

  /// スコープ内の候補数を試算して表示（誤答のユニーク数）
  Future<void> _probeAvailable() async {
    // 1) 成績スコープから sessionId を収集
    final sessionIds = await SessionScope.collect(days: _days, type: _type);

    // 2) AttemptStore を sessionIds で絞って候補数を取得
    final store = AttemptStore();
    final freq = await store.getWrongFrequencyMap(
      onlySessionIds: sessionIds,
    );

    if (!mounted) return;
    setState(() {
      _scopedSessionIds = sessionIds;
      _available = freq.length; // ユニーク誤答件数
    });
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      // スコープが未取得なら再収集
      final sessionIds = _scopedSessionIds ??
          await SessionScope.collect(days: _days, type: _type);

      // Builder にスコープを渡す（補充なし）
      final attempts = AttemptStore();
      final loader = DeckLoader();
      final builder = ReviewTestBuilder(
        attempts: attempts,
        loader: loader,
        sessionFilter: sessionIds, // ★重要：ここで絞り込み
      );

      // ハング保険：10秒でタイムアウト
      final cards = await builder
          .buildTopN(topN: _selected)
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (cards.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('指定範囲に復習対象がありません。期間やタイプを見直してください。')),
        );
        Navigator.of(context).pop();
        return;
      }

      // 補充なし仕様：候補がN未満でもそのまま出題
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

    final scopeLabel = () {
      final d = _days;
      final t = _type;
      final daysPart = (d == null) ? '全期間' : '直近${d}日';
      final typePart = (t == null) ? '' : '・タイプ:$t';
      return '$daysPart$typePart';
    }();

    final shortageHint = (_available >= 0 && _selected > _available)
        ? '（候補は$_available件のため$_available件で出題）'
        : '';

    return Scaffold(
      appBar: AppBar(title: const Text('復習テストの設定')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 出題数セレクタ
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
            if (shortageHint.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                shortageHint,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 32),

            // 開始ボタン
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

            // 候補数とスコープ表示
            if (_available >= 0)
              Text(
                '候補（ユニーク誤答）: $_available 件（スコープ: $scopeLabel）',
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),

            const SizedBox(height: 12),
            const Text(
              '選択範囲（成績スコープ）で誤答が多かった問題から優先的に出題します。補充は行いません。',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),

            const Spacer(),

            // 画面再計測（将来、期間やタイプをUIで変更する際に使用）
            Row(
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : _probeAvailable,
                  icon: const Icon(Icons.refresh),
                  label: const Text('候補を再計算'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
