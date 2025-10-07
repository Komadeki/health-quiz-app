import 'package:flutter/material.dart';
import '../services/attempt_store.dart';
import '../models/attempt_entry.dart';
import '../services/deck_loader.dart';
import '../models/deck.dart';
import '../models/card.dart';
import 'quiz_screen.dart';

class AttemptHistoryScreen extends StatelessWidget {
  final String sessionId;
  const AttemptHistoryScreen({super.key, required this.sessionId});

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

          // ★ 集計
          final total = items.length;
          final correctCount = items.where((e) => e.isCorrect).length;
          final wrongCount = total - correctCount;
          final avgMs = total == 0
              ? 0
              : (items.fold<int>(0, (sum, e) => sum + e.durationMs) / total)
                  .round();

          // ★ 画面内だけで状態を持つ（誤答のみ表示トグル）
          bool showOnlyWrong = false;

          return StatefulBuilder(
            builder: (context, setState) {
              final visible = showOnlyWrong
                  ? items.where((e) => !e.isCorrect).toList()
                  : items;

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                itemCount: visible.length + 1, // サマリー＋履歴行
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSummary(correctCount, wrongCount, avgMs),
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

                  final a = visible[i - 1];
                  final correct = a.isCorrect;

                  // ★ 表示用に 1-based 保証（旧データ救済）
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

  // ★ 秒数は切り捨て＋最小1秒＋単位「秒」
  String _formatSec(int ms) {
    final sec = (ms / 1000).floor().clamp(1, 9999);
    return '${sec}秒';
  }

  String _formatTs(DateTime ts) {
    final m = ts.month.toString().padLeft(2, '0');
    final d = ts.day.toString().padLeft(2, '0');
    final hh = ts.hour.toString().padLeft(2, '0');
    final mm = ts.minute.toString().padLeft(2, '0');
    return '$m/$d $hh:$mm';
  }

  // ==== UIビルダー ====

  // ★ 集計カード
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

  // ★ 単問リプレイ
  Future<void> _replaySingle(BuildContext context, AttemptEntry a) async {
    final loader = DeckLoader();
    final decks = await loader.loadAll();
    final deck = decks.firstWhere(
      (d) => d.id == a.unitId,
      orElse: () => decks.first,
    );
    final QuizCard? found = deck.cards.firstWhere(
      (c) => c.question.trim() == a.question.trim(),
      orElse: () => deck.cards.first,
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizScreen(deck: deck, overrideCards: [found!]),
      ),
    );
  }

  // ★ 誤答だけ再挑戦
  Future<void> _replayWrong(
      BuildContext context, List<AttemptEntry> items) async {
    final wrong = items.where((e) => !e.isCorrect).toList();
    if (wrong.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('今回の誤答はありません')),
      );
      return;
    }

    final loader = DeckLoader();
    final decks = await loader.loadAll();
    final unitId = wrong.first.unitId;
    final deck =
        decks.firstWhere((d) => d.id == unitId, orElse: () => decks.first);

    final set = <String>{};
    final list = <QuizCard>[];
    for (final a in wrong) {
      final q = a.question.trim();
      if (set.contains(q)) continue;
      final match = deck.cards.firstWhere(
        (c) => c.question.trim() == q,
        orElse: () => deck.cards.first,
      );
      set.add(q);
      list.add(match);
    }

    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('カードの特定に失敗しました')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizScreen(deck: deck, overrideCards: list),
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
        isCorrect ? Colors.green.withOpacity(0.05) : Colors.red.withOpacity(0.06);
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
            color: Colors.black.withOpacity(0.06),
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
