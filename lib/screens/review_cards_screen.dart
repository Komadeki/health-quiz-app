// lib/screens/review_cards_screen.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

import '../models/card.dart';
import '../services/attempt_store.dart';
import '../services/deck_loader.dart';
import '../utils/logger.dart';

class ReviewCardsScreen extends StatefulWidget {
  const ReviewCardsScreen({super.key});
  @override
  State<ReviewCardsScreen> createState() => _ReviewCardsScreenState();
}

enum MenuAction { sortOriginal, sortRandom, top10, top20, top30, top50 }

class _ReviewCardsScreenState extends State<ReviewCardsScreen> {
  bool _showAnswer = false;
  void _toggle() {
    setState(() => _showAnswer = !_showAnswer);
    debugPrint('[REVIEW] toggle -> $_showAnswer (idx=$_index)');
  }

  final _rng = Random();

  // 表示用
  List<QuizCard> _base = [];
  List<QuizCard> _cards = [];
  int _index = 0;
  bool _loading = true;

  // タイトルの逆引き（並び替えに強い）
  final Map<QuizCard, String> _deckTitleCache = {};
  final Map<QuizCard, String> _unitTitleCache = {};

  // 解決インデックス
  final Map<String, QuizCard> _byStableId = {};
  final Map<String, QuizCard> _byInternalId = {};
  final Map<String, QuizCard> _byFull = {};
  final Map<String, List<QuizCard>> _byHead = {};

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

  String _head(String s, [int n = 22]) {
    final t = _norm(s);
    return t.length > n ? t.substring(0, n) : t;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMany());
  }

  String _visible(String s) =>
      s.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '').trim();

  Future<void> _loadMany() async {
    try {
      final attempts = AttemptStore();
      final loader = DeckLoader();

      // 誤答ゼロなら戻る
      final wrongQuestions = await attempts.getAllWrongCardIds();
      if (wrongQuestions.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('復習対象がありません'), duration: Duration(seconds: 2)),
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

          // インデックス
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
        _deckTitleCache
          ..clear()
          ..addAll(titleOfDeck);
        _unitTitleCache
          ..clear()
          ..addAll(titleOfUnit);
        _index = 0;
        _showAnswer = false;
        _loading = false;
      });
      AppLog.d('[REVIEW] prepared cards=${_cards.length}');
    } catch (e, st) {
      if (!mounted) return;
      setState(() => _loading = false);
      AppLog.e('[REVIEW] load failed: $e\n$st');
    }
  }

  // 右上メニュー
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
          case MenuAction.top10:
            _rebuildTopN(10);
            break;
          case MenuAction.top20:
            _rebuildTopN(20);
            break;
          case MenuAction.top30:
            _rebuildTopN(30);
            break;
          case MenuAction.top50:
            _rebuildTopN(50);
            break;
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: MenuAction.sortOriginal, child: Text('元の順')),
        PopupMenuItem(value: MenuAction.sortRandom, child: Text('ランダム')),
        PopupMenuDivider(),
        PopupMenuItem(value: MenuAction.top10, child: Text('上位10（誤答頻度）')),
        PopupMenuItem(value: MenuAction.top20, child: Text('上位20（誤答頻度）')),
        PopupMenuItem(value: MenuAction.top30, child: Text('上位30（誤答頻度）')),
        PopupMenuItem(value: MenuAction.top50, child: Text('上位50（誤答頻度）')),
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
    });
  }

  Future<void> _rebuildTopN(int n) async {
    try {
      final attempts = AttemptStore();
      Map<String, int> freq = {};
      try {
        // 存在すれば使う（PR②想定API）
        final dynamic fn = (attempts as dynamic).getWrongFrequencyMap;
        if (fn is Function) {
          final dynamic m = await Function.apply(fn, const []);
          if (m is Map<String, int>) {
            freq = m;
          } else if (m is Map) {
            m.forEach((k, v) {
              if (k is String && v is num) freq[k] = v.toInt();
            });
          }
        }
      } catch (_) {}
      if (freq.isEmpty) {
        // フォールバック：questionテキストで集計
        final qs = await attempts.getAllWrongCardIds();
        for (final raw in qs) {
          final k = _norm(raw);
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
        final normed = _norm(key);
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
    } catch (e, st) {
      AppLog.e('[REVIEW] rebuildTopN failed: $e\n$st');
    }
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
    final hint = 'タップで答え表示 / スワイプで移動';

    return Scaffold(
      appBar: AppBar(
        title: const Text('見直しモード'),
        actions: [_buildMenu(context)],
      ),
      // 1) 背景は QuizScreen と同じトーンに
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
              // ヘッダ（落ち着いたトーン）
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
              const SizedBox(height: 12),

              // 2) 質問カード：白 + 軽い影 + 薄い枠 + 角丸16、内側余白20
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

              // 3) 答えカード（トグル時のみ）：同質感
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
          // 5) 下部バーも白ベース＋薄い境界線
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
