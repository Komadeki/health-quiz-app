// lib/screens/review_test_setup_screen.dart
import 'package:flutter/material.dart';
import '../models/deck.dart';
import '../models/review_scope.dart';
import '../services/attempt_store.dart';
// ★統合版にするなら下は削除：import '../services/attempt_store_review_ext.dart';
import '../services/deck_loader.dart';
import '../services/review_test_builder.dart';
import 'quiz_screen.dart';

class ReviewTestSetupScreen extends StatefulWidget {
  const ReviewTestSetupScreen({super.key});

  @override
  State<ReviewTestSetupScreen> createState() => _ReviewTestSetupScreenState();
}

class _ReviewTestSetupScreenState extends State<ReviewTestSetupScreen> {
  // 出題数プリセット
  final List<int> _sizes = const [10, 20, 30, 50];
  int _selected = 10;

  // 成績スコープ簡易UI（将来拡張用）
  int? _days = 30;          // 直近30日（null=全期間）
  String? _type;            // 'unit' | 'mixed' | 'review_test'（null=全タイプ）

  bool _busy = false;
  bool _probing = false;
  int _available = -1;      // スコープ内ユニーク誤答（stableIdベース）

  @override
  void initState() {
    super.initState();
    // 初回フレーム描画後に集計を開始（jank抑制）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _probeAvailable();
    });
  }

  /// UI状態から ScoreScope を構成
  ScoreScope _buildScope() {
    final now = DateTime.now();
    final from = (_days == null) ? null : now.subtract(Duration(days: _days!));

    Set<String>? sessionTypes;
    if (_type != null && _type!.trim().isNotEmpty) {
      sessionTypes = {_type!.trim()};
    } else {
      // 既定は「単元＋ミックス」を対象（= review_test は除外）
      sessionTypes = {'unit', 'mixed'};
    }

    return ScoreScope(
      from: from,
      to: null,
      sessionTypes: sessionTypes,
      onlyFinishedSessions: true,
      onlyLatestAttemptsPerCard: true,
      excludeWhenCorrectedLater: true,
    );
  }

  /// スコープ内の候補数（ユニーク誤答stableId）を試算
  Future<void> _probeAvailable() async {
    if (_probing) return;
    _probing = true;
    try {
      final store = AttemptStore();
      final scope = _buildScope();
      final freq = await store.getWrongFrequencyMapScoped(scope); // ★ ScoreScope渡しで統一
      if (!mounted) return;
      setState(() {
        _available = freq.length; // ユニークID数 = 候補枚数
      });
    } finally {
      _probing = false;
    }
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final attempts = AttemptStore();
      final loader = await DeckLoader.instance(); // シングルトン＋索引済み
      final scope = _buildScope();

      final builder = ReviewTestBuilder(
        attempts: attempts,
        loader: loader,
      );

      // 補充なしでTop-Nを構築（見つかった分だけ）
      final cards = await builder
          .buildTopNWithScope(topN: _selected, scope: scope)
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (cards.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('指定範囲に復習対象がありません。期間やタイプを見直してください。')),
        );
        Navigator.of(context).pop();
        return;
      }

      // ダミーデッキで QuizScreen を起動
      final fakeDeck = Deck(
        id: 'review',
        title: '復習テスト',
        isPurchased: true,
        units: const [],
      );

      await Navigator.push(
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

    final String scopeLabel = () {
      final d = _days;
      final t = _type;
      final daysPart = (d == null) ? '全期間' : '直近${d}日';
      final typePart =
          (t == null || t.isEmpty) ? '（タイプ: 単元+ミックス）' : '（タイプ: $t）';
      return '$daysPart$typePart';
    }();

    final String shortageHint =
        (_available >= 0 && _selected > _available)
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

            // 再計算
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
