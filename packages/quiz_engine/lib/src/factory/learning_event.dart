enum LearningModeV1 {
  unitPractice('unit_practice'),
  randomPractice('random_practice'),
  unansweredPractice('unanswered_practice'),
  incorrectPractice('incorrect_practice'),
  retry('retry'),
  mockExam('mock_exam');

  const LearningModeV1(this.wireName);

  final String wireName;

  static LearningModeV1 fromWireName(String value) {
    return values.firstWhere(
      (mode) => mode.wireName == value,
      orElse: () => throw FormatException('Unsupported learning mode: $value'),
    );
  }
}

/// Canonical, backend-independent answer event for Factory v1.
final class LearningEventV1 {
  LearningEventV1({
    required this.appKey,
    required this.sessionId,
    required this.attemptId,
    required this.questionId,
    required this.questionVersion,
    required this.bankRevision,
    required this.unitId,
    required this.knowledgeTarget,
    required this.selectedChoice,
    required this.correct,
    required this.answeredAt,
    required this.responseDurationMs,
    required this.attemptNumber,
    required this.mode,
    required this.appVersion,
  }) {
    for (final entry in <String, String>{
      'app_key': appKey,
      'session_id': sessionId,
      'attempt_id': attemptId,
      'question_id': questionId,
      'bank_revision': bankRevision,
      'unit_id': unitId,
      'app_version': appVersion,
    }.entries) {
      if (entry.value.trim().isEmpty) {
        throw ArgumentError.value(entry.value, entry.key, 'must not be empty');
      }
    }
    if (questionVersion < 1) {
      throw ArgumentError.value(
        questionVersion,
        'questionVersion',
        'must be positive',
      );
    }
    if (selectedChoice < 0) {
      throw ArgumentError.value(
        selectedChoice,
        'selectedChoice',
        'must not be negative',
      );
    }
    if (!answeredAt.isUtc) {
      throw ArgumentError.value(answeredAt, 'answeredAt', 'must be UTC');
    }
    if (responseDurationMs < 0) {
      throw ArgumentError.value(
        responseDurationMs,
        'responseDurationMs',
        'must not be negative',
      );
    }
    if (attemptNumber < 1) {
      throw ArgumentError.value(
        attemptNumber,
        'attemptNumber',
        'must be positive',
      );
    }
  }

  factory LearningEventV1.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != schemaVersion) {
      throw const FormatException('Unsupported LearningEvent schema.');
    }
    final answeredAt = DateTime.tryParse('${json['answered_at'] ?? ''}');
    if (answeredAt == null || !answeredAt.isUtc) {
      throw const FormatException('answered_at must be an explicit UTC time.');
    }
    final knowledgeTarget = json['knowledge_target'];
    if (knowledgeTarget != null && knowledgeTarget is! String) {
      throw const FormatException('knowledge_target must be a string or null.');
    }
    return LearningEventV1(
      appKey: '${json['app_key'] ?? ''}',
      sessionId: '${json['session_id'] ?? ''}',
      attemptId: '${json['attempt_id'] ?? ''}',
      questionId: '${json['question_id'] ?? ''}',
      questionVersion: _requiredInt(json, 'question_version'),
      bankRevision: '${json['bank_revision'] ?? ''}',
      unitId: '${json['unit_id'] ?? ''}',
      knowledgeTarget: knowledgeTarget as String?,
      selectedChoice: _requiredInt(json, 'selected_choice'),
      correct: _requiredBool(json, 'correct'),
      answeredAt: answeredAt,
      responseDurationMs: _requiredInt(json, 'response_duration_ms'),
      attemptNumber: _requiredInt(json, 'attempt_number'),
      mode: LearningModeV1.fromWireName('${json['mode'] ?? ''}'),
      appVersion: '${json['app_version'] ?? ''}',
    );
  }

  static const int schemaVersion = 1;

  final String appKey;
  final String sessionId;
  final String attemptId;
  final String questionId;
  final int questionVersion;
  final String bankRevision;
  final String unitId;
  final String? knowledgeTarget;
  final int selectedChoice;
  final bool correct;
  final DateTime answeredAt;
  final int responseDurationMs;
  final int attemptNumber;
  final LearningModeV1 mode;
  final String appVersion;

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'app_key': appKey,
        'session_id': sessionId,
        'attempt_id': attemptId,
        'question_id': questionId,
        'question_version': questionVersion,
        'bank_revision': bankRevision,
        'unit_id': unitId,
        'knowledge_target': knowledgeTarget,
        'selected_choice': selectedChoice,
        'correct': correct,
        'answered_at': answeredAt.toIso8601String(),
        'response_duration_ms': responseDurationMs,
        'attempt_number': attemptNumber,
        'mode': mode.wireName,
        'app_version': appVersion,
      };
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer.');
  return value;
}

bool _requiredBool(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! bool) throw FormatException('$key must be a boolean.');
  return value;
}
