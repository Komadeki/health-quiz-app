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

class QuizScreen extends StatefulWidget {
  final Deck deck;
  final List<QuizCard>? overrideCards; // ← 追加

  const QuizScreen({
    super.key,
    required this.deck,
    this.overrideCards, // ← 追加
  });

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late final List<QuizCard> sequence;
  int index = 0;
  int? selected;
  bool revealed = false;
  int correctCount = 0;

  final Stopwatch _sw = Stopwatch()..start();
  bool _savedOnce = false; // 結果保存の多重防止
  final _uuid = const Uuid();
  late final String _sessionId;
  DateTime? _qStart; // この問題の開始時刻（表示タイミング）

  // 追加：タグ別集計
  final Map<String, int> _tagCorrect = {};
  final Map<String, int> _tagWrong = {};

  // 追加：ユニット別集計（出題内訳）
  final Map<String, int> _unitCount = {};

  void _bumpTags(Iterable<String> tags, bool isCorrect) {
    for (final t in tags) {
      if (isCorrect) {
        _tagCorrect[t] = (_tagCorrect[t] ?? 0) + 1;
      } else {
        _tagWrong[t] = (_tagWrong[t] ?? 0) + 1;
      }
    }
  }

  // QuizCardにunitIdが未実装でもビルドが通る安全な取得ヘルパー
  String _unitIdOf(QuizCard c) {
    try {
      final dyn = c as dynamic;
      final v = dyn.unitId;
      if (v is String && v.isNotEmpty) return v;
    } catch (_) {
      // 未実装/型不一致は握りつぶし
    }
    // フォールバック：deck.id（単一ユニット出題時も成立）
    return widget.deck.id;
  }

  QuizCard get card => sequence[index];

  @override
  void initState() {
    super.initState();
    // UnitSelectScreen から渡されてきたカード束があればそちらを使用
    // （toListで可変化しておく）
    final base = (widget.overrideCards ?? widget.deck.cards).toList();
    // 各カードの選択肢シャッフルは従来通り
    sequence = base.map((c) => c.shuffled()).toList();

    // 出題順ランダム化の一本化：設定がONならここだけで shuffle
    final settings = Provider.of<AppSettings>(context, listen: false);
    if (settings.randomize) {
      sequence.shuffle();
    }

    // セッションID生成＆最初の問題の開始時刻を記録
    _sessionId = _uuid.v4();
    _qStart = DateTime.now();

    // ★ユニット別件数の事前集計（出題が確定したタイミングで一括）
    _unitCount.clear();
    for (final qc in sequence) {
      final uid = _unitIdOf(qc);
      _unitCount[uid] = (_unitCount[uid] ?? 0) + 1;
    }
  }

