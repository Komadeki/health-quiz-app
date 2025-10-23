// lib/models/card.dart
import 'dart:math';

class QuizCard {
  final String question; // 問題文
  final List<String> choices; // 選択肢（4択想定）
  final int answerIndex; // 正解のindex（0-based）
  final String? explanation; // 解説（任意）
  final bool isPremium; // 有料かどうか
  final List<String> unitTags; // 分野タグ（複数可）
  final String? unitId; // ★追加：所属ユニットID（任意・後方互換）

  const QuizCard({
    required this.question,
    required this.choices,
    required this.answerIndex,
    this.explanation,
    this.isPremium = false,
    this.unitTags = const [],
    this.unitId, // ★追加
  });

  QuizCard copyWith({
    String? question,
    List<String>? choices,
    int? answerIndex,
    String? explanation,
    bool? isPremium,
    List<String>? unitTags,
    String? unitId,
  }) {
    return QuizCard(
      question: question ?? this.question,
      choices: choices ?? this.choices,
      answerIndex: answerIndex ?? this.answerIndex,
      explanation: explanation ?? this.explanation,
      isPremium: isPremium ?? this.isPremium,
      unitTags: unitTags ?? this.unitTags,
      unitId: unitId ?? this.unitId,
    );
  }

  List<String> get tags => unitTags;

  /// JSON読み込み用
  factory QuizCard.fromJson(Map<String, dynamic> json) {
    List<String> readTags(Map<String, dynamic> j) {
      final raw = j['unitTags'] ?? j['tags'] ?? j['tag'] ?? j['tag_list'];
      if (raw is List) {
        return raw
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      if (raw is String) {
        return raw
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const <String>[];
    }

    // ❗ final を外して通常のローカル関数に
    String? readUnitId(Map<String, dynamic> j) {
      final u = j['unitId'] ?? j['unit_id'];
      if (u == null) return null;
      final s = u.toString().trim();
      return s.isEmpty ? null : s;
    }

    return QuizCard(
      question: json['question'] as String,
      choices: List<String>.from(json['choices']),
      answerIndex: json['answerIndex'] as int,
      explanation: json['explanation'] as String?,
      isPremium: json['isPremium'] as bool? ?? false,
      unitTags: readTags(json),
      unitId: readUnitId(json), // ← ここはそのままでOK
    );
  }

  /// CSV読み込み用
  factory QuizCard.fromRowWithHeader(Map<String, int> idx, List<dynamic> row) {
    String s(String key) {
      final i = idx[key];
      if (i == null) return '';
      final v = row[i];
      return (v == null) ? '' : v.toString().trim();
    }

    final c1 = s('choice1');
    final c2 = s('choice2');
    final c3 = s('choice3');
    final c4 = s('choice4');
    final ansRaw = s('answer_index');
    final exp = idx.containsKey('explanation') ? s('explanation') : null;

    final list = [c1, c2, c3, c4].where((e) => e.isNotEmpty).toList();

    var ans = int.tryParse(ansRaw) ?? 1;
    ans = (ans - 1).clamp(0, list.length - 1); // 1→0, 4→3 など

    // ★ テンプレ列に合わせて unit_id を拾う（無ければ null）
    final uid = idx.containsKey('unit_id') ? s('unit_id') : null;

    return QuizCard(
      question: s('question'),
      choices: list,
      answerIndex: ans,
      explanation: (exp != null && exp.isEmpty) ? null : exp,
      unitId: (uid != null && uid.isEmpty) ? null : uid, // ★追加
    );
  }
}

/// 選択肢をシャッフルして answerIndex を再計算した新しいカードを返す
extension QuizCardShuffle on QuizCard {
  QuizCard shuffled({Random? rnd, bool randomize = true}) {
    final pairs = List.generate(choices.length, (i) => MapEntry(i, choices[i]));
    if (randomize) {
      pairs.shuffle(rnd ?? Random());
    }
    final newChoices = pairs.map((e) => e.value).toList(growable: false);
    final newAnswerIndex = pairs.indexWhere((e) => e.key == answerIndex);
    return QuizCard(
      question: question,
      choices: newChoices,
      answerIndex: newAnswerIndex,
      explanation: explanation,
      isPremium: isPremium,
      unitTags: unitTags,
      unitId: unitId, // ★維持
    );
  }
}
