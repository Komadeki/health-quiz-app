// lib/screens/review_cards_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../models/card.dart';
import '../services/attempt_store.dart';
import '../services/deck_loader.dart';
import '../services/session_scope.dart';
import '../utils/logger.dart';

class ReviewCardsScreen extends StatefulWidget {
  const ReviewCardsScreen({super.key});
  @override
  State<ReviewCardsScreen> createState() => _ReviewCardsScreenState();
}

enum MenuAction {
  sortOriginal,
  sortRandom,
  sortByFreq,
  sortByRecent,
  toggleRepeatedOnly
}

enum _SortState { original, random, freq, recent }

class _ReviewCardsScreenState extends State<ReviewCardsScreen> {
  bool _showAnswer = false;
  bool _onlyRepeated = false;
  _SortState _sortState = _SortState.original;

  final _rng = Random();

  List<QuizCard> _base = [];
  List<QuizCard> _cards = [];
  int _index = 0;
  bool _loading = true;

  final Map<QuizCard, String> _deckTitleCache = {};
  final Map<QuizCard, String> _unitTitleCache = {};

  final Map<String, QuizCard> _byStableId = {};
  final Map<String, QuizCard> _byInternalId = {};
  final Map<String, QuizCard> _byFull = {};
  final Map<String, List<QuizCard>> _byHead = {};

  int? _days = 30;
  String? _type;
  List<String>? _scopedSessionIds;

  // 画面表示用の“強め”正規化（見映え・部分一致用）
  String _norm(String s) {
    var t = s;
    t = t.replaceAll('\u3000', ' ');
    t = t.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
    t = t.replaceAll(RegExp(r'[「」『』\[\]\(\)（）]'), '');
    t = t.replaceAll(RegExp(r'[、，,]'), '、');
    t = t.replaceAll(RegExp(r'[。．.]'), '。');
    t = t.replaceAll(RegExp(r'\s+'), ' ');
    return t.trim();
  }

  // ★AttemptStoreのキー化と互換にする（空白を1つに畳むだけ）
  String _attemptStoreQuestionKey(String q) =>
      'Q::${q.trim().replaceAll(RegExp(r'\s+'), ' ')}';

