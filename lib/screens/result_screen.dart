import 'package:flutter/material.dart';
import '../models/score_record.dart';
import '../services/attempt_store.dart';
import 'attempt_history_screen.dart'; // 履歴画面への遷移用

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
  final Map<String, String>? unitTitleMap; // ★ 日本語タイトル表示用

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
      if (mounted) {
        setState(() => _saved = true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('結果を保存しました')),
        );
      }
    } catch (e) {
      // 失敗しても致命傷ではないので軽くログ程度に
    }
  }

  @override
  Widget build(BuildContext context) {
    final rate =
        widget.total == 0 ? '0.0' : (widget.correct / widget.total * 100).toStringAsFixed(1);
    final ub = widget.unitBreakdown ?? const {};

    print('UB keys: ${(widget.unitBreakdown ?? {}).keys.toList()}');
    print('unitTitleMap keys: ${widget.unitTitleMap?.keys.take(5).toList()}');
    final k = (widget.unitBreakdown ?? {}).keys.first;
    print('lookup sample: ${widget.unitTitleMap?[k]}');

    return Scaffold(
      appBar: AppBar(title: const Text('結果')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'スコア: ${widget.correct} / ${widget.total}',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('正答率: $rate %', style: const TextStyle(fontSize: 18)),
            if (widget.durationSec != null) ...[
              const SizedBox(height: 4),
              Text('解答時間: ${_fmtDuration(widget.durationSec!)}',
                  style: const TextStyle(fontSize: 16, color: Colors.black54)),
            ],
            if (widget.deckTitle != null) ...[
              const SizedBox(height: 4),
              Text('デッキ: ${widget.deckTitle!}',
                  style: const TextStyle(fontSize: 16, color: Colors.black54)),
            ],

            if (ub.isNotEmpty) ...[
              const SizedBox(height: 24),
              _UnitBreakdownCard(
                unitBreakdown: ub,
                totalQuestions: widget.total,
                unitTitleMap: widget.unitTitleMap, // ★ここで渡す
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
                        unitTitleMap: widget.unitTitleMap, // ★日本語タイトルを引き継ぎ
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],

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
    );
  }

  String _fmtDuration(int secs) {
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${m}分${s}秒';
  }
}

// ===== 出題内訳カード（日本語タイトル対応） =====
class _UnitBreakdownCard extends StatelessWidget {
  final Map<String, int> unitBreakdown;
  final int totalQuestions;
  final Map<String, String>? unitTitleMap;

  const _UnitBreakdownCard({
    required this.unitBreakdown,
    required this.totalQuestions,
    this.unitTitleMap,
  });

  @override
  Widget build(BuildContext context) {
    final entries = unitBreakdown.entries.toList()
      ..sort((a, b) {
        final c = b.value.compareTo(a.value);
        return c != 0 ? c : a.key.compareTo(b.key);
      });

    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '出題内訳',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...entries.map((e) {
              final count = e.value;
              final ratio = totalQuestions == 0 ? 0.0 : count / totalQuestions;
              final pct = (ratio * 100).toStringAsFixed(0);
              final title = unitTitleMap?[e.key] ?? e.key; // ★ここで日本語タイトルを適用

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                        Text('$count問（$pct%）',
                            style: const TextStyle(fontSize: 13)),
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
          ],
        ),
      ),
    );
  }
}
