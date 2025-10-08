// lib/screens/scores_screen.dart
import 'package:flutter/material.dart';
import 'package:health_quiz_app/widgets/quiz_analytics.dart';
import '../services/score_store.dart';
import '../services/deck_loader.dart';
import '../models/score_record.dart';
import 'attempt_history_screen.dart';

class ScoresScreen extends StatefulWidget {
  const ScoresScreen({super.key});

  @override
  State<ScoresScreen> createState() => _ScoresScreenState();
}

class _ScoresScreenState extends State<ScoresScreen> {
  bool _loading = true;
  List<ScoreRecord> _records = const [];
  Map<String, String> _unitTitleMap = const {}; // ★ 追加：ユニットID→日本語タイトル

  @override
  void initState() {
    super.initState();
    _load();
    debugPrint('📊 ScoresScreen(ScoreStore版) mounted');
  }

  Future<void> _load() async {
    // 成績の読み込み
    final records = await ScoreStore.instance.loadAll();
    records.sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // デッキからユニットタイトルマップを構築
    final decks = await DeckLoader().loadAll();
    final unitTitleMap = <String, String>{};
    for (final d in decks) {
      final units = d.units ?? const [];
      for (final u in units) {
        if (u.id.isNotEmpty) {
          unitTitleMap[u.id] = u.title;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _records = records;
      _unitTitleMap = unitTitleMap;
      _loading = false;
    });
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('成績を削除しますか？'),
        content: const Text('保存済みの全履歴を削除します。元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ScoreStore.instance.clearAll();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('成績を削除しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('成績'),
        actions: [
          IconButton(
            tooltip: '全削除',
            icon: const Icon(Icons.delete_outline),
            onPressed: _records.isEmpty ? null : _confirmClear,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _records.isEmpty
              ? const Center(child: Text('まだ成績がありません'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemCount: _records.length,
                  itemBuilder: (_, i) {
                    final r = _records[i];
                    final rate =
                        (r.total == 0) ? 0 : ((r.score * 100) / r.total).round();

                    final dt = DateTime.fromMillisecondsSinceEpoch(r.timestamp);
                    final when =
                        '${dt.year}/${dt.month.toString().padLeft(2, "0")}/${dt.day.toString().padLeft(2, "0")} '
                        '${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}';

                    // unitBreakdown を UnitStat 化（誤答数はここでは 0 固定）
                    final Map<String, UnitStat> ubStat =
                        (r.unitBreakdown ?? const <String, int>{})
                            .map((k, v) => MapEntry(
                                  k,
                                  UnitStat(asked: v, wrong: 0),
                                ));

                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.assessment_outlined,
                                color: theme.colorScheme.primary,
                              ),
                              title: Text(
                                (r.deckTitle.isNotEmpty ? r.deckTitle : r.deckId),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                '$when・${(r.selectedUnitIds == null) ? "単元" : "ミックス"}',
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '$rate%',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${r.score} / ${r.total}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                              onTap: () => _onTapRecord(context, r),
                            ),

                            // === 追加: 主要ユニットチップ ===
                            if (ubStat.isNotEmpty)
                              UnitRatioChips(
                                unitBreakdown: ubStat,
                                unitTitleMap: _unitTitleMap, // ★ ここで全体のマップを渡す
                                topK: 2,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  Future<void> _onTapRecord(BuildContext context, ScoreRecord record) async {
    if (record.sessionId != null && record.sessionId!.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AttemptHistoryScreen(
            sessionId: record.sessionId!,
            unitTitleMap: _unitTitleMap, // ★ ここでも再利用
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('この成績には履歴がありません（旧バージョン）')),
      );
    }
  }
}
