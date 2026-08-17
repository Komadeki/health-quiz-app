// lib/models/card.dart
import 'dart:math';

class QuizCard {
  final String question;
  final List<String> choices;
  final int answerIndex;
  final String? explanation;
  final bool isPremium;
  final List<String> unitTags;
  final String? unitId;

  /// 新規資格アプリ向けの永久問題ID。既存高校保健では読み込むだけで、
  /// stableIdForOriginal() は従来方式を維持する。
  final String? stableId;
  final String? sourceTitle;
  final String? sourceSection;
  final int? difficulty;
  final int? importance;
  final String? revisionTag;

  const QuizCard({
    required this.question,
    required this.choices,
    required this.answerIndex,
    this.explanation,
    this.isPremium = false,
    this.unitTags = const [],
    this.unitId,
    this.stableId,
    this.sourceTitle,
    this.sourceSection,
    this.difficulty,
    this.importance,
    this.revisionTag,
  });

  QuizCard copyWith({
    String? question,
    List<String>? choices,
    int? answerIndex,
    String? explanation,
    bool? isPremium,
    List<String>? unitTags,
    String? unitId,
    String? stableId,
    String? sourceTitle,
    String? sourceSection,
    int? difficulty,
    int? importance,
    String? revisionTag,
  }) {
    return QuizCard(
      question: question ?? this.question,
      choices: choices ?? this.choices,
      answerIndex: answerIndex ?? this.answerIndex,
      explanation: explanation ?? this.explanation,
      isPremium: isPremium ?? this.isPremium,
      unitTags: unitTags ?? this.unitTags,
      unitId: unitId ?? this.unitId,
      stableId: stableId ?? this.stableId,
      sourceTitle: sourceTitle ?? this.sourceTitle,
      sourceSection: sourceSection ?? this.sourceSection,
      difficulty: difficulty ?? this.difficulty,
      importance: importance ?? this.importance,
      revisionTag: revisionTag ?? this.revisionTag,
    );
  }

  List<String> get tags => unitTags;

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

    String? readString(List<String> keys) {
      for (final key in keys) {
        final raw = json[key];
        if (raw == null) continue;
        final value = raw.toString().trim();
        if (value.isNotEmpty) return value;
      }
      return null;
    }

    int? readInt(List<String> keys) {
      for (final key in keys) {
        final raw = json[key];
        if (raw == null) continue;
        if (raw is int) return raw;
        final value = int.tryParse(raw.toString().trim());
        if (value != null) return value;
      }
      return null;
    }

    return QuizCard(
      question: json['question'] as String,
      choices: List<String>.from(json['choices']),
      answerIndex: json['answerIndex'] as int,
      explanation: json['explanation'] as String?,
      isPremium: json['isPremium'] as bool? ?? false,
      unitTags: readTags(json),
      unitId: readString(const ['unitId', 'unit_id']),
      stableId: readString(const [
        'stableId',
        'stable_id',
        'questionId',
        'question_id',
      ]),
      sourceTitle: readString(const ['sourceTitle', 'source_title']),
      sourceSection: readString(const ['sourceSection', 'source_section']),
      difficulty: readInt(const ['difficulty']),
      importance: readInt(const ['importance']),
      revisionTag: readString(const ['revisionTag', 'revision_tag']),
    );
  }

  factory QuizCard.fromRowWithHeader(Map<String, int> idx, List<dynamic> row) {
    String s(String key) {
      final i = idx[key];
      if (i == null || i < 0 || i >= row.length) return '';
      final v = row[i];
      return v == null ? '' : v.toString().trim();
    }

    String first(List<String> keys) {
      for (final key in keys) {
        final value = s(key);
        if (value.isNotEmpty) return value;
      }
      return '';
    }

    int? optionalInt(String key) {
      final value = s(key);
      return value.isEmpty ? null : int.tryParse(value);
    }

    final list = [s('choice1'), s('choice2'), s('choice3'), s('choice4')]
        .where((e) => e.isNotEmpty)
        .toList();

    var ans = int.tryParse(s('answer_index')) ?? 1;
    ans = (ans - 1).clamp(0, list.length - 1);

    final exp = s('explanation');
    final uid = first(const ['unit_id', 'unitId']);
    final sid = first(const [
      'stable_id',
      'stableId',
      'question_id',
      'questionId',
    ]);
    final sourceTitle = first(const ['source_title', 'sourceTitle']);
    final sourceSection = first(const ['source_section', 'sourceSection']);
    final revisionTag = first(const ['revision_tag', 'revisionTag']);

    return QuizCard(
      question: s('question'),
      choices: list,
      answerIndex: ans,
      explanation: exp.isEmpty ? null : exp,
      unitId: uid.isEmpty ? null : uid,
      stableId: sid.isEmpty ? null : sid,
      sourceTitle: sourceTitle.isEmpty ? null : sourceTitle,
      sourceSection: sourceSection.isEmpty ? null : sourceSection,
      difficulty: optionalInt('difficulty'),
      importance: optionalInt('importance'),
      revisionTag: revisionTag.isEmpty ? null : revisionTag,
    );
  }
}

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
      unitId: unitId,
      stableId: stableId,
      sourceTitle: sourceTitle,
      sourceSection: sourceSection,
      difficulty: difficulty,
      importance: importance,
      revisionTag: revisionTag,
    );
  }
}
