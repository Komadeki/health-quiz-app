import 'dart:convert';

final class DroneQuizSession {
  const DroneQuizSession({
    required this.sessionId,
    required this.bankRevision,
    required this.unitId,
    required this.questionIds,
    required this.currentIndex,
    required this.responses,
    required this.updatedAt,
  });

  factory DroneQuizSession.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != schemaVersion) {
      throw const FormatException('Unsupported session schema.');
    }
    final rawQuestionIds = json['questionIds'];
    final rawResponses = json['responses'];
    if (rawQuestionIds is! List<dynamic> || rawResponses is! Map) {
      throw const FormatException('Invalid session sequence or responses.');
    }
    final updatedAt = DateTime.tryParse('${json['updatedAt'] ?? ''}');
    if (updatedAt == null) {
      throw const FormatException('Invalid session updatedAt.');
    }
    final responses = <String, int>{};
    for (final entry in rawResponses.entries) {
      if (entry.value is! num) {
        throw const FormatException('Invalid committed response.');
      }
      responses['${entry.key}'] = (entry.value as num).toInt();
    }
    return DroneQuizSession(
      sessionId: '${json['sessionId'] ?? ''}',
      bankRevision: '${json['bankRevision'] ?? ''}',
      unitId: '${json['unitId'] ?? ''}',
      questionIds:
          rawQuestionIds.map((value) => '$value').toList(growable: false),
      currentIndex: (json['currentIndex'] as num?)?.toInt() ?? -1,
      responses: Map.unmodifiable(responses),
      updatedAt: updatedAt,
    );
  }

  static const int schemaVersion = 1;

  final String sessionId;
  final String bankRevision;
  final String unitId;
  final List<String> questionIds;
  final int currentIndex;
  final Map<String, int> responses;
  final DateTime updatedAt;

  String get currentQuestionId => questionIds[currentIndex];

  DroneQuizSession copyWith({
    int? currentIndex,
    Map<String, int>? responses,
    DateTime? updatedAt,
  }) {
    return DroneQuizSession(
      sessionId: sessionId,
      bankRevision: bankRevision,
      unitId: unitId,
      questionIds: questionIds,
      currentIndex: currentIndex ?? this.currentIndex,
      responses: Map.unmodifiable(responses ?? this.responses),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'sessionId': sessionId,
        'bankRevision': bankRevision,
        'unitId': unitId,
        'questionIds': questionIds,
        'currentIndex': currentIndex,
        'responses': responses,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  String encode() => jsonEncode(toJson());

  static DroneQuizSession? decode(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map<String, dynamic>) return null;
      return DroneQuizSession.fromJson(decoded);
    } on Object {
      return null;
    }
  }
}

final class DroneQuizResult {
  const DroneQuizResult({required this.correct, required this.total});

  final int correct;
  final int total;
}
