// lib/screens/scores_screen.dart
import 'package:flutter/material.dart';
import '../services/scores_store.dart';
import '../services/deck_loader.dart';

class ScoresScreen extends StatefulWidget {
  const ScoresScreen({super.key});

  @override
  State<ScoresScreen> createState() => _ScoresScreenState();
}

class _ScoresScreenState extends State<ScoresScreen> {
  bool _loading = true;
  List<QuizResult> _results = [];
  Map<String, String> _deckTitleById = {}; // deckId -> title

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = ScoresStore();
    final results = await store.loadAll();

    // タイトル解決用にデッキ一覧も読む
    final decks = await DeckLoader().loadAll();
    final map = <String, String>{for (final d in decks) d.id: d.title};
    map['mixed'] = 'ミックス練習';

    setState(() {
      _results = results;
      _deckTitleById = map;
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
      await ScoresStore().clearAll();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('成績を削除しました')));
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
            onPressed: _results.isEmpty ? null : _confirmClear,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _results.isEmpty
          ? const Center(child: Text('まだ成績がありません'))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final r = _results[i];
                final title = _deckTitleById[r.deckId] ?? r.deckId;
                final rate = (r.total == 0)
                    ? 0
                    : ((r.correct * 100) / r.total).round();
                final ts = r.timestamp; // ローカル表示
                final when =
                    '${ts.year}/${ts.month.toString().padLeft(2, "0")}/${ts.day.toString().padLeft(2, "0")} '
                    '${ts.hour.toString().padLeft(2, "0")}:${ts.minute.toString().padLeft(2, "0")}';

                return Card(
                  child: ListTile(
                    title: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      '$when・${r.mode == "mixed" ? "ミックス" : "単元"}',
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '$rate%',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${r.correct} / ${r.total}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