  /// 選択肢をタップしたときの挙動
  void _select(int i) {
    if (revealed) return;

    final app = Provider.of<AppSettings>(context, listen: false);
    final tapMode = app.tapMode;

    if (tapMode == TapAdvanceMode.oneTap) {
      // 1タップモード：即確定
      setState(() => selected = i);
      _reveal();
    } else {
      // 2タップモード：同じ選択肢を2回で確定
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

    // この問題のタグを集計
    final isCorrect = (selected == card.answerIndex);
    final tagsThisQuestion = card.tags; // List<String>
    _bumpTags(tagsThisQuestion, isCorrect);

    // --- AttemptEntry 保存（この問題の確定時点） ---
    try {
      final ended = DateTime.now();
      final started = _qStart ?? ended;
      final durationMs = ended.difference(started).inMilliseconds;
      // ★ 保存する selectedIndex / correctIndex は 1–4 に統一
      final attempt = AttemptEntry(
        attemptId: _uuid.v4(),          // AttemptStore 側で未設定時も採番されるが、ここで付与
        sessionId: _sessionId,
        questionNumber: index + 1,      // 1-based
        unitId: _unitIdOf(card),        // ← カードから安全に取得（フォールバックは deck.id）
        cardId: index.toString(),       // QuizCard に id があるなら置き換え可
        question: card.question,
        selectedIndex: (selected ?? 0) + 1, // ← 1-based で保存
        correctIndex: (card.answerIndex) + 1, // ← 1-based で保存
        isCorrect: isCorrect,           // 判定は 0-based 比較でOK
        durationMs: durationMs,
        timestamp: ended,
      );
      await AttemptStore().add(attempt);
      AppLog.d('[ATTEMPT] ${attempt.sessionId} Q${attempt.questionNumber} '
          '${attempt.isCorrect ? "○" : "×"} ${attempt.durationMs}ms');
    } catch (_) {
      // 失敗しても致命傷ではないので黙って続行
    }

    if (index >= sequence.length - 1) {
      if (_savedOnce) return; // すでに保存していたら何もしない
      _savedOnce = true;

      // --- 成績サマリ情報をローカル変数で保持（QuizResultは使わない） ---
      final deckId = widget.deck.id;            // 'mixed' もここに入る
      final total = sequence.length;
      final correct = correctCount;
      final timestamp = DateTime.now();
      final durationSec = _sw.elapsed.inSeconds;

      // デッキタイトル解決
      final decks = await DeckLoader().loadAll();

      // 1パスで Deck → Title と Unit → Title を同時に構築
      final Map<String, String> deckTitleMap = {};
      final Map<String, String> unitTitleMap = {};

      for (final d in decks) {
        // デッキ
        final did = d.id.trim();
        final dtitle = d.title.trim();
        if (did.isNotEmpty) {
          deckTitleMap[did] = dtitle.isNotEmpty ? dtitle : did; // タイトル未設定ならIDをフォールバック
        }

        // ユニット
        for (final u in (d.units ?? const [])) {
          final uid = u.id.trim();
          final utitle = u.title.trim();
          if (uid.isNotEmpty) {
            // タイトルが空なら uid をフォールバック
            unitTitleMap[uid] = utitle.isNotEmpty ? utitle : uid;
          }
        }
      }

      // デッキ表示名（'mixed' は特別扱い）
      final String fallbackDeckTitle =
          (widget.deck.title.isNotEmpty) ? widget.deck.title : deckId;
      final String deckTitle = (deckId == 'mixed')
          ? 'ミックス練習'
          : (deckTitleMap[deckId] ?? fallbackDeckTitle);

      // 以降：unitTitleMap は ResultScreen などにそのまま渡せます

      // TagStat マップを構築（現状ロジックはそのまま）
      final Map<String, TagStat> tagStats = {};
      final allKeys = <String>{..._tagCorrect.keys, ..._tagWrong.keys};
      for (final k in allKeys) {
        tagStats[k] = TagStat(
          correct: _tagCorrect[k] ?? 0,
          wrong: _tagWrong[k] ?? 0,
        );
      }

      // ★ AttemptStore に ScoreRecord を保存（unitBreakdown を含める）
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
      } catch (_) {
        // 保存失敗は致命ではないので握りつぶし
      }

      if (!mounted) return;
      await _onQuizEndDebugLog(); // 直近5件の確認ログ
      if (!mounted) return; // await後も安全チェック

      // Navigatorを事前に確保して安全に使う
      final nav = Navigator.of(context);

      // 結果画面へ（deckId/deckTitle/durationSec を渡す）
      nav.pushReplacement(
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

    setState(() {
      index++;
      selected = null;
      revealed = false;
      _qStart = DateTime.now(); // 次の問題の開始時刻
    });
  }

  void _primaryAction() {
    if (revealed) {
      _next();
    } else {
      _reveal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCorrect = revealed && selected == card.answerIndex;

    return Scaffold(
      appBar: AppBar(
        title: Text('問題 ${index + 1}/${sequence.length}'),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(6),
          child: _ProgressBar(),
        ),
      ),
      // 公開済みなら画面どこをタップしても次へ
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
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // 選択肢
              ...List.generate(card.choices.length, (i) => _buildChoice(i)),

              // 解説カード（選択肢の直下）
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                reverseDuration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  final slide = Tween<Offset>(
                    begin: const Offset(0, 0.06),
                    end: Offset.zero,
                  ).animate(animation);
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
                child: (revealed && (card.explanation ?? '').trim().isNotEmpty)
                    ? Card(
                        key: ValueKey('exp-$index'),
                        elevation: 1.5,
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
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
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                14,
                                16,
                                16,
                              ),
                              child: Text(
                                (card.explanation ?? '').trim(),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontSize: 18, height: 1.5),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey('exp-empty')),
              ),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (selected == null && !revealed)
                      ? null
                      : _primaryAction,
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

    final fg = (revealed && (isAnswer || isSelected))
        ? Colors.white
        : Colors.black87;

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
      curve: Curves.easeOut,
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
          onTap: () {
            if (revealed) {
              _next();
            } else {
              _select(i);
            }
          },
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

  /// クイズ終了時に直近の Attempt を確認ログ出力
  Future<void> _onQuizEndDebugLog() async {
    try {
      final list = await AttemptStore().recent(limit: 5);
      for (final a in list) {
        AppLog.d('[ATTEMPT] ${a.sessionId} Q${a.questionNumber} '
            '${a.isCorrect ? "○" : "×"} ${a.durationMs}ms');
      }
    } catch (_) {
      // ログ用途なので握りつぶしでOK
    }
  }
}

// 進捗バーを切り出してリビルド負荷軽減（任意）
class _ProgressBar extends StatelessWidget implements PreferredSizeWidget {
  const _ProgressBar();

  @override
  Size get preferredSize => const Size.fromHeight(6);

  @override
  Widget build(BuildContext context) {
    final state = context.findAncestorStateOfType<_QuizScreenState>();
    final value = (state == null || state.sequence.isEmpty)
        ? 0.0
        : (state.index + 1) / state.sequence.length;
    return LinearProgressIndicator(
      value: value,
      minHeight: 6,
    );
  }
}
