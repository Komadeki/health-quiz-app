// lib/screens/scores_screen.dart  ← 完全版（ScoreStore/ScoreRecord を使用）
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
    debugPrint('📊 ScoresScreen(ScoreStore版) mounted'); // 目印
  }

  Future<void> _load() async {
    final records = await ScoreStore.instance.loadAll();
    records.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // 新→古
    if (!mounted) return;
    setState(() {
      _records = records;
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

                    return Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 1,
                      child: ListTile(
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
                    );
                  },
                ),
    );
  }

  Future<void> _onTapRecord(BuildContext context, ScoreRecord record) async {
    if (record.sessionId != null && record.sessionId!.isNotEmpty) {
      // ★ユニットID→ユニット名を構築
      final decks = await DeckLoader().loadAll();
      final unitTitleMap = <String, String>{};
      for (final d in decks) {
        final units = d.units ?? const [];
        for (final u in units) {
          if (u.id.isNotEmpty) unitTitleMap[u.id] = u.title;
        }
      }

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AttemptHistoryScreen(
            sessionId: record.sessionId!,
            unitTitleMap: unitTitleMap, // ← 日本語タイトルを渡す
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
