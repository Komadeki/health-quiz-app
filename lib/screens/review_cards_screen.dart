// lib/screens/review_cards_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../models/card.dart';
import '../services/attempt_store.dart';
import '../services/deck_loader.dart';
import '../services/session_scope.dart';
import '../utils/logger.dart';
import '../utils/stable_id.dart';

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
  toggleRepeatedOnly,
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

  // 表示情報（落とさない）
  final Map<QuizCard, String> _deckTitleCache = {};
  final Map<QuizCard, String> _unitTitleCache = {};

  // スコープ（UI は現状固定：直近30日・全タイプ。必要ならこの2つを外部から受け取るよう拡張可）
  final int _days = 30; // null で全期間
  String? _type; // 'unit' | 'mixed' | 'review_test' | null
  List<String>? _scopedSessionIds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCards());
  }

  // ===================================================
  // stableId ベースの完全版ロード
  // ===================================================
  Future<void> _loadCards() async {
    try {
      setState(() => _loading = true);

      // Score(成績) からセッションIDを収集（期間/type の絞り込みは SessionScope 側）
      final sessionIds = await SessionScope.collect(days: _days, type: _type);
      _scopedSessionIds = sessionIds;

      final store = AttemptStore();
      final loader = await DeckLoader.instance();

      // ここが肝：誤答の stableId（ユニーク）だけを取得（無くても後段でフォールバック）
      final wrongIds = await store.getWrongStableIdsUnique(
        onlySessionIds: sessionIds,
      );

      // 現在の assets から sid→card の逆引きを作成（DeckLoader 依存の getByStableId に頼らない）
      final decks = await loader.loadAll();
      final bySid = <String, QuizCard>{};
      for (final d in decks) {
        for (final c in d.cards) {
          bySid[_sidOf(c)] = c; // 安定ID（元順MD5）
        }
      }

      // stableId リストからカードを復元
      final outCards = <QuizCard>[
        for (final id in wrongIds)
          if (bySid.containsKey(id)) bySid[id]!,
      ];

      // 0件なら質問文ベースでフォールバック（古い Attempt で stableId が無い場合の救済）
      if (outCards.isEmpty) {
        final qs = await store.getAllWrongCardIdsFiltered(
          onlySessionIds: sessionIds,
        );
        String norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

        QuizCard? findByQuestion(String qnorm) {
          // 完全一致 → 先頭一致(最大16文字) → 部分一致の順で走査
          for (final c in bySid.values) {
            if (norm(c.question) == qnorm) return c;
          }
          final headLen = min(qnorm.length, 16);
          final head = qnorm.substring(0, headLen);
          for (final c in bySid.values) {
            if (norm(c.question).startsWith(head)) return c;
          }
          for (final c in bySid.values) {
            if (norm(c.question).contains(head)) return c;
          }
          return null;
        }

        final seen = <QuizCard>{};
        for (final q in qs.map(norm).toSet()) {
          final hit = findByQuestion(q);
          if (hit != null && seen.add(hit)) outCards.add(hit);
        }
        AppLog.d('[REVIEW] fallback by question -> ${outCards.length}');
      }

      outCards.shuffle(_rng);

      // 表示用にデッキ/ユニット名のキャッシュも作っておく（情報は落とさない）
      await _buildDeckUnitTitleCaches(loader);

      if (!mounted) return;
      if (outCards.isEmpty) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('復習対象がありません')));
        Navigator.of(context).maybePop();
        return;
      }

      setState(() {
        _base = List.of(outCards);
        _cards = List.of(outCards);
        _index = 0;
        _showAnswer = false;
        _loading = false;
      });

      AppLog.d(
        '[REVIEW] loaded ${_cards.length} cards (stableId-based, scoped=${sessionIds.length})',
      );
    } catch (e, st) {
      AppLog.e('[REVIEW] loadCards failed: $e\n$st');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// デッキ／ユニット名をカードにひも付ける（Deck モデル差異に耐えるように動的アクセス）
  Future<void> _buildDeckUnitTitleCaches(DeckLoader loader) async {
    _deckTitleCache.clear();
    _unitTitleCache.clear();

    final decks = await loader.loadAll();
    for (final d in decks) {
      final deckTitle = d.title;

      // パターン1: units -> cards
      try {
        final units = (d as dynamic).units as List<dynamic>?;
        if (units != null) {
          for (final u in units) {
            final unitTitle = (u as dynamic).title as String? ?? '';
            final cards = (u as dynamic).cards as List<QuizCard>? ?? const [];
            for (final c in cards) {
              _deckTitleCache[c] = deckTitle;
              _unitTitleCache[c] = unitTitle;
            }
          }
        }
      } catch (_) {}

      // パターン2: 直下に cards
      try {
        final cards = (d as dynamic).cards as List<QuizCard>?;
        if (cards != null) {
          for (final c in cards) {
            _deckTitleCache.putIfAbsent(c, () => deckTitle);
            // unit は取れない場合があるので空にしておく
            _unitTitleCache.putIfAbsent(c, () => '');
          }
        }
      } catch (_) {}

      // パターン3: unitTitleMap 経由（DeckLoader が付与している場合）
      try {
        final unitMap = (d as dynamic).unitTitleMap as Map<String, String>?;
        if (unitMap != null) {
          Iterable<QuizCard> allCards = const [];
          try {
            allCards = (d as dynamic).cards as List<QuizCard>? ?? const [];
          } catch (_) {}
          try {
            final units = (d as dynamic).units as List<dynamic>?;
            if (units != null) {
              for (final u in units) {
                final cs = (u as dynamic).cards as List<QuizCard>? ?? const [];
                allCards = [...allCards, ...cs];
              }
            }
          } catch (_) {}

          for (final c in allCards) {
            _deckTitleCache.putIfAbsent(c, () => deckTitle);
            try {
              final uid = (c as dynamic).unitId as String?;
              if (uid != null && uid.isNotEmpty) {
                final ut = unitMap[uid] ?? '';
                if (ut.isNotEmpty) _unitTitleCache[c] = ut;
              }
            } catch (_) {}
          }
        }
      } catch (_) {}
    }
  }

  // ===================== ここから：クラス内ヘルパー =====================
  Future<Map<String, int>> _fetchFreqWithFallback() async {
    final store = AttemptStore();

    // 1) まず公式API
    Map<String, int> freq = {};
    try {
      freq = await store.getWrongFrequencyByStableId(
        onlySessionIds: _scopedSessionIds,
      );
    } catch (_) {}

    // freq が空 or 全部0ならフォールバック判定（必ず _sidOf(c) で照合）
    final allZero =
        freq.isEmpty || _base.every((c) => (freq[_sidOf(c)] ?? 0) == 0);
    if (!allZero) return freq;

    // 2) Attempt を直接なめて、isCorrect==false をカウント
    final Map<String, int> fb = {};
    try {
      if (_scopedSessionIds == null || _scopedSessionIds!.isEmpty) return fb;
      for (final sid in _scopedSessionIds!) {
        final atts = await store.bySession(sid);
        for (final a in atts) {
          try {
            final dyn = a as dynamic;
            final st = (dyn.stableId ?? '').toString().trim();
            final ok = (dyn.isCorrect == true);
            if (st.isEmpty || ok) continue;
            fb[st] = (fb[st] ?? 0) + 1;
          } catch (_) {}
        }
      }
      AppLog.d(
        '[REVIEW] freq fallback scan -> matched=${fb.length}/${_base.length}',
      );
    } catch (_) {}
    return fb;
  }

  Future<Map<String, DateTime>> _fetchLatestWithFallback() async {
    final store = AttemptStore();

    // 1) まず公式API
    Map<String, DateTime> latest = {};
    try {
      latest = await store.getLatestWrongAtByStableId(
        onlySessionIds: _scopedSessionIds,
      );
    } catch (_) {}

    final epoch0 = DateTime.fromMillisecondsSinceEpoch(0);
    final emptyOrEpoch =
        latest.isEmpty ||
        _base.every((c) => (latest[_sidOf(c)] ?? epoch0) == epoch0);
    if (!emptyOrEpoch) return latest;

    // 2) Attempt を直接なめて、直近の×時刻を採用
    final Map<String, DateTime> fb = {};
    DateTime? ts(dynamic e) {
      try {
        final v = (e as dynamic).timestamp;
        if (v is DateTime) return v;
        if (v is num)
          return DateTime.fromMillisecondsSinceEpoch(
            v > 2000000000 ? v.toInt() : (v * 1000).toInt(),
          );
        if (v is String) return DateTime.tryParse(v);
      } catch (_) {}
      try {
        final v = (e as dynamic).answeredAt;
        if (v is DateTime) return v;
        if (v is num)
          return DateTime.fromMillisecondsSinceEpoch(
            v > 2000000000 ? v.toInt() : (v * 1000).toInt(),
          );
        if (v is String) return DateTime.tryParse(v);
      } catch (_) {}
      try {
        final v = (e as dynamic).createdAt;
        if (v is DateTime) return v;
        if (v is num)
          return DateTime.fromMillisecondsSinceEpoch(
            v > 2000000000 ? v.toInt() : (v * 1000).toInt(),
          );
        if (v is String) return DateTime.tryParse(v);
      } catch (_) {}
      return null;
    }

    try {
      if (_scopedSessionIds == null || _scopedSessionIds!.isEmpty) return fb;
      for (final sid in _scopedSessionIds!) {
        final atts = await store.bySession(sid);
        for (final a in atts) {
          try {
            final dyn = a as dynamic;
            final st = (dyn.stableId ?? '').toString().trim();
            final ok = (dyn.isCorrect == true);
            if (st.isEmpty || ok) continue;
            final t = ts(a);
            if (t == null) continue;
            final cur = fb[st];
            if (cur == null || t.isAfter(cur)) fb[st] = t;
          } catch (_) {}
        }
      }
      AppLog.d(
        '[REVIEW] latest fallback scan -> matched=${fb.length}/${_base.length}',
      );
    } catch (_) {}
    return fb;
  }
  // ===================== ここまで：クラス内ヘルパー =====================

  // Attempt 保存時と同一ロジック（stable_id.dart）に統一
  String _sidOf(QuizCard c) => stableIdForOriginal(c);

  // ===================================================
  // 並べ替え／フィルタ（stableIdベース）
  // ===================================================
  Future<void> _applySortByFrequency() async {
    if (_base.isEmpty) return;

    final freq = await _fetchFreqWithFallback(); // 既存の取得ヘルパーを利用

    int scoreOf(QuizCard c) => freq[_sidOf(c)] ?? 0;

    setState(() {
      _cards = List.of(_base)..sort((a, b) => scoreOf(b).compareTo(scoreOf(a)));
      _index = 0;
      _showAnswer = false;
      _sortState = _SortState.freq;
    });

    final top5 = _cards.take(5).map((c) => scoreOf(c)).toList();
    AppLog.d('[REVIEW] sort=freq top5=$top5');
    _announce('並び替え：誤答頻度の高い順');
  }

  Future<void> _applySortByRecency() async {
    if (_base.isEmpty) return;

    final latest = await _fetchLatestWithFallback(); // 既存の取得ヘルパーを利用
    final epoch0 = DateTime.fromMillisecondsSinceEpoch(0);

    DateTime timeOf(QuizCard c) => latest[_sidOf(c)] ?? epoch0;

    setState(() {
      _cards = List.of(_base)..sort((a, b) => timeOf(b).compareTo(timeOf(a)));
      _index = 0;
      _showAnswer = false;
      _sortState = _SortState.recent;
    });

    final top3 = _cards
        .take(3)
        .map((c) => timeOf(c).toIso8601String())
        .toList();
    AppLog.d('[REVIEW] sort=recent top3=$top3');
    _announce('並び替え：最新誤答が新しい順');
  }

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

    final freq = await _fetchFreqWithFallback(); // 既存の取得ヘルパーを利用
    bool isRepeated(QuizCard c) => (freq[_sidOf(c)] ?? 0) >= 2;

    final filtered = _base.where(isRepeated).toList();
    setState(() {
      _cards = filtered;
      _index = 0;
      _showAnswer = false;
    });

    AppLog.d('[REVIEW] filter=repeated -> ${filtered.length}/${_base.length}');
    _announce('重複誤答のみ：${filtered.length}/${_base.length}件');

    if (filtered.isEmpty && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('重複して誤答した問題はありません')));
    }
  }

  // ===================================================
  // UI（既存踏襲）
  // ===================================================
  void _toggle() => setState(() => _showAnswer = !_showAnswer);

  void _announce(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(milliseconds: 900)),
    );
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

  String _deckTitleOf(QuizCard c) => _deckTitleCache[c] ?? '';
  String _unitTitleOf(QuizCard c) => _unitTitleCache[c] ?? '';

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
    final q = (card.question).trim();
    final ans = _safeAnswer(card);
    final exp = (card.explanation ?? '').trim();

    final deckTitle = _deckTitleOf(card);
    final unitTitle = _unitTitleOf(card);

    return Scaffold(
      appBar: AppBar(
        title: const Text('見直しモード'),
        actions: [
          PopupMenuButton<MenuAction>(
            onSelected: (a) {
              switch (a) {
                case MenuAction.sortOriginal:
                  setState(() {
                    _cards = List.of(_base);
                    _index = 0;
                    _showAnswer = false;
                    _sortState = _SortState.original;
                  });
                  _announce('並び替え：元の順');
                  break;
                case MenuAction.sortRandom:
                  setState(() {
                    _cards = List.of(_base)..shuffle(_rng);
                    _index = 0;
                    _showAnswer = false;
                    _sortState = _SortState.random;
                  });
                  _announce('並び替え：ランダム');
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
            itemBuilder: (context) => const [
              PopupMenuItem(value: MenuAction.sortOriginal, child: Text('元の順')),
              PopupMenuItem(value: MenuAction.sortRandom, child: Text('ランダム')),
              PopupMenuDivider(),
              PopupMenuItem(
                value: MenuAction.sortByFreq,
                child: Text('誤答頻度の高い順'),
              ),
              PopupMenuItem(
                value: MenuAction.sortByRecent,
                child: Text('最新誤答が新しい順'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: MenuAction.toggleRepeatedOnly,
                child: Text('重複誤答のみ'),
              ),
            ],
          ),
        ],
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggle,
        onHorizontalDragEnd: (details) {
          final vx = details.velocity.pixelsPerSecond.dx;
          const threshold = 200.0;
          if (vx > threshold) _go(-1);
          if (vx < -threshold) _go(1);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (deckTitle.isNotEmpty || unitTitle.isNotEmpty) ...[
              Text(
                '・単元　$deckTitle',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (unitTitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '・ユニット　$unitTitle',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              const SizedBox(height: 10),
            ],
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Theme.of(
                    context,
                  ).colorScheme.outlineVariant.withOpacity(0.4),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  q.isEmpty ? '(問題文なし)' : q,
                  style: Theme.of(context).textTheme.headlineSmall,
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
  const _AnswerCard({
    required this.answer,
    required this.explanation,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final onBg = cs.onSurface;

    final labelS = tt.labelMedium ?? const TextStyle(fontSize: 12);
    final titleS =
        tt.titleMedium ??
        const TextStyle(fontSize: 16, fontWeight: FontWeight.w700);

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
                style: titleS.copyWith(
                  color: onBg,
                  fontWeight: FontWeight.w800,
                ),
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
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withOpacity(0.6)),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: index > 0 ? onPrev : null,
              icon: const Icon(Icons.arrow_back_ios_new),
              tooltip: '前へ',
            ),
            const Spacer(),
            Text(
              '${index + 1} / $total',
              style: caption.copyWith(color: cs.onSurface),
            ),
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
