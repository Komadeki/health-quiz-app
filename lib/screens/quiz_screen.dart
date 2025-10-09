// lib/screens/quiz_screen.dart
import 'package:flutter/material.dart';
import '../models/deck.dart';
import '../models/card.dart';
import '../models/score_record.dart';
import 'result_screen.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import '../services/app_settings.dart';
import '../services/deck_loader.dart';
import '../services/attempt_store.dart';
import '../models/attempt_entry.dart';
import '../utils/logger.dart';

// ★ セッション保存/再開
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'dart:convert';
import '../models/quiz_session.dart';
import '../data/quiz_session_local_repository.dart';

class QuizScreen extends StatefulWidget {
  final Deck deck;
  final List<QuizCard>? overrideCards; // UnitSelect などからの限定セット
  final QuizSession? resumeSession;    // 再開用

  const QuizScreen({
    super.key,
    required this.deck,
    this.overrideCards,
    this.resumeSession,
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  // ===== ランタイム状態 =====
  late List<QuizCard> sequence; // 出題順に並んだカード（選択肢は各カード内でシャッフル済み）
  late List<String> _stableOrder; // ★ 出題順に対応する「安定ID」列（保存・復元の唯一の根拠）
  late String _sessionId;

  int index = 0;
  int? selected;
  bool revealed = false;
  int correctCount = 0;

  final Stopwatch _sw = Stopwatch()..start();
  bool _savedOnce = false;
  DateTime? _qStart;

  // 解析用
  final Map<String, int> _tagCorrect = {};
  final Map<String, int> _tagWrong = {};
  final Map<String, int> _unitCount = {};

  // 復元用：安定ID → 元カード
  late Map<String, QuizCard> _id2card;

  // 画面安全化
  bool _initReady = false;   // 初期化が完了したときだけ build する
  bool _abortAndPop = false; // 復元不能時の安全フラグ

  // ===== ユーティリティ =====
  // 安定ID（問題文＋元の選択肢順から計算）※シャッフル後には使わない
  String _stableIdForOriginal(QuizCard c) {
    final raw = '${c.question}\n${c.choices.join('|')}';
    return crypto.md5.convert(utf8.encode(raw)).toString();
  }

  // QuizCardにunitIdが未実装でも安全に取得
  String _unitIdOf(QuizCard c) {
    try {
      final dyn = c as dynamic;
      final v = dyn.unitId;
      if (v is String && v.isNotEmpty) return v;
    } catch (_) {}
    return widget.deck.id;
  }

  void _bumpTags(Iterable<String> tags, bool isCorrect) {
    for (final t in tags) {
      if (isCorrect) {
        _tagCorrect[t] = (_tagCorrect[t] ?? 0) + 1;
      } else {
        _tagWrong[t] = (_tagWrong[t] ?? 0) + 1;
      }
    }
  }

  QuizCard get card => sequence[index];

  // ===== ライフサイクル =====
  @override
  void initState() {
    super.initState();

    // 1) ベース問題集合（UnitSelect 等から来ていれば限定セット）
    final base = (widget.overrideCards ?? widget.deck.cards).toList();

    // 2) 安定IDの逆引き（必ず「元の並び・元の選択肢」で計算する）
    _id2card = {for (final c in base) _stableIdForOriginal(c): c};

    final settings = Provider.of<AppSettings>(context, listen: false);

    if (widget.resumeSession == null) {
      // ───────── 新規セッション ─────────
      // a) 出題順をまず決める（安定IDと対で保持）
      final items = [
        for (final c in base) (_stableIdForOriginal(c), c),
      ];
      if (settings.randomize) {
        items.shuffle(); // ★ 出題順のシャッフルはここだけ
      }

      // b) 画面で使うカード配列を作成（選択肢シャッフルはカード内部で実施）
      sequence = [
        for (final it in items) it.$2.shuffled(),
      ];

      // c) 「実際の出題順」に対応する安定ID列を保存
      _stableOrder = [for (final it in items) it.$1];

      // d) セッションID・開始時刻
      _sessionId = const Uuid().v4();
      _qStart = DateTime.now();

      // e) ユニット内訳
      _unitCount.clear();
      for (final qc in sequence) {
        final uid = _unitIdOf(qc);
        _unitCount[uid] = (_unitCount[uid] ?? 0) + 1;
      }

      // f) 初期セーブ（⚠️ _stableOrder は「出題順」です）
      _saveSession(
        QuizSession(
          sessionId: _sessionId,
          deckId: widget.deck.id,
          unitId: null,
          itemIds: _stableOrder,
          currentIndex: 0,
          answers: const {},
          updatedAt: DateTime.now(),
          isFinished: false,
        ),
      );

      _initReady = true;
    } else {
      // ───────── 再開セッション ─────────
      final s = widget.resumeSession!;
      _sessionId = s.sessionId;

      // a) 失われた問題チェック（データ差し替え等）
      final missing = s.itemIds.where((id) => !_id2card.containsKey(id)).toList();
      if (missing.isNotEmpty) {
        AppLog.d('[RESUME][MISSING] deck=${s.deckId} '
            'missing=${missing.length} ids=${missing.take(5).toList()}...');
        _abortAndPop = true;
        _initReady = false;

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('前回の出題を復元できませんでした（問題セットが更新された可能性）'),
            ),
          );
          Navigator.pop(context);
        });
        return;
      }

