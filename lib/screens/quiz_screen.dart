import 'package:flutter/material.dart';
import '../models/deck.dart';
import '../models/card.dart';
import 'result_screen.dart';

class QuizScreen extends StatefulWidget {
  final Deck deck;
  const QuizScreen({super.key, required this.deck});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late final List<QuizCard> sequence;
  int index = 0;
  int? selected;
  bool revealed = false;
  int correctCount = 0;

  QuizCard get card => sequence[index];

  @override
  void initState() {
    super.initState();
    sequence = widget.deck.cards.map((c) => c.shuffled()).toList();
  }

  /// 選択肢をタップしたときの挙動
  void _select(int i) {
    if (revealed) return;

    // すでに同じ選択肢を選んでいる → 2回目のタップで公開
    if (selected == i) {
      _reveal();
    } else {
      setState(() => selected = i);
    }
  }

  void _reveal() {
    if (selected == null) return;
    setState(() => revealed = true);
  }

  void _next() {
    if (selected == card.answerIndex) correctCount++;
    if (index >= sequence.length - 1) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(total: sequence.length, correct: correctCount),
        ),
      );
      return;
    }
    setState(() {
      index++;
      selected = null;
      revealed = false;
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
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // 選択肢
              ...List.generate(card.choices.length, (i) => _buildChoice(i)),

              const Spacer(),

              if (revealed && card.explanation != null) ...[
                Text('解説: ${card.explanation!}'),
                const SizedBox(height: 12),
              ],

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: (selected == null && !revealed) ? null : _primaryAction,
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
      bg = Theme.of(context).colorScheme.primary.withOpacity(0.9);
    }

    final fg = (revealed && (isAnswer || isSelected)) ? Colors.white : Colors.black87;

    IconData? trail;
    if (revealed) {
      if (isAnswer) {
        trail = Icons.check_rounded;
      } else if (isSelected) {
        trail = Icons.close_rounded;
      }
    } else {
      trail = isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked;
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
            color: Colors.black.withOpacity(0.06),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _select(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (revealed && isAnswer) ? Colors.white24 : Colors.black12,
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
