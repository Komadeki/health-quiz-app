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

  Widget _buildChoice(int i) {
    final isAnswer = i == card.answerIndex;
    final isSelected = i == selected;

    // 色の決定
    Color bg = Colors.white;
    if (revealed) {
      if (isAnswer) {
        bg = const Color(0xFF2e7d32); // 正解: 緑
      } else if (isSelected && !isAnswer) {
        bg = const Color(0xFFc62828); // 不正解を選択: 赤
      }
    } else if (isSelected) {
      bg = Theme.of(context).colorScheme.primary;
    }

    // テキスト色
    final bool lightText = revealed && (isAnswer || isSelected);
    final Color fg = lightText ? Colors.white : Colors.black87;

    // 右端アイコン
    IconData? trail;
    if (revealed) {
      if (isAnswer) trail = Icons.check_rounded;
      if (isSelected && !isAnswer) trail = Icons.close_rounded;
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
            spreadRadius: 0,
            offset: const Offset(0, 2),
            color: Colors.black.withOpacity(0.06),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: revealed ? null : () => _select(i),
          child: Container(
            // ← 縦を“約1.3倍”にするポイント
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 14),
            child: Row(
              children: [
                // A/B/C/D バッジ
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
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 選択肢テキスト
                Expanded(
                  child: Text(
                    card.choices[i],
                    textAlign: TextAlign.left,
                    softWrap: true,
                    style: TextStyle(
                      color: fg,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                ),
                if (trail != null) ...[
                  const SizedBox(width: 10),
                  Icon(trail, color: Colors.white, size: 22),
                ],
              ],
            ),
          ),
        ),
      ),
    );
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
            ...List.generate(card.choices.length, (i) => _buildChoice(i)),
            
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