      // b) 「保存されていた出題順」＝これを唯一の根拠として復元
      _stableOrder = List<String>.from(s.itemIds);

      // c) 復元（選択肢は現状仕様どおり再ランダム）
      sequence = [
        for (final id in _stableOrder) _id2card[id]!.shuffled(),
      ];

      // d) インデックス補正
      index = s.currentIndex.clamp(0, sequence.length - 1);
      correctCount = 0;
      _qStart = DateTime.now();

      // e) ユニット内訳
      _unitCount.clear();
      for (final qc in sequence) {
        final uid = _unitIdOf(qc);
        _unitCount[uid] = (_unitCount[uid] ?? 0) + 1;
      }

      _initReady = true;
    }
  }

  // ===== セッション保存ユーティリティ =====
  Future<void> _saveSession(QuizSession s) async {
    final prefs = await SharedPreferences.getInstance();
    await QuizSessionLocalRepository(prefs).save(s);
    AppLog.d('[RESUME] saved: deck=${s.deckId} index=${s.currentIndex} '
        'len=${s.itemIds.length} finished=${s.isFinished}');
  }

  Future<void> _markFinishedAndClear(QuizSession s) async {
    final prefs = await SharedPreferences.getInstance();
    final repo = QuizSessionLocalRepository(prefs);
    await repo.save(s.copyWith(isFinished: true));
    await repo.clear();
  }

  // ===== 選択・遷移 =====
  void _select(int i) {
    if (revealed) return;
    final app = Provider.of<AppSettings>(context, listen: false);
    final tapMode = app.tapMode;

    if (tapMode == TapAdvanceMode.oneTap) {
      setState(() => selected = i);
      _reveal();
    } else {
      if (selected == i) {
        _reveal();
      } else {
        setState(() => selected = i);
      }
    }
  }

  void _reveal() {
    if (selected == null) return;
    setState(() => revealed = true);
  }

  void _next() async {
    if (selected == card.answerIndex) correctCount++;
    final isCorrect = selected == card.answerIndex;
    _bumpTags(card.tags, isCorrect);

    // 1) 問題単位の Attempt 保存
    try {
      final ended = DateTime.now();
      final started = _qStart ?? ended;
      final durationMs = ended.difference(started).inMilliseconds;
      final attempt = AttemptEntry(
        attemptId: const Uuid().v4(),
        sessionId: _sessionId,
        questionNumber: index + 1,            // 1-based
        unitId: _unitIdOf(card),
        cardId: index.toString(),             // QuizCard に id があるなら差し替え可
        question: card.question,
        selectedIndex: (selected ?? 0) + 1,   // 1-based
        correctIndex: (card.answerIndex) + 1, // 1-based
        isCorrect: isCorrect,
        durationMs: durationMs,
        timestamp: ended,
      );
      await AttemptStore().add(attempt);
      AppLog.d('[ATTEMPT] ${attempt.sessionId} Q${attempt.questionNumber} '
          '${attempt.isCorrect ? "○" : "×"} ${attempt.durationMs}ms');
    } catch (_) {}

    // 2) オートセーブ（⚠️ 必ず _stableOrder を使う）
    try {
      await _saveSession(
        QuizSession(
          sessionId: _sessionId,
          deckId: widget.deck.id,
          unitId: null,
          itemIds: _stableOrder,        // ← ここが重要：常に出題順の安定ID列
          currentIndex: index + 1,      // 次に解く位置
          answers: const {},
          updatedAt: DateTime.now(),
          isFinished: false,
        ),
      );
    } catch (_) {}

    // 3) 最終問題ならスコア保存→クリア→結果へ
    if (index >= sequence.length - 1) {
      if (_savedOnce) return;
      _savedOnce = true;

      final deckId = widget.deck.id;
      final total = sequence.length;
      final correct = correctCount;
      final timestamp = DateTime.now();
      final durationSec = _sw.elapsed.inSeconds;

      // デッキ/ユニットタイトル解決
      final decks = await DeckLoader().loadAll();
      final Map<String, String> deckTitleMap = {};
      final Map<String, String> unitTitleMap = {};
      for (final d in decks) {
        deckTitleMap[d.id.trim()] =
            d.title.trim().isNotEmpty ? d.title.trim() : d.id.trim();
        for (final u in (d.units ?? const [])) {
          final uid = u.id.trim();
          final ut = u.title.trim();
          if (uid.isNotEmpty) unitTitleMap[uid] = ut.isNotEmpty ? ut : uid;
        }
      }
      final deckTitle = deckTitleMap[deckId] ?? widget.deck.title;

      // タグ統計
      final Map<String, TagStat> tagStats = {};
      final allKeys = <String>{..._tagCorrect.keys, ..._tagWrong.keys};
      for (final k in allKeys) {
        tagStats[k] = TagStat(
          correct: _tagCorrect[k] ?? 0,
          wrong: _tagWrong[k] ?? 0,
        );
      }

      // スコア保存
      try {
        await AttemptStore().addScore(
          ScoreRecord(
            id: const Uuid().v4(),
            deckId: deckId,
            deckTitle: deckTitle,
            score: correct,
            total: total,
            durationSec: durationSec,
            timestamp: timestamp.millisecondsSinceEpoch,
            tags: tagStats.isEmpty ? null : tagStats,
            selectedUnitIds: null,
            sessionId: _sessionId,
            unitBreakdown: Map<String, int>.from(_unitCount),
          ),
        );
      } catch (_) {}

      // セッション終了保存→クリア
      try {
        await _markFinishedAndClear(
          QuizSession(
            sessionId: _sessionId,
            deckId: widget.deck.id,
            unitId: null,
            itemIds: _stableOrder,
            currentIndex: sequence.length,
            answers: const {},
            updatedAt: DateTime.now(),
            isFinished: true,
          ),
        );
      } catch (_) {}

      if (!mounted) return;
      await _onQuizEndDebugLog();
      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            total: total,
            correct: correct,
            sessionId: _sessionId,
            unitBreakdown: Map<String, int>.from(_unitCount),
            deckId: deckId,
            deckTitle: deckTitle,
            durationSec: durationSec,
            unitTitleMap: unitTitleMap,
          ),
        ),
      );
      return;
    }

    // 4) 次の問題へ
    setState(() {
      index++;
      selected = null;
      revealed = false;
      _qStart = DateTime.now();
    });
  }

  void _primaryAction() => revealed ? _next() : _reveal();

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    // 初期化前/中断時の安全ガード
    if (!_initReady || _abortAndPop) {
      return Scaffold(
        appBar: AppBar(title: const Text('読み込み中…')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final isCorrect = revealed && selected == card.answerIndex;

    return Scaffold(
      appBar: AppBar(
        title: Text('問題 ${index + 1}/${sequence.length}'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(6),
          child: _ProgressBar(),
        ),
      ),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (revealed) _next();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(
                card.question,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ...List.generate(card.choices.length, (i) => _buildChoice(i)),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                reverseDuration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: (revealed && (card.explanation ?? '').trim().isNotEmpty)
                    ? _ExplanationCard(index: index, text: card.explanation!)
                    : const SizedBox.shrink(),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      (selected == null && !revealed) ? null : _primaryAction,
                  child: Text(
                    revealed
                        ? (index == sequence.length - 1 ? '結果へ' : '次へ')
                        : '答えを見る',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (revealed)
                Text(
                  isCorrect ? '正解！' : '不正解…',
                  style: TextStyle(
                    color: isCorrect ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChoice(int i) {
    final isAnswer = i == card.answerIndex;
    final isSelected = i == selected;

    Color bg = Colors.white;
    if (revealed) {
      if (isAnswer) {
        bg = Colors.green;
      } else if (isSelected) {
        bg = Colors.red;
      } else {
        bg = Colors.grey.shade300;
      }
    } else if (isSelected) {
      bg = Theme.of(context).colorScheme.primary.withValues(alpha: 0.9);
    }
    final fg =
        (revealed && (isAnswer || isSelected)) ? Colors.white : Colors.black87;

    IconData? trail;
    if (revealed) {
      if (isAnswer) {
        trail = Icons.check_rounded;
      } else if (isSelected) {
        trail = Icons.close_rounded;
      }
    } else {
      trail = isSelected
          ? Icons.radio_button_checked
          : Icons.radio_button_unchecked;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            blurRadius: 6,
            offset: const Offset(0, 2),
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => revealed ? _next() : _select(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (revealed && isAnswer)
                        ? Colors.white24
                        : Colors.black12,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    String.fromCharCode('A'.codeUnitAt(0) + i),
                    style: TextStyle(color: fg, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    card.choices[i],
                    softWrap: true,
                    style: TextStyle(
                      color: fg,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
                if (trail != null) ...[
                  const SizedBox(width: 10),
                  Icon(trail, color: fg, size: 22),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 直近Attemptのデバッグログ
  Future<void> _onQuizEndDebugLog() async {
    try {
      final list = await AttemptStore().recent(limit: 5);
      for (final a in list) {
        AppLog.d('[ATTEMPT] ${a.sessionId} Q${a.questionNumber} '
            '${a.isCorrect ? "○" : "×"} ${a.durationMs}ms');
      }
    } catch (_) {}
  }
}

// 解説カード
class _ExplanationCard extends StatelessWidget {
  final int index;
  final String text;
  const _ExplanationCard({required this.index, required this.text});

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey('exp-$index'),
      elevation: 1.5,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.4),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 20),
                const SizedBox(width: 8),
                Text(
                  '解説',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Text(
              text.trim(),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(fontSize: 18, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// 進捗バー
class _ProgressBar extends StatelessWidget implements PreferredSizeWidget {
  const _ProgressBar();
  @override
  Size get preferredSize => const Size.fromHeight(6);
  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_QuizScreenState>();
    final value = (state == null ||
            !state._initReady ||
            state._abortAndPop ||
            state.sequence.isEmpty)
        ? 0.0
        : (state.index + 1) / state.sequence.length;
    return LinearProgressIndicator(value: value, minHeight: 6);
  }
}
