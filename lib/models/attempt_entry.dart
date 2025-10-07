import 'dart:convert';

class AttemptEntry {
  final String attemptId;
  final String sessionId;
  final DateTime startedAt;
  final DateTime endedAt;

  final String deckId;
  final String unitId;
  final String cardId;
  final String question;
  final List<String> choices;
  final int correctIndex; // 1..4
  final int selectedIndex; // 1..4
  final bool isCorrect;
  final int durationMs;
  final List<String> tags;
  final int questionNumber; // 1-based
  final String? note;
  final int schema;

  AttemptEntry({
    required this.attemptId,
    required this.sessionId,
    required this.startedAt,
    required this.endedAt,
    required this.deckId,
    required this.unitId,
    required this.cardId,
    required this.question,
    required this.choices,
    required this.correctIndex,
    required this.selectedIndex,
    required this.isCorrect,
    required this.durationMs,
    required this.tags,
    required this.questionNumber,
    this.note,
    this.schema = 1,
  });

  factory AttemptEntry.fromMap(Map<String, dynamic> map) => AttemptEntry(
    attemptId: map['attemptId'] as String,
    sessionId: map['sessionId'] as String,
    startedAt: DateTime.parse(map['startedAt'] as String),
    endedAt: DateTime.parse(map['endedAt'] as String),
    deckId: map['deckId'] as String,
    unitId: map['unitId'] as String,
    cardId: map['cardId'] as String,
    question: map['question'] as String,
    choices: (map['choices'] as List).map((e) => e as String).toList(),
    correctIndex: map['correctIndex'] as int,
    selectedIndex: map['selectedIndex'] as int,
    isCorrect: map['isCorrect'] as bool,
    durationMs: map['durationMs'] as int,
    tags: (map['tags'] as List).map((e) => e as String).toList(),
    questionNumber: map['questionNumber'] as int,
    note: map['note'] as String?,
    schema: (map['schema'] ?? 1) as int,
  );

  Map<String, dynamic> toMap() => {
    'attemptId': attemptId,
    'sessionId': sessionId,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'deckId': deckId,
    'unitId': unitId,
    'cardId': cardId,
    'question': question,
    'choices': choices,
    'correctIndex': correctIndex,
    'selectedIndex': selectedIndex,
    'isCorrect': isCorrect,
    'durationMs': durationMs,
    'tags': tags,
    'questionNumber': questionNumber,
    'note': note,
    'schema': schema,
  };

  String toJson() => jsonEncode(toMap());
  factory AttemptEntry.fromJson(String s) =>
      AttemptEntry.fromMap(jsonDecode(s) as Map<String, dynamic>);
}
