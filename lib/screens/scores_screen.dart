// lib/screens/scores_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/score_record.dart';
import '../services/score_store.dart';
import '../services/deck_loader.dart';
import '../widgets/quiz_analytics.dart';
import 'attempt_history_screen.dart';

class ScoresScreen extends StatefulWidget {
  const ScoresScreen({super.key});

  @override
  State<ScoresScreen> createState() => _ScoresScreenState();
}

class _ScoresScreenState extends State<ScoresScreen> {
  bool _loading = true;
  List<ScoreRecord> _records = [];
  Map<String, String> _unitTitleMap = {};

  @override
  void initState() {
    super.initState();
    _load();
    debugPrint('📊 ScoresScreen(ScoreStore版) mounted');
  }

  Future<void> _load() async {
    try {
      final records = await ScoreStore.instance.loadAll();
      records.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final decks = await DeckLoader().loadAll();
      final unitTitleMap = <String, String>{};
      for (final d in decks) {
        final units = d.units ?? const [];
        for (final u in units) {
          if (u.id.isNotEmpty) unitTitleMap[u.id] = u.title;
        }
      }

      if (!mounted) return;
      setState(() {
        _records = records;
        _unitTitleMap = unitTitleMap;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('成績の読み込みに失敗しました: $e')),
      );
    }
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
                    final dt =
                        DateTime.fromMillisecondsSinceEpoch(r.timestamp);
                    final when =
                        '${dt.year}/${dt.month.toString().padLeft(2, "0")}/${dt.day.toString().padLeft(2, "0")} '
                        '${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}';
                    final ubStat = (r.unitBreakdown ?? const <String, int>{})
                        .map((k, v) => MapEntry(k, UnitStat(asked: v, wrong: 0)));

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
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () => _onTapRecord(context, r),
                              onLongPress: () => _showRecordActions(context, r),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Icon(
                                      Icons.assessment_outlined,
                                      color: theme.colorScheme.primary,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (r.deckTitle.isNotEmpty
                                              ? r.deckTitle
                                              : r.deckId),
                                          style: theme.textTheme.titleMedium
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w700),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '$when・${(r.selectedUnitIds == null) ? "単元" : "ミックス"}',
                                          style: theme.textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '$rate%',
                                        style: theme.textTheme.titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 2),
                                      Text('${r.score} / ${r.total}',
                                          style: theme.textTheme.bodySmall),
                                      if (r.sessionId != null &&
                                          r.sessionId!.isNotEmpty)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 4),
                                          child: Tooltip(
                                            message: '履歴を開く',
                                            child: InkResponse(
                                              radius: 18,
                                              onTap: () =>
                                                  _onTapRecord(context, r),
                                              child: const Icon(Icons.history,
                                                  size: 18),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (ubStat.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              UnitRatioChips(
                                unitBreakdown: ubStat,
                                unitTitleMap: _unitTitleMap,
                                topK: 3,
                              ),
                            ],
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
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AttemptHistoryScreen(
          sessionId: record.sessionId!,
          unitTitleMap: _unitTitleMap,
        ),
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('この成績には履歴がありません（旧バージョン）')),
      );
    }
  }

  Future<void> _showRecordActions(BuildContext context, ScoreRecord r) async {
    final canOpenHistory = r.sessionId != null && r.sessionId!.isNotEmpty;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canOpenHistory)
                ListTile(
                  leading: const Icon(Icons.history),
                  title: const Text('履歴を開く'),
                  onTap: () {
                    Navigator.pop(context);
                    _onTapRecord(context, r);
                  },
                ),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('共有（この成績をコピー）'),
                onTap: () async {
                  Navigator.pop(context);
                  await _shareRecord(r);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('この成績を削除'),
                onTap: () async {
                  Navigator.pop(context);
                  await _deleteRecord(context, r);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _shareRecord(ScoreRecord r) async {
    final payload = {
      'id': r.id,
      'timestamp': r.timestamp,
      'deckId': r.deckId,
      'deckTitle': r.deckTitle,
      'score': r.score,
      'total': r.total,
      'durationSec': r.durationSec,
      'sessionId': r.sessionId,
      'selectedUnitIds': r.selectedUnitIds,
      'unitBreakdown': r.unitBreakdown,
      'tags': r.tags?.map((k, v) => MapEntry(k, {
            'correct': v.correct,
            'wrong': v.wrong,
            'asked': v.correct + v.wrong,
          })),
      'exportedAt': DateTime.now().toIso8601String(),
      'format': 'ScoreRecord.v2',
    };
    await Clipboard.setData(ClipboardData(text: jsonEncode(payload)));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('成績データをクリップボードへコピーしました')),
    );
  }

  Future<void> _deleteRecord(BuildContext context, ScoreRecord r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('この成績を削除しますか？'),
        content: Text(
            '${r.deckTitle.isNotEmpty ? r.deckTitle : r.deckId}\n${DateTime.fromMillisecondsSinceEpoch(r.timestamp)}'),
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
    if (ok != true) return;

    try {
      await ScoreStore.instance.delete(r.id); // delete 実装必要
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('成績を削除しました')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
    }
  }
}