  String _head(String s, [int n = 22]) {
    final t = _norm(s);
    return t.length > n ? t.substring(0, n) : t;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMany());
  }

  void _toggle() {
    setState(() => _showAnswer = !_showAnswer);
    debugPrint('[REVIEW] toggle -> $_showAnswer (idx=$_index)');
  }

  void _announce(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 900)),
    );
  }

  String _visible(String s) =>
      s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '').trim();

  Future<void> _loadMany() async {
    try {
      setState(() => _loading = true);

      final sessionIds = await SessionScope.collect(days: _days, type: _type);
      _scopedSessionIds = sessionIds;

      final attempts = AttemptStore();
      final loader = DeckLoader();

      // スコープ内の誤答（重複あり）
      final wrongQuestions = await attempts.getAllWrongCardIdsFiltered(
        onlySessionIds: sessionIds,
      );

      if (wrongQuestions.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('指定範囲に復習対象がありません'), duration: Duration(seconds: 2)),
        );
        unawaited(Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) Navigator.of(context).maybePop();
        }));
        setState(() => _loading = false);
        return;
      }

      // デッキ読み込み
      final decks = await loader.loadAll().timeout(const Duration(seconds: 12));
      final all = <QuizCard>[];
      final Map<QuizCard, String> titleOfDeck = {};
      final Map<QuizCard, String> titleOfUnit = {};

      for (final d in decks) {
        final deckTitle = d.title;
        Map<String, String>? unitMap;
        try {
          unitMap = (d as dynamic).unitTitleMap as Map<String, String>?;
        } catch (_) {
          unitMap = null;
        }
        for (final c in d.cards) {
          all.add(c);
          titleOfDeck[c] = deckTitle;
          try {
            final uid = (c as dynamic).unitId as String?;
            titleOfUnit[c] = (uid != null) ? (unitMap?[uid] ?? '') : '';
          } catch (_) {
            titleOfUnit[c] = '';
          }

          try {
            final sid = (c as dynamic).stableId as String?;
            if (sid != null && sid.isNotEmpty) _byStableId[sid] = c;
          } catch (_) {}
          try {
            final id = (c as dynamic).id as String?;
            if (id != null && id.isNotEmpty) _byInternalId[id] = c;
          } catch (_) {}
          final fq = _norm(c.question);
          _byFull.putIfAbsent(fq, () => c);
          (_byHead[_head(fq)] ??= []).add(c);
        }
      }

      // AttemptStoreから得た誤答の“質問文”で解決 → 重複除去
      final outCards = <QuizCard>[];
      final seen = <QuizCard>{};
      for (final raw in wrongQuestions.map(_norm).toSet()) {
        QuizCard? hit = _byFull[raw];
        if (hit == null) {
          final hk = _head(raw);
          final list = _byHead[hk];
          if (list != null && list.isNotEmpty) hit = list.first;
        }
        if (hit == null) {
          final hk2 = _head(raw, 12);
          hit = all.firstWhere(
            (c) => _norm(c.question).contains(hk2),
            orElse: () => all.first,
          );
        }
        if (hit != null && !seen.contains(hit)) {
          seen.add(hit);
          outCards.add(hit);
        }
      }

      outCards.shuffle(_rng);

      if (!mounted) return;
      setState(() {
        _base = List.of(outCards);
        _cards = List.of(outCards);
        _deckTitleCache..clear()..addAll(titleOfDeck);
        _unitTitleCache..clear()..addAll(titleOfUnit);
        _index = 0;
        _showAnswer = false;
        _loading = false;
      });
      AppLog.d('[REVIEW] prepared cards=${_cards.length} (scoped=${sessionIds.length})');
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppLog.e('[REVIEW] load failed: $e\n$st');
    }
  }

  Widget _buildMenu(BuildContext context) {
    return PopupMenuButton<MenuAction>(
      tooltip: 'メニュー',
      onSelected: (a) {
        switch (a) {
          case MenuAction.sortOriginal:
            _applySort(original: true);
            break;
          case MenuAction.sortRandom:
            _applySort(original: false);
            break;
          case MenuAction.sortByFreq:
            _applySortByFrequency();
            break;
          case MenuAction.sortByRecent:
            _applySortByRecency();
            break;
          case MenuAction.toggleRepeatedOnly:
            _toggleRepeatedOnly();
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: MenuAction.sortOriginal, child: Text('元の順')),
        const PopupMenuItem(value: MenuAction.sortRandom, child: Text('ランダム')),
        const PopupMenuDivider(),
        const PopupMenuItem(value: MenuAction.sortByFreq, child: Text('誤答頻度の高い順')),
        const PopupMenuItem(value: MenuAction.sortByRecent, child: Text('最新誤答が新しい順')),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: MenuAction.toggleRepeatedOnly,
          child: Row(
            children: [
              Icon(_onlyRepeated ? Icons.check_box : Icons.check_box_outline_blank),
              const SizedBox(width: 8),
              const Text('重複誤答のみ'),
            ],
          ),
        ),
      ],
      icon: const Icon(Icons.more_vert),
    );
  }

  void _applySort({required bool original}) {
    if (_base.isEmpty) return;
    setState(() {
      _cards = original ? List.of(_base) : (List.of(_base)..shuffle(_rng));
      _index = 0;
      _showAnswer = false;
      _sortState = original ? _SortState.original : _SortState.random;
    });
    _announce(original ? '並び替え：元の順' : '並び替え：ランダム');
  }

  // TopN再構築（残置）
  Future<void> _rebuildTopN(int n) async {
    try {
      final attempts = AttemptStore();
      final sessionIds =
          _scopedSessionIds ?? await SessionScope.collect(days: _days, type: _type);

      Map<String, int> freq = await attempts.getWrongFrequencyMap(
        onlySessionIds: sessionIds,
      );

      if (freq.isEmpty) {
        final qs = await attempts.getAllWrongCardIdsFiltered(
          onlySessionIds: sessionIds,
        );
        for (final raw in qs) {
          final k = _attemptStoreQuestionKey(raw);
          freq[k] = (freq[k] ?? 0) + 1;
        }
      }
      if (freq.isEmpty) return;

      final keys = freq.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top = keys.take(n).map((e) => e.key).toList();

      QuizCard? resolve(String key) {
        if (_byStableId.containsKey(key)) return _byStableId[key];
        if (_byInternalId.containsKey(key)) return _byInternalId[key];
        // attempt互換キーが Q::質問 なので、画面側の強め正規化→完全一致/先頭一致を試す
        final normed = _norm(key.startsWith('Q::') ? key.substring(3) : key);
        final f = _byFull[normed];
        if (f != null) return f;
        final hk = _head(normed);
        final list = _byHead[hk];
        if (list != null && list.isNotEmpty) return list.first;
        return null;
      }

      final out = <QuizCard>[];
      final seen = <QuizCard>{};
      for (final k in top) {
        final c = resolve(k);
        if (c != null && !seen.contains(c)) {
          seen.add(c);
          out.add(c);
        }
      }
      if (out.isEmpty) return;

      out.shuffle(_rng);
      if (!mounted) return;
      setState(() {
        _base = List.of(out);
        _cards = List.of(out);
        _index = 0;
        _showAnswer = false;
      });
      AppLog.d('[REVIEW] rebuildTopN=$n -> ${out.length} (scoped=${sessionIds.length})');
    } catch (e, st) {
      AppLog.e('[REVIEW] rebuildTopN failed: $e\n$st');
    }
  }

  // ★頻度の高い順
  Future<void> _applySortByFrequency() async {
    if (_base.isEmpty) return;
    try {
      final attempts = AttemptStore();
      final sessionIds =
          _scopedSessionIds ?? await SessionScope.collect(days: _days, type: _type);
      final freq = await attempts.getWrongFrequencyMap(onlySessionIds: sessionIds);

      int scoreOf(QuizCard c) {
        String? sid;
        try { sid = (c as dynamic).stableId as String?; } catch (_) {}
        final qKey = _attemptStoreQuestionKey(c.question);
        return (sid != null && sid.isNotEmpty && freq.containsKey(sid))
            ? (freq[sid] ?? 0)
            : (freq[qKey] ?? 0);
      }

      setState(() {
        _cards = List.of(_base)..sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));
        _index = 0;
        _showAnswer = false;
        _sortState = _SortState.freq;
      });

      final top5 = _cards.take(5).map((c) => scoreOf(c)).toList();
      debugPrint('[REVIEW] sort=freq top5 scores=$top5');
      _announce('並び替え：誤答頻度の高い順');
    } catch (e, st) {
      AppLog.e('[REVIEW] sortByFrequency failed: $e\n$st');
    }
  }

  // ★最新誤答が新しい順
  Future<void> _applySortByRecency() async {
    if (_base.isEmpty) return;
    try {
      final sessionIds =
          _scopedSessionIds ?? await SessionScope.collect(days: _days, type: _type);
      final latest = await _buildLatestWrongAtMap(sessionIds);

      DateTime epoch0 = DateTime.fromMillisecondsSinceEpoch(0);
      DateTime timeOf(QuizCard c) {
        String? sid;
        try { sid = (c as dynamic).stableId as String?; } catch (_) {}
        final qKey = _attemptStoreQuestionKey(c.question);
        if (sid != null && sid.isNotEmpty && latest.containsKey(sid)) {
          return latest[sid]!;
        }
        return latest[qKey] ?? epoch0;
      }

      setState(() {
        _cards = List.of(_base)..sort((a, b) => timeOf(b).compareTo(timeOf(a)));
        _index = 0;
        _showAnswer = false;
        _sortState = _SortState.recent;
      });

      final top3 =
          _cards.take(3).map((c) => timeOf(c).toIso8601String()).toList();
      debugPrint('[REVIEW] sort=recent top3 timestamps=$top3');
      _announce('並び替え：最新誤答が新しい順');
    } catch (e, st) {
      AppLog.e('[REVIEW] sortByRecency failed: $e\n$st');
    }
  }

  // ★重複誤答のみ
  Future<void> _toggleRepeatedOnly() async {
    _onlyRepeated = !_onlyRepeated;

    if (!_onlyRepeated) {
      setState(() {
        _cards = List.of(_base);
        _index = 0;
        _showAnswer = false;
      });
      _announce('フィルタ解除：重複誤答のみ OFF');
      return;
    }

    try {
      final attempts = AttemptStore();
      final sessionIds =
          _scopedSessionIds ?? await SessionScope.collect(days: _days, type: _type);
      final freq = await attempts.getWrongFrequencyMap(onlySessionIds: sessionIds);

      bool isRepeated(QuizCard c) {
        String? sid;
        try { sid = (c as dynamic).stableId as String?; } catch (_) {}
        final qKey = _attemptStoreQuestionKey(c.question);
        final n = ((sid != null && sid.isNotEmpty) ? (freq[sid] ?? 0) : 0)
                + (freq[qKey] ?? 0);
        return n >= 2;
      }

      final filtered = _base.where(isRepeated).toList();
      setState(() {
        _cards = filtered;
        _index = 0;
        _showAnswer = false;
      });

      debugPrint('[REVIEW] filter=repeated only -> ${filtered.length}/${_base.length}');
      _announce('重複誤答のみ：${filtered.length}/${_base.length}件');

      if (filtered.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('重複して誤答した問題はありません')),
        );
      }
    } catch (e, st) {
      AppLog.e('[REVIEW] toggleRepeatedOnly failed: $e\n$st');
    }
  }

  /// ★スコープ内の「最新誤答時刻」マップを推定
  /// key は stableId 優先、無ければ AttemptStore互換の 'Q::質問'
  Future<Map<String, DateTime>> _buildLatestWrongAtMap(List<String> sessionIds) async {
    DateTime? _ts(dynamic e) {
      // DateTime / ISO文字列 / epoch(秒/ms) に広めに対応
      try { final v = (e as dynamic).answeredAt; if (v is DateTime) return v; if (v is String) return DateTime.tryParse(v); if (v is num) return DateTime.fromMillisecondsSinceEpoch(v > 2000000000 ? v.toInt() : (v * 1000).toInt()); } catch (_) {}
      try { final v = (e as dynamic).answeredAtMs; if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt()); } catch (_) {}
      try { final v = (e as dynamic).timestamp;  if (v is DateTime) return v; if (v is String) return DateTime.tryParse(v); if (v is num) return DateTime.fromMillisecondsSinceEpoch(v > 2000000000 ? v.toInt() : (v * 1000).toInt()); } catch (_) {}
      try { final v = (e as dynamic).time;       if (v is num) return DateTime.fromMillisecondsSinceEpoch(v > 2000000000 ? v.toInt() : (v * 1000).toInt()); } catch (_) {}
      try { final v = (e as dynamic).at;         if (v is num) return DateTime.fromMillisecondsSinceEpoch(v > 2000000000 ? v.toInt() : (v * 1000).toInt()); } catch (_) {}
      try { final v = (e as dynamic).finishedAt; if (v is String) return DateTime.tryParse(v); } catch (_) {}
      try { final v = (e as dynamic).completedAt;if (v is String) return DateTime.tryParse(v); } catch (_) {}
      try { final v = (e as dynamic).createdAt;  if (v is DateTime) return v; if (v is String) return DateTime.tryParse(v); if (v is num) return DateTime.fromMillisecondsSinceEpoch(v > 2000000000 ? v.toInt() : (v * 1000).toInt()); } catch (_) {}
      return null;
    }

    String _keyFromAttempt(dynamic e) {
      try { final v = (e as dynamic).stableId as String?; if (v != null && v.trim().isNotEmpty) return v.trim(); } catch (_) {}
      try { final v = (e as dynamic).cardStableId as String?; if (v != null && v.trim().isNotEmpty) return v.trim(); } catch (_) {}
      try { final v = (e as dynamic).cardId as String?; if (v != null && v.trim().isNotEmpty) return v.trim(); } catch (_) {}
      final q = ((e as dynamic).question ?? '').toString();
      return _attemptStoreQuestionKey(q);
    }

    final store = AttemptStore();
    final map = <String, DateTime>{};

    for (final sid in sessionIds) {
      final attempts = await store.bySession(sid); // 新→古
      for (final a in attempts) {
        try { if ((a as dynamic).isCorrect == true) continue; } catch (_) { continue; }
        final key = _keyFromAttempt(a);
        if (key.isEmpty) continue;
        final t = _ts(a);
        if (t == null) continue;
        final cur = map[key];
        if (cur == null || t.isAfter(cur)) {
          map[key] = t;
        }
      }
    }
    return map;
  }

  void _go(int delta) {
    if (_cards.isEmpty) return;
    final next = (_index + delta).clamp(0, _cards.length - 1);
    if (next != _index) {
      setState(() {
        _index = next;
        _showAnswer = false;
      });
    }
  }

  String _safeAnswer(QuizCard c) {
    if (c.choices.isEmpty) return '';
    final i = c.answerIndex.clamp(0, c.choices.length - 1);
    return c.choices[i];
  }

  String _deckTitleOf(QuizCard c) {
    final t = _deckTitleCache[c];
    if (t != null && t.trim().isNotEmpty) return t;
    try {
      final d = (c as dynamic).deckTitle as String?;
      if (d != null && d.trim().isNotEmpty) return d;
    } catch (_) {}
    return '';
  }

  String _unitTitleOf(QuizCard c) {
    final t = _unitTitleCache[c];
    if (t != null && t.trim().isNotEmpty) return t;
    try {
      final u = (c as dynamic).unitTitle as String?;
      if (u != null && u.trim().isNotEmpty) return u;
    } catch (_) {}
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('見直しモード')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_cards.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('見直しモード')),
        body: const Center(child: Text('復習対象がありません')),
      );
    }

    final card = _cards[_index];
    final q = _visible(card.question);
    final ans = _safeAnswer(card);
    final exp = (card.explanation ?? '').trim();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final onBg = cs.onSurface;
    final onBg2 = cs.onSurface.withOpacity(0.68);
    final titleS = tt.titleMedium ?? const TextStyle(fontSize: 16);
    final labelS = tt.labelMedium ?? const TextStyle(fontSize: 12);
    final questionS = tt.headlineSmall ??
        const TextStyle(fontSize: 24, fontWeight: FontWeight.w700);

    final deckTitle = _deckTitleOf(card);
    final unitTitle = _unitTitleOf(card);

    final scopeLabel = () {
      final d = _days;
      final t = _type;
      final daysPart = (d == null) ? '全期間' : '直近${d}日';
      final typePart = (t == null) ? '' : '・タイプ:$t';
      return '$daysPart$typePart';
    }();

    final sortLabel = {
      _SortState.original: '元の順',
      _SortState.random: 'ランダム',
      _SortState.freq: '誤答頻度の高い順',
      _SortState.recent: '最新誤答が新しい順',
    }[_sortState]!;

    final hint = 'タップで答え表示 / スワイプで移動（スコープ: $scopeLabel）';

    return Scaffold(
      appBar: AppBar(
        title: const Text('見直しモード'),
        actions: [_buildMenu(context)],
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          onHorizontalDragEnd: (details) {
            final vx = details.velocity.pixelsPerSecond.dx;
            const threshold = 200.0;
            if (vx > threshold) {
              _go(-1);
            } else if (vx < -threshold) {
              _go(1);
            }
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (deckTitle.isNotEmpty)
                Text(
                  '・単元　$deckTitle',
                  style: titleS.copyWith(
                      color: onBg, fontWeight: FontWeight.w700, fontSize: (titleS.fontSize ?? 16) + 2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (unitTitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '・ユニット　$unitTitle',
                  style: labelS.copyWith(
                      color: onBg2, fontSize: (labelS.fontSize ?? 12) + 2),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 6),
              Text(hint, style: labelS.copyWith(color: onBg2)),
              const SizedBox(height: 4),
              Text(
                '並び: $sortLabel　|　フィルタ: ${_onlyRepeated ? "重複のみ" : "なし"}　|　${_cards.length}/${_base.length}件',
                style: labelS.copyWith(color: onBg2),
              ),
              const SizedBox(height: 12),

              Card(
                elevation: 2,
                color: Colors.white,
                shadowColor: cs.shadow.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: cs.outlineVariant.withOpacity(0.4), width: 1),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    q.isEmpty ? '(問題文なし)' : q,
                    style: questionS.copyWith(color: onBg),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) =>
                    FadeTransition(opacity: anim, child: child),
                child: _showAnswer
                    ? _AnswerCard(
                        key: const ValueKey('answer'),
                        answer: ans,
                        explanation: exp,
                      )
                    : const SizedBox.shrink(key: ValueKey('empty')),
              ),

              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _BottomBar(
        index: _index,
        total: _cards.length,
        onPrev: () => _go(-1),
        onNext: () => _go(1),
      ),
    );
  }
}

