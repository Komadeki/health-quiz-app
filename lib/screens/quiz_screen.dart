import 'package:flutter/material.dart';
import '../models/deck.dart';
import '../models/card.dart';
import '../models/score_record.dart';
import 'result_screen.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import '../services/app_settings.dart';
import '../services/score_store.dart';
import '../services/scores_store.dart';
import '../services/deck_loader.dart';
import '../services/attempt_store.dart';
import '../models/attempt_entry.dart';

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
      final attempt = AttemptEntry(
        attemptId: _uuid.v4(),
        sessionId: _sessionId,
        startedAt: started,
        endedAt: ended,
        deckId: widget.deck.id,
        unitId: widget.deck.id,
        cardId: index.toString(),
        question: card.question,
        choices: card.choices,
        correctIndex: card.answerIndex,
        selectedIndex: selected!, // reveal済みなので非null
        isCorrect: isCorrect,
        durationMs: durationMs,
        tags: card.tags,
        questionNumber: index + 1,
        note: null,
        schema: 1,
      );
      await AttemptStore().add(attempt);
    } catch (_) {
      // 失敗しても致命傷ではないので黙って続行
    }

    if (index >= sequence.length - 1) {
      if (_savedOnce) return; // すでに保存していたら何もしない
      _savedOnce = true;
      // 成績を保存
      final result = QuizResult(
        deckId: widget.deck.id, // 'mixed' もここに入る
        total: sequence.length,
        correct: correctCount,
        timestamp: DateTime.now(),
        mode: widget.deck.id == 'mixed' ? 'mixed' : 'single',
      );

      // QuizResult作成直後に deckTitle を解決
      final decks = await DeckLoader().loadAll();
      final titleMap = {for (final d in decks) d.id: d.title};
      final deckTitle = (result.deckId == 'mixed')
          ? 'ミックス練習'
          : (titleMap[result.deckId] ?? result.deckId);

      await ScoresStore().add(result);

      final durationSec = _sw.elapsed.inSeconds;

      // 追加：TagStat マップを構築
      final Map<String, TagStat> tagStats = {};
      final allKeys = <String>{..._tagCorrect.keys, ..._tagWrong.keys};
      for (final k in allKeys) {
        tagStats[k] = TagStat(
          correct: _tagCorrect[k] ?? 0,
          wrong: _tagWrong[k] ?? 0,
        );
      }

      await ScoreStore.instance.add(
        ScoreRecord(
          id: const Uuid().v4(),
          deckId: result.deckId,
          deckTitle: deckTitle,
          score: result.correct,
          total: result.total,
          durationSec: durationSec,
          timestamp: result.timestamp.millisecondsSinceEpoch,
          tags: tagStats.isEmpty ? null : tagStats,
          selectedUnitIds: null,
        ),
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) =>
              ResultScreen(total: sequence.length, correct: correctCount),
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
          preferredSize: const Size.fromHeight(6),
          child: LinearProgressIndicator(
            value: (index + 1) / sequence.length,
            minHeight: 6,
          ),
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
}
