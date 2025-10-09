// lib/models/quiz_session.dart
import 'dart:convert';

class QuizSession {
  final String sessionId;
  final String deckId;
  final String? unitId; // 単一ユニット出題なら入る想定。ミックス時は null でOK
  final List<String> itemIds; // 安定IDの配列（出題順のソース）
  final int currentIndex; // 次に解くインデックス（0-based）
  final Map<String, int> answers; // 将来拡張用。キーは "1","2"... など文字列にしておく
  final DateTime updatedAt;
  final bool isFinished;

  const QuizSession({
    required this.sessionId,
    required this.deckId,
    required this.unitId,
    required this.itemIds,
    required this.currentIndex,
    required this.answers,
    required this.updatedAt,
    required this.isFinished,
  });

  QuizSession copyWith({
    String? sessionId,
    String? deckId,
    String? unitId,
    List<String>? itemIds,
    int? currentIndex,
    Map<String, int>? answers,
    DateTime? updatedAt,
    bool? isFinished,
  }) {
    return QuizSession(
      sessionId: sessionId ?? this.sessionId,
      deckId: deckId ?? this.deckId,
      unitId: unitId ?? this.unitId,
      itemIds: itemIds ?? this.itemIds,
      currentIndex: currentIndex ?? this.currentIndex,
      answers: answers ?? this.answers,
      updatedAt: updatedAt ?? this.updatedAt,
      isFinished: isFinished ?? this.isFinished,
    );
  }

  // ---- JSON ----
  Map<String, dynamic> toMap() {
    return {
      'sessionId': sessionId,
      'deckId': deckId,
      'unitId': unitId,
      'itemIds': itemIds,
      'currentIndex': currentIndex,
      'answers': answers, // Map<String,int>
      'updatedAt': updatedAt.toIso8601String(),
      'isFinished': isFinished,
    };
  }

  static QuizSession fromMap(Map<String, dynamic> map) {
    return QuizSession(
      sessionId: map['sessionId'] as String,
      deckId: map['deckId'] as String,
      unitId: map['unitId'] as String?,
      itemIds: (map['itemIds'] as List).map((e) => e as String).toList(),
      currentIndex: map['currentIndex'] as int,
      answers: Map<String, int>.from(map['answers'] as Map? ?? const {}),
      updatedAt: DateTime.parse(map['updatedAt'] as String),
      isFinished: map['isFinished'] as bool? ?? false,
    );
  }

  String toJson() => jsonEncode(toMap());
  static QuizSession fromJson(String source) =>
      fromMap(jsonDecode(source) as Map<String, dynamic>);

  // 互換用：既存コードが呼んでいる encode/decode を提供
  static String encode(QuizSession s) => s.toJson();
  static QuizSession decode(String raw) => QuizSession.fromJson(raw);
}
