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
  late final List<QuizCard> sequence; // 出題順
  int index = 0;                      // 今の問題番号
  int? selected;                      // 選んだ選択肢
  bool revealed = false;              // 答え公開したか
  int correctCount = 0;               // 正答数

  QuizCard get card => sequence[index];

  @override
  void initState() {
    super.initState();
    // 各問題の選択肢をシャッフルした配列を最初に作る
    sequence = widget.deck.cards.map((c) => c.shuffled()).toList();
    // 問題の順番もランダムにしたい場合は次を有効化：
    // sequence.shuffle();
  }

  void _select(int i) {
    if (revealed) return;
    setState(() => selected = i);
  }

  void _reveal() {
    if (selected == null) return;
    setState(() => revealed = true);
  }

  void _next() {
    if (selected == card.answerIndex) correctCount++;

    if (index >= sequence.length - 1) {
      // 最終問題 → 結果画面へ
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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              card.question,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // 選択肢リスト
            ...List.generate(card.choices.length, (i) {
              final isAnswer = i == card.answerIndex;
              final isSelected = i == selected;

              Color? bg;
              if (revealed) {
                if (isAnswer) {
                  bg = Colors.green.withOpacity(0.15);
                } else if (isSelected && !isAnswer) {
                  bg = Colors.red.withOpacity(0.15);
                }
              } else if (isSelected) {
                bg = Theme.of(context).colorScheme.primary.withOpacity(0.08);
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  tileColor: bg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: revealed
                          ? (isAnswer
                              ? Colors.green
                              : (isSelected ? Colors.red : Colors.grey.shade300))
                          : (isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey.shade300),
                    ),
                  ),
                  title: Text(card.choices[i]),
                  trailing: revealed
                      ? (isAnswer
                          ? const Icon(Icons.check_circle, color: Colors.green)
                          : (isSelected ? const Icon(Icons.cancel, color: Colors.red) : null))
                      : (isSelected
                          ? const Icon(Icons.radio_button_checked)
                          : const Icon(Icons.radio_button_unchecked)),
                  onTap: () => _select(i),
                ),
              );
            }),

            const Spacer(),

            if (revealed && card.explanation != null) ...[
              Text('解説: ${card.explanation!}'),
              const SizedBox(height: 12),
            ],

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: (selected == null || revealed) ? null : _reveal,
                    child: const Text('答え合わせ'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: (selected == null)
                        ? null
                        : (revealed ? _next : _reveal),
                    child: Text(revealed
                        ? (index == sequence.length - 1 ? '結果へ' : '次へ')
                        : '答えを見る'),
                  ),
                ),
              ],
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
    );
  }
}
