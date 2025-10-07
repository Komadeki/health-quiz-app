import 'dart:convert';

class AttemptEntry {
  final String? attemptId;      // ★重複判定・インポート用（任意）
  final String sessionId;       // 1回のクイズ実施単位のID
  final int questionNumber;     // そのセッション内での通し番号 (1-based)
  final String unitId;          // 出題ユニットID
  final String cardId;          // カードID
  final String question;        // 問題文（保存時点）
  final int selectedIndex;      // ユーザーの選択（1〜4）
  final int correctIndex;       // 正答（1〜4）
  final bool isCorrect;         // 正誤
  final int durationMs;         // その問題に要した時間
  final DateTime timestamp;     // 保存時刻

  const AttemptEntry({
    this.attemptId,             // ★任意
    required this.sessionId,
    required this.questionNumber,
    required this.unitId,
    required this.cardId,
    required this.question,
    required this.selectedIndex,
    required this.correctIndex,
    required this.isCorrect,
    required this.durationMs,
    required this.timestamp,
  });

  AttemptEntry copyWith({
    String? attemptId,
    String? sessionId,
    int? questionNumber,
    String? unitId,
    String? cardId,
    String? question,
    int? selectedIndex,
    int? correctIndex,
    bool? isCorrect,
    int? durationMs,
    DateTime? timestamp,
  }) {
    return AttemptEntry(
      attemptId: attemptId ?? this.attemptId,
      sessionId: sessionId ?? this.sessionId,
      questionNumber: questionNumber ?? this.questionNumber,
      unitId: unitId ?? this.unitId,
      cardId: cardId ?? this.cardId,
      question: question ?? this.question,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      correctIndex: correctIndex ?? this.correctIndex,
      isCorrect: isCorrect ?? this.isCorrect,
      durationMs: durationMs ?? this.durationMs,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  Map<String, dynamic> toMap() => {
        'attemptId': attemptId, // ★null 可
        'sessionId': sessionId,
        'questionNumber': questionNumber,
        'unitId': unitId,
        'cardId': cardId,
        'question': question,
        'selectedIndex': selectedIndex,
        'correctIndex': correctIndex,
        'isCorrect': isCorrect,
        'durationMs': durationMs,
        'timestamp': timestamp.toIso8601String(),
      };

  factory AttemptEntry.fromMap(Map<String, dynamic> map) {
    return AttemptEntry(
      attemptId: map['attemptId'] as String?, // ★無ければnull
      sessionId: map['sessionId'] as String,
      questionNumber: (map['questionNumber'] as num).toInt(),
      unitId: map['unitId'] as String,
      cardId: map['cardId'] as String,
      question: map['question'] as String,
      selectedIndex: (map['selectedIndex'] as num).toInt(),
      correctIndex: (map['correctIndex'] as num).toInt(),
      isCorrect: map['isCorrect'] as bool,
      durationMs: (map['durationMs'] as num).toInt(),
      timestamp: DateTime.parse(map['timestamp'] as String),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory AttemptEntry.fromJson(String source) =>
      AttemptEntry.fromMap(jsonDecode(source) as Map<String, dynamic>);
}
