// lib/screens/review_test_setup_screen.dart
import 'package:flutter/material.dart';

import '../models/card.dart';
import '../models/deck.dart';
import '../services/deck_loader.dart';
import '../services/attempt_store.dart';
import '../services/score_store.dart';          // ★ Score を読む
import 'quiz_screen.dart';

class ReviewTestSetupScreen extends StatefulWidget {
  const ReviewTestSetupScreen({super.key});
  @override
  State<ReviewTestSetupScreen> createState() => _ReviewTestSetupScreenState();
}

class _ReviewTestSetupScreenState extends State<ReviewTestSetupScreen> {
  final _options = const [10, 20, 30, 50];
  int _count = 20;
  bool _loading = false;
  String? _error;

  int? _candidateCount;

  @override
  void initState() {
    super.initState();
    _recalcCandidates();
  }

  /// 復習テストの素材にする「対象セッションID」を取得
  /// - 期間制限なし（必要になったらここで days フィルタを入れる）
  /// - deckTitle == '復習テスト' を **除外**
  Future<List<String>> _eligibleSessionIds() async {
    final scores = await ScoreStore.instance.loadAll();
    // 新しい順に近いデータから
    final filtered = scores.where((s) => s.deckTitle.trim() != '復習テスト');
    // 空でない sessionId を集める
    final ids = <String>[];
    for (final s in filtered) {
      final sid = (s.sessionId ?? '').trim();
      if (sid.isNotEmpty) ids.add(sid);
    }
    return ids;
  }

  Future<void> _recalcCandidates() async {
    setState(() => _candidateCount = null);

    final sessionIds = await _eligibleSessionIds();
    final freq = await AttemptStore().getWrongFrequencyMap(
      onlySessionIds: sessionIds,
    );

    setState(() => _candidateCount = freq.length);
  }

  @override
  Widget build(BuildContext context) {
    final countLabel = _candidateCount == null ? '-' : '$_candidateCount';
    final startDisabled = (_candidateCount ?? 0) == 0 || _loading;

    return Scaffold(
      appBar: AppBar(title: const Text('復習テストの設定')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('出題数を選択', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                children: _options.map((n) {
                  final selected = _count == n;
                  return ChoiceChip(
                    label: Text('$n問'),
                    selected: selected,
                    onSelected: (_) => setState(() => _count = n),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Text(
                '（候補は$countLabel 件。候補が少ない場合は不足分を補充しません）',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: const TextStyle(color: Colors.red)),
                ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.play_arrow),
                  label: _loading ? const Text('準備中…') : const Text('開始'),
                  onPressed: startDisabled
                      ? null
                      : () async {
                          setState(() {
                            _loading = true;
                            _error = null;
                          });
                          try {
                            // 1) 対象セッション集合（復習テストは除外）
                            final sessionIds = await _eligibleSessionIds();

                            // 2) 誤答頻度 & 最新誤答時刻
                            final store = AttemptStore();
                            final freq = await store.getWrongFrequencyMap(
                              onlySessionIds: sessionIds,
                            );
                            if (freq.isEmpty) {
                              setState(() {
                                _error = '誤答履歴がありません。先に通常の練習を行ってください。';
                                _loading = false;
                              });
                              return;
                            }
                            final latest = await store.getWrongLatestAtMap(
                              onlySessionIds: sessionIds,
                            );

                            // 3) 頻度降順 → 同率は最新誤答が新しい順で並べる
                            final ordered = freq.entries.toList()
                              ..sort((a, b) {
                                final c = b.value.compareTo(a.value);
                                if (c != 0) return c;
                                final ta = latest[a.key];
                                final tb = latest[b.key];
                                if (ta == null && tb == null) return 0;
                                if (ta == null) return 1;
                                if (tb == null) return -1;
                                return tb.compareTo(ta);
                              });
                            final pickedIds =
                                ordered.take(_count).map((e) => e.key).toList();

                            // 4) 安定ID → QuizCard 解決
                            final loader = await DeckLoader.instance();

                            // DeckLoader のAPIでまとめて変換
                            final List<QuizCard> cards = loader.mapStableIdsToCards(pickedIds);

                            if (cards.isEmpty) {
                              setState(() {
                                _error = 'カードの特定に失敗しました';
                                _loading = false;
                              });
                              return;
                            }
                            cards.shuffle();

                            if (!mounted) return;

                            // 5) overrideCards を使うので、どのデッキでも可（先頭を使用）
                            final decks = await loader.loadAll();
                            final Deck deck = decks.first;

                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => QuizScreen(
                                  deck: deck,
                                  overrideCards: cards,
                                  sessionType: 'review_test',
                                ),
                              ),
                            );
                          } catch (e) {
                            if (!mounted) return;
                            setState(() {
                              _error = 'カード選定に失敗しました';
                              _loading = false;
                            });
                          }
                        },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '候補（ユニーク誤答）：$countLabel 件（復習テストの履歴は除外）',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _recalcCandidates,
                icon: const Icon(Icons.refresh),
                label: const Text('候補を再計算'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
