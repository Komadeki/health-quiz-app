// lib/screens/scores_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/score_record.dart';
import '../services/score_store.dart';
import '../services/deck_loader.dart';
import '../widgets/quiz_analytics.dart';
import 'attempt_history_screen.dart';

// ★ 追加：誤答カード再特定で使用
import '../services/attempt_store.dart';
import '../models/attempt_entry.dart';
import '../models/card.dart';
import '../utils/stable_id.dart';
import 'quiz_screen.dart';

enum RecordKindFilter { all, unit, mix, retry, reviewTest }
enum SortMode { newest, oldest, accuracy }

class ScoresScreen extends StatefulWidget {
  const ScoresScreen({super.key});

  @override
  State<ScoresScreen> createState() => _ScoresScreenState();
}

class _ScoresScreenState extends State<ScoresScreen> {
  bool _loading = true;
  List<ScoreRecord> _records = [];
  Map<String, String> _unitTitleMap = {};

  // フィルタ & 並び替え
  RecordKindFilter _kind = RecordKindFilter.all;
  DateTimeRange? _range;
  SortMode _sort = SortMode.newest;

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

      final decks = await (await DeckLoader.instance()).loadAll();

      // デッキ名・ユニット名マップを同時構築
      final Map<String, String> deckTitleMap = {};
      final Map<String, String> unitTitleMap = {};
      for (final d in decks) {
        final deckId = d.id.trim();
        final deckTitle = d.title.trim();
        if (deckId.isNotEmpty) {
          deckTitleMap[deckId] = deckTitle.isNotEmpty ? deckTitle : deckId;
        }
        for (final u in (d.units ?? const [])) {
          final unitId = u.id.trim();
          final unitTitle = u.title.trim();
          if (unitId.isNotEmpty) {
            unitTitleMap[unitId] = unitTitle.isNotEmpty ? unitTitle : unitId;
          }
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

  // ===== 種別フィルタ =====
  List<ScoreRecord> get _filteredSorted {
    Iterable<ScoreRecord> it = _records;

    switch (_kind) {
      case RecordKindFilter.all:
        // 全件表示
        break;

      case RecordKindFilter.unit:
        // 単元のみ = 「ミックス練習」「誤答だけもう一度*」「復習テスト」を除外
        it = it.where((r) {
          final t = r.deckTitle.trim();
          final isMix = (t == 'ミックス練習');
          final isRetry = t.startsWith('誤答だけもう一度');
          final isReviewTest = (t == '復習テスト');
          return !isMix && !isRetry && !isReviewTest;
        });
        break;

      case RecordKindFilter.mix:
        // 「ミックス練習」だけ
        it = it.where((r) => r.deckTitle.trim() == 'ミックス練習');
        break;

      case RecordKindFilter.retry:
        // 「誤答だけもう一度」だけ
        it = it.where((r) => r.deckTitle.trim().startsWith('誤答だけもう一度'));
        break;

      case RecordKindFilter.reviewTest:
        // 「復習テスト」だけ（まず type を見て、無い旧データはタイトルで判定）
        it = it.where((r) => r.deckTitle.trim() == '復習テスト');
        break;

      case RecordKindFilter.reviewTest:
        it = it.where((r) => r.deckTitle.trim() == '復習テスト');
        break;
    }

    // ===== 日付範囲 =====
    if (_range != null) {
      final startMs = DateTime(_range!.start.year, _range!.start.month, _range!.start.day)
          .millisecondsSinceEpoch;
      final endMs = DateTime(_range!.end.year, _range!.end.month, _range!.end.day, 23, 59, 59, 999)
          .millisecondsSinceEpoch;
      it = it.where((r) => r.timestamp >= startMs && r.timestamp <= endMs);
    }

    // ===== ソート =====
    final list = it.toList();
    switch (_sort) {
      case SortMode.newest:
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        break;
      case SortMode.oldest:
        list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        break;
      case SortMode.accuracy:
        double acc(ScoreRecord r) => (r.total == 0) ? -1.0 : (r.score / r.total);
        list.sort((a, b) => acc(b).compareTo(acc(a)));
        break;
    }

    return list;
  }


  Future<void> _pickRange() async {
    final now = DateTime.now();
    final first = DateTime(now.year - 3, 1, 1);
    final last = DateTime(now.year + 1, 12, 31);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: _range,
      helpText: '期間を選択',
    );
    if (picked != null) setState(() => _range = picked);
  }

  String _fmtYmd(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('成績を削除しますか？'),
        content: const Text('保存済みの全履歴を削除します。元に戻せません。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('削除')),
        ],
      ),
    );
    if (ok == true) {
      await ScoreStore.instance.clearAll();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('成績を削除しました')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredSorted;

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
              : Column(
                  children: [
                    // ===== 上部ツールバー（1行に集約） =====
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          DropdownButton<RecordKindFilter>(
                            value: _kind,
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(value: RecordKindFilter.all, child: Text('すべて')),
                              DropdownMenuItem(value: RecordKindFilter.unit, child: Text('単元')),
                              DropdownMenuItem(value: RecordKindFilter.mix, child: Text('ミックス')),
                              DropdownMenuItem(value: RecordKindFilter.retry, child: Text('誤答だけ')),
                              DropdownMenuItem(value: RecordKindFilter.reviewTest, child: Text('復習テスト')),
                            ],
                            onChanged: (v) => setState(() => _kind = v ?? _kind),
                          ),
                          DropdownButton<SortMode>(
                            value: _sort,
                            underline: const SizedBox(),
                            items: const [
                              DropdownMenuItem(value: SortMode.newest, child: Text('新しい順')),
                              DropdownMenuItem(value: SortMode.oldest, child: Text('古い順')),
                              DropdownMenuItem(value: SortMode.accuracy, child: Text('正答率順')),
                            ],
                            onChanged: (v) => setState(() => _sort = v ?? _sort),
                          ),
                          // 期間ボタン（横幅が足りない端末では自動折返し）
                          OutlinedButton.icon(
                            icon: const Icon(Icons.event),
                            label: Text(_range == null
                                ? '期間を選択'
                                : '${_fmtYmd(_range!.start)} ～ ${_fmtYmd(_range!.end)}'),
                            onPressed: _pickRange,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              minimumSize: const Size(0, 40),
                              visualDensity: const VisualDensity(horizontal: -1, vertical: -1),
                            ),
                          ),
                          if (_range != null)
                            TextButton.icon(
                              icon: const Icon(Icons.close),
                              label: const Text('クリア'),
                              onPressed: () => setState(() => _range = null),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                visualDensity: const VisualDensity(horizontal: -1, vertical: -2),
                              ),
                            ),
                          Text('全 ${filtered.length} 件', style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const Divider(height: 1),

                    // ===== リスト（フィルタ適用後） =====
                    Expanded(
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final r = filtered[i];
                          final rate = (r.total == 0) ? 0 : ((r.score * 100) / r.total).round();
                          final dt = DateTime.fromMillisecondsSinceEpoch(r.timestamp);
                          final when =
                              '${dt.year}/${dt.month.toString().padLeft(2, "0")}/${dt.day.toString().padLeft(2, "0")} '
                              '${dt.hour.toString().padLeft(2, "0")}:${dt.minute.toString().padLeft(2, "0")}';

                          final Map<String, UnitStat> ubStat =
                              (r.unitBreakdown ?? const <String, int>{})
                                  .map((k, v) => MapEntry(k, UnitStat(asked: v, wrong: 0)));

                          return Card(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                            elevation: 1,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // ヘッダ（タップで履歴、長押しでアクション）
                                  InkWell(
                                    borderRadius: BorderRadius.circular(10),
                                    onTap: () => _onTapRecord(context, r),
                                    onLongPress: () => _showRecordActions(context, r),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Icon(Icons.assessment_outlined,
                                              color: theme.colorScheme.primary, size: 24),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                (r.deckTitle.isNotEmpty ? r.deckTitle : r.deckId),
                                                style: theme.textTheme.titleMedium
                                                    ?.copyWith(fontWeight: FontWeight.w700),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '$when',
                                                style: theme.textTheme.bodySmall,
                                              ),
                                            ],
                                          ),
                                        ),
                                        Column(
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '$rate%',
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 2),
                                            Text('${r.score} / ${r.total}',
                                                style: theme.textTheme.bodySmall),
                                            if (r.sessionId != null && r.sessionId!.isNotEmpty)
                                              Padding(
                                                padding: const EdgeInsets.only(top: 4),
                                                child: Tooltip(
                                                  message: '履歴を開く',
                                                  child: InkResponse(
                                                    radius: 18,
                                                    onTap: () => _onTapRecord(context, r),
                                                    child: const Icon(Icons.history, size: 18),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),

                                  // 主要ユニットチップ
                                  if (ubStat.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Theme(
                                      data: theme.copyWith(
                                        chipTheme: theme.chipTheme.copyWith(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                                          side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.25)),
                                        ),
                                        textTheme: theme.textTheme.copyWith(
                                          bodySmall: theme.textTheme.bodySmall?.copyWith(height: 1.0),
                                        ),
                                      ),
                                      child: UnitRatioChips(
                                        unitBreakdown: ubStat,
                                        unitTitleMap: _unitTitleMap,
                                        topK: 3,
                                        padding: const EdgeInsets.only(top: 0),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }

  // ====== レコード操作 ======

  Future<void> _onTapRecord(BuildContext context, ScoreRecord record) async {
    if (record.sessionId != null && record.sessionId!.isNotEmpty) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AttemptHistoryScreen(
            sessionId: record.sessionId!,
            unitTitleMap: _unitTitleMap,
          ),
        ),
      );
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
              if (canOpenHistory)
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('誤答だけもう一度'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _replayWrongFromScore(context, r.sessionId!);
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
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
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
          '${r.deckTitle.isNotEmpty ? r.deckTitle : r.deckId}\n'
          '${DateTime.fromMillisecondsSinceEpoch(r.timestamp)}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('削除')),
        ],
      ),
    );
    if (ok != true) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ScoreStore.instance.delete(r.id);
      await _load();
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('成績を削除しました')));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('削除に失敗しました: $e')));
    }
  }

  // ====== ここから「誤答だけもう一度」実装（成績→セッションID起点） ======

  // AttemptEntry 1件に対応する QuizCard を全デッキから探索（stableId優先）
  Future<QuizCard?> _findCardForAttempt(AttemptEntry a) async {
    final loader = await DeckLoader.instance();
    final decks = await loader.loadAll();

    // 1) unitId 一致のデッキを優先
    var deckByUnit = decks.where((d) => d.id == a.unitId);
    // 2) stableId で検索（所属デッキ→全デッキ）
    final sid = (a.stableId ?? '').trim();
    if (sid.isNotEmpty) {
      if (deckByUnit.isNotEmpty) {
        try {
          return deckByUnit.first.cards.firstWhere(
            (c) => stableIdForOriginal(c) == sid,
          );
        } catch (_) {}
      }
      for (final d in decks) {
        try {
          return d.cards.firstWhere((c) => stableIdForOriginal(c) == sid);
        } catch (_) {}
      }
    }

    // 3) フォールバック：質問文一致（所属デッキ→全デッキ）
    final q = a.question.trim();
    if (q.isNotEmpty && deckByUnit.isNotEmpty) {
      try {
        return deckByUnit.first.cards.firstWhere((c) => c.question.trim() == q);
      } catch (_) {}
    }
    if (q.isNotEmpty) {
      for (final d in decks) {
        try {
          return d.cards.firstWhere((c) => c.question.trim() == q);
        } catch (_) {}
      }
    }
    return null;
  }

  // セッションIDから「誤答だけ」を復元し、QuizScreen(overrideCards)で再挑戦
  Future<void> _replayWrongFromScore(BuildContext context, String sessionId) async {
    final attempts = await AttemptStore().bySession(sessionId);
    final wrong = attempts.where((e) => !e.isCorrect).toList();

    if (wrong.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('この回の誤答はありません')),
      );
      return;
    }

    // 重複排除キー（stableId 優先、なければ質問文正規化）
    String keyOf(AttemptEntry a) {
      final sid = (a.stableId ?? '').trim();
      if (sid.isNotEmpty) return 'S::$sid';
      return 'Q::${a.question.replaceAll(RegExp(r'\\s+'), ' ').trim()}';
    }

    final seen = <String>{};
    final cards = <QuizCard>[];

    for (final a in wrong) {
      if (!seen.add(keyOf(a))) continue;
      final c = await _findCardForAttempt(a);
      if (c != null) cards.add(c);
    }

    if (cards.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('カードの特定に失敗しました')),
      );
      return;
    }

    if (!context.mounted) return;
    // QuizScreen は overrideCards 指定時 deck.cards を使わないため、どのデッキでもOK
    final decks = await (await DeckLoader.instance()).loadAll();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => QuizScreen(
          deck: decks.first,         // ダミー
          overrideCards: cards,      // ← これが実際の出題セット
          type: 'retry_wrong',
        ),
      ),
    );
  }
}
