// lib/models/card.dart
import 'dart:math';

class QuizCard {
  final String question; // 問題文
  final List<String> choices; // 選択肢（4択想定）
  final int answerIndex; // 正解のindex（0-based）
  final String? explanation; // 解説（任意）
  final bool isPremium; // 有料かどうか
  final List<String> unitTags; // 分野タグ（複数可）

  const QuizCard({
    required this.question,
    required this.choices,
    required this.answerIndex,
    this.explanation,
    this.isPremium = false,
    this.unitTags = const [],
  });

  List<String> get tags => unitTags;
  
  /// JSON読み込み用
  factory QuizCard.fromJson(Map<String, dynamic> json) {
    List<String> _readTags(Map<String, dynamic> j) {
      final raw = j['unitTags'] ?? j['tags'] ?? j['tag'] ?? j['tag_list'];
      if (raw is List) {
        return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      }
      if (raw is String) {
        return raw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      }
      return const <String>[];
    }

    return QuizCard(
      question: json['question'] as String,
      choices: List<String>.from(json['choices']),
      answerIndex: json['answerIndex'] as int,
      explanation: json['explanation'] as String?,
      isPremium: json['isPremium'] as bool? ?? false,
      unitTags: _readTags(json), // ← ここがポイント
    );
  }

  /// CSV読み込み用
  factory QuizCard.fromRowWithHeader(Map<String, int> idx, List<dynamic> row) {
    String _s(String key) {
      final i = idx[key];
      if (i == null) return '';
      final v = row[i];
      return (v == null) ? '' : v.toString().trim();
    }

    final c1 = _s('choice1');
    final c2 = _s('choice2');
    final c3 = _s('choice3');
    final c4 = _s('choice4');
    final ansRaw = _s('answer_index');
    final exp = idx.containsKey('explanation') ? _s('explanation') : null;

    final list = [c1, c2, c3, c4].where((e) => e.isNotEmpty).toList();

    var ans = int.tryParse(ansRaw) ?? 1;
    ans = (ans - 1).clamp(0, list.length - 1); // 1→0, 4→3 など

    return QuizCard(
      question: _s('question'),
      choices: list,
      answerIndex: ans,
      explanation: (exp != null && exp.isEmpty) ? null : exp,
    );
  }
}

/// 選択肢をシャッフルして answerIndex を再計算した新しいカードを返す
extension QuizCardShuffle on QuizCard {
  QuizCard shuffled([Random? rnd]) {
    final pairs = List.generate(choices.length, (i) => MapEntry(i, choices[i]));
    pairs.shuffle(rnd ?? Random());
    final newChoices = pairs.map((e) => e.value).toList(growable: false);
    final newAnswerIndex = pairs.indexWhere((e) => e.key == answerIndex);
    return QuizCard(
      question: question,
      choices: newChoices,
      answerIndex: newAnswerIndex,
      explanation: explanation,
      isPremium: isPremium,
      unitTags: unitTags,
    );
  }
}