// ---- パーツ ----
class _AnswerCard extends StatelessWidget {
  final String answer;
  final String explanation;
  const _AnswerCard({required this.answer, required this.explanation, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final onBg = cs.onSurface;
    final labelS = tt.labelMedium ?? const TextStyle(fontSize: 12);
    final titleS =
        tt.titleMedium ?? const TextStyle(fontSize: 16, fontWeight: FontWeight.w700);

    return Card(
      elevation: 2,
      color: Colors.white,
      shadowColor: cs.shadow.withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.4), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: DefaultTextStyle(
          style: TextStyle(color: onBg, fontSize: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('答え', style: labelS.copyWith(color: onBg.withOpacity(0.8))),
              const SizedBox(height: 4),
              Text(
                answer,
                style: titleS.copyWith(color: onBg, fontWeight: FontWeight.w800),
              ),
              if (explanation.isNotEmpty) ...[
                const SizedBox(height: 12),
                Divider(height: 1, color: cs.outlineVariant.withOpacity(0.6)),
                const SizedBox(height: 12),
                Text(
                  explanation,
                  style: tt.bodyMedium ?? const TextStyle(fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final int total;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  const _BottomBar({
    super.key,
    required this.index,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final caption = tt.labelLarge ?? const TextStyle(fontSize: 14);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.6))),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: index > 0 ? onPrev : null,
              icon: const Icon(Icons.arrow_back_ios_new),
              tooltip: '前へ',
            ),
            const Spacer(),
            Text('${index + 1} / $total', style: caption.copyWith(color: cs.onSurface)),
            const Spacer(),
            IconButton(
              onPressed: index < total - 1 ? onNext : null,
              icon: const Icon(Icons.arrow_forward_ios),
              tooltip: '次へ',
            ),
          ],
        ),
      ),
    );
  }
}
