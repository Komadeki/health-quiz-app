import 'package:flutter/material.dart';
import '../services/attempt_store.dart';
import '../models/attempt_entry.dart';
import '../services/deck_loader.dart';
import '../models/card.dart';
import 'quiz_screen.dart';
import 'package:health_quiz_app/widgets/quiz_analytics.dart'; // ErrorRateTag

class AttemptHistoryScreen extends StatelessWidget {
  final String sessionId;

  /// ★任意：ユニットID→日本語タイトル
  final Map<String, String>? unitTitleMap;

  const AttemptHistoryScreen({
    super.key,
    required this.sessionId,
    this.unitTitleMap,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('今回の履歴')),
      body: FutureBuilder<List<AttemptEntry>>(
        future: AttemptStore().bySession(sessionId),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final raw = snap.data ?? const <AttemptEntry>[];

          // ★ 新しい順にソート（逆順で来ても安全）
          final items = raw.toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

          if (items.isEmpty) {
            return const Center(child: Text('履歴が見つかりません'));
          }

          // ===== 集計（今回のセッション） =====
          final total = items.length;
          final correctCount = items.where((e) => e.isCorrect).length;
          final wrongCount = total - correctCount;
          final avgMs = total == 0
              ? 0
              : (items.fold<int>(0, (sum, e) => sum + e.durationMs) / total)
                  .round();

          // ユニット別の件数・誤答数を同時に集計
          final Map<String, int> unitCounts = {};
          final Map<String, int> unitWrongs = {};

          for (final e in items) {
            final id = e.unitId.isNotEmpty ? e.unitId : 'unknown';

            unitCounts.update(id, (v) => v + 1, ifAbsent: () => 1);
            if (!e.isCorrect) {
              unitWrongs.update(id, (v) => v + 1, ifAbsent: () => 1);
            }
          }

          // 合計問題数（単純にunitCountsの合計）
          final unitTotal = unitCounts.values.fold<int>(0, (a, b) => a + b);

          // 画面内だけで状態を持つ（誤答のみ表示トグル）
          bool showOnlyWrong = false;

          return StatefulBuilder(
            builder: (context, setState) {
              final visible =
                  showOnlyWrong ? items.where((e) => !e.isCorrect).toList() : items;

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                itemCount: visible.length + 2, // サマリー + ユニット内訳 + 履歴行
                itemBuilder: (context, i) {
                  // 0: 集計サマリー ＋ トグル/誤答再挑戦
                  if (i == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSummary(correctCount, wrongCount, avgMs),
                        const SizedBox(height: 8),
                        _UnitBreakdownCard(
                          unitCounts: unitCounts,
                          totalQuestions: unitTotal,
                          unitTitleMap: unitTitleMap,
                          unitWrongs: unitWrongs, // ★ 追加
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilterChip(
                            label: const Text('誤答のみ表示'),
                            selected: showOnlyWrong,
                            onSelected: (v) => setState(() {
                              showOnlyWrong = v;
                            }),
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('誤答だけもう一度'),
                          onPressed: () => _replayWrong(context, items),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 48),
                            textStyle: const TextStyle(fontSize: 16),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    );
                  }

                  // 1: セクション見出し（履歴一覧）
                  if (i == 1) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                      child: Text(
                        '履歴一覧（今回）',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    );
                  }

                  // 2..: 履歴行
                  final a = visible[i - 2];
                  final correct = a.isCorrect;

                  // 表示用に 1-based 保証（旧データ救済）
                  final looksZeroBased =
                      (a.selectedIndex == 0) || (a.correctIndex == 0);
                  final sel =
                      looksZeroBased ? (a.selectedIndex + 1) : a.selectedIndex;
                  final ans =
                      looksZeroBased ? (a.correctIndex + 1) : a.correctIndex;

                  return _AttemptTile(
                    attempt: a,
                    title: 'Q${a.questionNumber}. ${_trim(a.question, 48)}',
                    subtitle:
                        '選択: $sel / 正答: $ans ・ 時間: ${_formatSec(a.durationMs)} ・ ${_formatTs(a.timestamp)}',
                    isCorrect: correct,
                    onTap: () async {
                      await _replaySingle(context, a);
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  // ==== 補助関数群 ====

  String _trim(String s, int max) =>
      (s.length <= max) ? s : '${s.substring(0, max)}…';

  // 秒数は切り捨て＋最小1秒＋単位「秒」
  String _formatSec(int ms) {
    final sec = (ms / 1000).floor().clamp(1, 9999);
    return '$sec秒';
  }

  String _formatTs(DateTime ts) {
    final m = ts.month.toString().padLeft(2, '0');
    final d = ts.day.toString().padLeft(2, '0');
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');
    return '$m/$d $hh:$mm';
  }

  // ==== UIビルダー ====

  // 集計カード（正解/不正解/平均/正答率）
  Widget _buildSummary(int correct, int wrong, int avgMs) {
    final rate = (correct + wrong) == 0
        ? 0
        : (correct * 100 / (correct + wrong)).toStringAsFixed(1);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(
          children: [
            const Icon(Icons.insights, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '正解 $correct ・ 不正解 $wrong ・ 平均 ${_formatSec(avgMs)} ・ 正答率 $rate%',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==== 機能 ====

  // 単問リプレイ
  Future<void> _replaySingle(BuildContext context, AttemptEntry a) async {
    // awaitの前にNavigatorを確保
    final nav = Navigator.of(context);

    final loader = await DeckLoader.instance();
    final decks = await loader.loadAll();

    // AttemptEntry.unitId に紐づくデッキを取得
    final deck = decks.firstWhere(
      (d) => d.id == a.unitId,
      orElse: () => decks.first,
    );

    final found = deck.cards.firstWhere(
      (c) => c.question.trim() == a.question.trim(),
      orElse: () => deck.cards.first,
    );

    if (!context.mounted) return;

    await nav.push(
      MaterialPageRoute(
        builder: (_) => QuizScreen(deck: deck, overrideCards: [found]),
      ),
    );
  }

  // 誤答だけ再挑戦
  Future<void> _replayWrong(BuildContext context, List<AttemptEntry> items) async {
    final wrong = items.where((e) => !e.isCorrect).toList();
    if (wrong.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('今回の誤答はありません')),
      );
      return;
    }

    // awaitの前にNavigatorを確保
    final nav = Navigator.of(context);

    final loader = await DeckLoader.instance();
    final decks = await loader.loadAll();

    // まず最初の誤答の unitId を採用（同一デッキ前提）
    final unitId = wrong.first.unitId;
    final deck = decks.firstWhere(
      (d) => d.id == unitId,
      orElse: () => decks.first,
    );

    // 重複質問を除外してカードを収集
    final set = <String>{};
    final list = <QuizCard>[];
    for (final a in wrong) {
      final q = a.question.trim();
      if (!set.add(q)) continue; // 既出はスキップ
      final match = deck.cards.firstWhere(
        (c) => c.question.trim() == q,
        orElse: () => deck.cards.first,
      );
      list.add(match);
    }

    if (list.isEmpty) {
     if (!context.mounted) return;
     final messenger = ScaffoldMessenger.of(context);
     messenger.showSnackBar(
       const SnackBar(content: Text('カードの特定に失敗しました')),
     );
     return;
    }

    if (!context.mounted) return;

    await nav.push(
      MaterialPageRoute(
        builder: (_) => QuizScreen(deck: deck, overrideCards: list),
      ),
    );
  }
}

/// ===== ユニット別内訳カード（今回） =====
class _UnitBreakdownCard extends StatefulWidget {
  final Map<String, int> unitCounts;
  final Map<String, int> unitWrongs;
  final int totalQuestions;
  final Map<String, String>? unitTitleMap;
  // ignore: unused_element_parameter
  final int maxCollapsedCount; // 折りたたみ時の表示件数（既定=5）

  const _UnitBreakdownCard({
    required this.unitCounts,
    required this.totalQuestions,
    required this.unitWrongs,
    this.unitTitleMap,
    this.maxCollapsedCount = 5, // ★ デフォルトを与えて初期化（required にしてもOK）
  });

  @override
  State<_UnitBreakdownCard> createState() => _UnitBreakdownCardState();
}

class _UnitBreakdownCardState extends State<_UnitBreakdownCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.unitCounts.isEmpty) return const SizedBox.shrink();

    // 並び順（直前に導入した「誤答率の高い順」）
    final entries = widget.unitCounts.entries.toList()
      ..sort((a, b) {
        final wrongA = widget.unitWrongs[a.key] ?? 0;
        final wrongB = widget.unitWrongs[b.key] ?? 0;
        final rateA = a.value == 0 ? 0 : wrongA / a.value;
        final rateB = b.value == 0 ? 0 : wrongB / b.value;
        final cmp = rateB.compareTo(rateA); // 誤答率降順
        if (cmp != 0) return cmp;
        final c = b.value.compareTo(a.value); // 件数降順
        return c != 0 ? c : a.key.compareTo(b.key);
      });

    final showToggle = entries.length > widget.maxCollapsedCount;
    final visibleEntries = _expanded
        ? entries
        : entries.take(widget.maxCollapsedCount).toList();

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ユニット別出題割合（今回）',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            // 本体リスト
            ...visibleEntries.map((e) {
              final asked = e.value;
              final wrong = widget.unitWrongs[e.key] ?? 0;
              final ratio = widget.totalQuestions == 0 ? 0.0 : asked / widget.totalQuestions;
              final pct = (ratio * 100).toStringAsFixed(0);
              final title = widget.unitTitleMap?[e.key] ?? e.key;

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // 左：タイトル＋誤答率
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 赤いChip（compact=false）
                              ErrorRateTag(
                                asked: asked,
                                wrong: wrong,
                                compact: false,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text('$asked問（$pct%）', style: const TextStyle(fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: ratio.clamp(0, 1),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              );
            }),

            // トグルボタン（6件以上のときだけ）
            if (showToggle) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Text(
                      _expanded
                          ? '閉じる'
                          : 'もっと見る（全${entries.length}件）',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }
}


/// ==== 個別タイル ====
class _AttemptTile extends StatelessWidget {
  final AttemptEntry attempt;
  final String title;
  final String subtitle;
  final bool isCorrect;
  final VoidCallback onTap;

  const _AttemptTile({
    required this.attempt,
    required this.title,
    required this.subtitle,
    required this.isCorrect,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg =
        isCorrect ? Colors.green.withValues(alpha: 0.05) : Colors.red.withValues(alpha: 0.06);
    final bar = isCorrect ? Colors.green : Colors.red;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            blurRadius: 6,
            offset: const Offset(0, 2),
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Row(
            children: [
              Container(
                width: 6,
                height: 78,
                decoration: BoxDecoration(
                  color: bar,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                ),
              ),
              Expanded(
                child: ListTile(
                  leading: Icon(
                    isCorrect ? Icons.check_rounded : Icons.close_rounded,
                    color: bar,
                  ),
                  title: Text(title),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(subtitle),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
