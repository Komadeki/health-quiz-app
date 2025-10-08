// lib/screens/result_screen.dart
import 'package:flutter/material.dart';
import 'package:health_quiz_app/widgets/quiz_analytics.dart'; // SummaryStackedBar, computeTopUnits, UnitStat, segmentColor
import '../models/score_record.dart';
import '../services/attempt_store.dart';
import 'attempt_history_screen.dart';

class ResultScreen extends StatefulWidget {
  final int total;
  final int correct;
  final String? sessionId;
  final Map<String, int>? unitBreakdown;

  // 保存関連（任意）
  final String? deckId;
  final String? deckTitle;
  final int? durationSec;
  final int? timestamp;
  final List<String>? selectedUnitIds;
  final Map<String, TagStat>? tags;
  final bool saveHistory;

  // 表示関連
  final Map<String, String>? unitTitleMap; // 日本語タイトル表示用

  const ResultScreen({
    super.key,
    required this.total,
    required this.correct,
    this.sessionId,
    this.unitBreakdown,
    this.deckId,
    this.deckTitle,
    this.durationSec,
    this.timestamp,
    this.selectedUnitIds,
    this.tags,
    this.saveHistory = true,
    this.unitTitleMap,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _maybeSaveRecordOnce();
  }

  Future<void> _maybeSaveRecordOnce() async {
    if (_saved) return;
    if (!widget.saveHistory) return;
    if (widget.deckId == null || widget.deckTitle == null) return;

    final record = ScoreRecord(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      deckId: widget.deckId!,
      deckTitle: widget.deckTitle!,
      score: widget.correct,
      total: widget.total,
      timestamp: widget.timestamp ?? DateTime.now().millisecondsSinceEpoch,
      durationSec: widget.durationSec,
      tags: widget.tags,
      selectedUnitIds: widget.selectedUnitIds,
      sessionId: widget.sessionId,
      unitBreakdown: widget.unitBreakdown,
    );

    try {
      await AttemptStore().addScore(record);
      if (!mounted) return;
      setState(() => _saved = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('結果を保存しました')),
      );
    } catch (_) {
      // 失敗は致命的でないので握りつぶす
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.total;
    final correct = widget.correct;
    final wrong = (total - correct).clamp(0, total);

    // サマリバー用に Map<String,int> -> Map<String,UnitStat>(wrong=0) へ変換
    final ub = widget.unitBreakdown ?? const <String, int>{};
    final breakdownForBar = ub.map((k, v) => MapEntry(k, UnitStat(asked: v, wrong: 0)));
    final top = computeTopUnits(
      unitBreakdown: breakdownForBar,
      unitTitleMap: widget.unitTitleMap,
      topN: 4,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('結果')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            // スコアヘッダ
            _scoreHeader(context, total: total, correct: correct, wrong: wrong),
            const SizedBox(height: 16),

            // 出題サマリ（総計100% 横積みバー）
            Text('出題サマリー', style: Theme.of(context).textTheme.titleMedium),
            SummaryStackedBar(data: top),
            const SizedBox(height: 12),

            // 出題内訳カード（既存置換OK）
            if (ub.isNotEmpty)
              _UnitBreakdownCard(
                unitBreakdown: ub,
                totalQuestions: total,
                unitTitleMap: widget.unitTitleMap,
              ),

            const SizedBox(height: 24),

            if (widget.durationSec != null)
              Text(
                '解答時間: ${_fmtDuration(widget.durationSec!)}',
                style: const TextStyle(fontSize: 16, color: Colors.black54),
              ),
            if (widget.deckTitle != null) ...[
              const SizedBox(height: 4),
              Text(
                'デッキ: ${widget.deckTitle!}',
                style: const TextStyle(fontSize: 16, color: Colors.black54),
              ),
            ],
            const SizedBox(height: 24),

            if (widget.sessionId != null && widget.sessionId!.isNotEmpty) ...[
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
                      builder: (_) => AttemptHistoryScreen(
                        sessionId: widget.sessionId!,
                        unitTitleMap: widget.unitTitleMap,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],

            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
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
    );
  }

  Widget _scoreHeader(BuildContext context,
      {required int total, required int correct, required int wrong}) {
    final rate = total > 0 ? (correct / total) : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '正解 $correct / $total（${(rate * 100).toStringAsFixed(1)}%）',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (wrong > 0)
              Chip(
                label: Text('誤答 $wrong'),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }

  String _fmtDuration(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '$m分$s秒';
  }
}

// ===== 出題内訳カード（日本語タイトル対応・5件まで表示＆開閉） =====
class _UnitBreakdownCard extends StatefulWidget {
  final Map<String, int> unitBreakdown;
  final int totalQuestions;
  final Map<String, String>? unitTitleMap;

  /// 初期表示件数（デフォルト 5）
  final int initialMax;

  const _UnitBreakdownCard({
    super.key,
    required this.unitBreakdown,
    required this.totalQuestions,
    this.unitTitleMap,
    this.initialMax = 5,
  });

  @override
  State<_UnitBreakdownCard> createState() => _UnitBreakdownCardState();
}

class _UnitBreakdownCardState extends State<_UnitBreakdownCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.unitBreakdown.isEmpty) return const SizedBox.shrink();

    final entries = widget.unitBreakdown.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value); // 件数降順
        return c != 0 ? c : a.key.compareTo(b.key); // 同数ならキー昇順
      });

    final total = widget.totalQuestions;
    final showToggle = entries.length > widget.initialMax;
    final visibleCount =
        _expanded ? entries.length : entries.length.clamp(0, widget.initialMax);

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '出題内訳',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // 可視分のみ描画
            for (var i = 0; i < visibleCount; i++)
              _row(
                context: context,
                index: i,
                title: (widget.unitTitleMap?[entries[i].key] ?? entries[i].key),
                asked: entries[i].value,
                total: total == 0
                    ? widget.unitBreakdown.values
                        .fold<int>(0, (a, b) => a + b) // 念のための保険
                    : total,
              ),

            if (showToggle) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  label: Text(
                    _expanded
                        ? '閉じる'
                        : 'もっと見る（全${entries.length}件）',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  // ignore: unused_element_parameter
  Widget _row({
    required BuildContext context,
    required int index,
    required String title,
    required int asked,
    required int total,
  }) {
    final ratio = total > 0 ? asked / total : 0.0;
    final pctStr = (ratio * 100).toStringAsFixed(0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // カラーインジケータ（ResultScreenのサマリバーに合わせて index 色）
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: segmentColor(index),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
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
              Text('$asked問（$pctStr%）', style: const TextStyle(fontSize: 13)),
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
  }
}
