import 'learning_event.dart';

final class SessionResponseV1 {
  SessionResponseV1({
    required this.choiceIndex,
    required this.attemptId,
    required this.answeredAt,
  }) {
    if (choiceIndex < 0) {
      throw ArgumentError.value(choiceIndex, 'choiceIndex');
    }
    if (attemptId.trim().isEmpty) {
      throw ArgumentError.value(attemptId, 'attemptId');
    }
    if (!answeredAt.isUtc) {
      throw ArgumentError.value(answeredAt, 'answeredAt', 'must be UTC');
    }
  }

  factory SessionResponseV1.fromJson(Map<String, dynamic> json) {
    final answeredAt = DateTime.tryParse('${json['answered_at'] ?? ''}');
    if (answeredAt == null || !answeredAt.isUtc) {
      throw const FormatException('Invalid response answered_at.');
    }
    final choiceIndex = json['choice_index'];
    if (choiceIndex is! int) {
      throw const FormatException('Invalid response choice_index.');
    }
    return SessionResponseV1(
      choiceIndex: choiceIndex,
      attemptId: '${json['attempt_id'] ?? ''}',
      answeredAt: answeredAt,
    );
  }

  final int choiceIndex;
  final String attemptId;
  final DateTime answeredAt;

  Map<String, dynamic> toJson() => {
        'choice_index': choiceIndex,
        'attempt_id': attemptId,
        'answered_at': answeredAt.toIso8601String(),
      };
}

/// Immutable question sequence and committed responses for resumable learning.
final class QualificationSessionV1 {
  QualificationSessionV1({
    required this.sessionId,
    required this.appKey,
    required this.bankRevision,
    required this.mode,
    required Iterable<String> questionIds,
    required this.currentIndex,
    required Map<String, SessionResponseV1> committedResponses,
    required this.startedAt,
    required this.updatedAt,
    this.examProfileVersion,
    this.unitId,
    this.retrySourceSessionId,
  })  : questionIds = List.unmodifiable(questionIds),
        committedResponses = Map.unmodifiable(committedResponses) {
    if (sessionId.trim().isEmpty ||
        appKey.trim().isEmpty ||
        bankRevision.trim().isEmpty) {
      throw ArgumentError('Session identity fields must not be empty.');
    }
    if (this.questionIds.isEmpty ||
        this.questionIds.any((id) => id.trim().isEmpty) ||
        this.questionIds.toSet().length != this.questionIds.length) {
      throw ArgumentError.value(this.questionIds, 'questionIds');
    }
    if (currentIndex < 0 || currentIndex >= this.questionIds.length) {
      throw ArgumentError.value(currentIndex, 'currentIndex');
    }
    if (!startedAt.isUtc || !updatedAt.isUtc || updatedAt.isBefore(startedAt)) {
      throw ArgumentError('Session timestamps must be ordered UTC values.');
    }
    if (!this.questionIds.toSet().containsAll(this.committedResponses.keys)) {
      throw ArgumentError('Committed responses must belong to the session.');
    }
  }

  factory QualificationSessionV1.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != schemaVersion) {
      throw const FormatException('Unsupported qualification session schema.');
    }
    final rawIds = json['question_ids'];
    final rawResponses = json['committed_responses'];
    final startedAt = DateTime.tryParse('${json['started_at'] ?? ''}');
    final updatedAt = DateTime.tryParse('${json['updated_at'] ?? ''}');
    if (rawIds is! List ||
        rawResponses is! Map ||
        startedAt == null ||
        updatedAt == null ||
        !startedAt.isUtc ||
        !updatedAt.isUtc) {
      throw const FormatException('Invalid qualification session payload.');
    }
    final responses = <String, SessionResponseV1>{};
    for (final entry in rawResponses.entries) {
      if (entry.value is! Map) {
        throw const FormatException('Invalid committed response.');
      }
      responses['${entry.key}'] = SessionResponseV1.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }
    final currentIndex = json['current_index'];
    if (currentIndex is! int) {
      throw const FormatException('current_index must be an integer.');
    }
    return QualificationSessionV1(
      sessionId: '${json['session_id'] ?? ''}',
      appKey: '${json['app_key'] ?? ''}',
      bankRevision: '${json['bank_revision'] ?? ''}',
      mode: LearningModeV1.fromWireName('${json['mode'] ?? ''}'),
      questionIds: rawIds.map((value) => '$value'),
      currentIndex: currentIndex,
      committedResponses: responses,
      startedAt: startedAt,
      updatedAt: updatedAt,
      examProfileVersion: json['exam_profile_version'] as String?,
      unitId: json['unit_id'] as String?,
      retrySourceSessionId: json['retry_source_session_id'] as String?,
    );
  }

  static const int schemaVersion = 1;

  final String sessionId;
  final String appKey;
  final String bankRevision;
  final LearningModeV1 mode;
  final List<String> questionIds;
  final int currentIndex;
  final Map<String, SessionResponseV1> committedResponses;
  final DateTime startedAt;
  final DateTime updatedAt;
  final String? examProfileVersion;
  final String? unitId;
  final String? retrySourceSessionId;

  String get currentQuestionId => questionIds[currentIndex];

  QualificationSessionV1 copyWith({
    int? currentIndex,
    Map<String, SessionResponseV1>? committedResponses,
    DateTime? updatedAt,
  }) {
    return QualificationSessionV1(
      sessionId: sessionId,
      appKey: appKey,
      bankRevision: bankRevision,
      mode: mode,
      questionIds: questionIds,
      currentIndex: currentIndex ?? this.currentIndex,
      committedResponses: committedResponses ?? this.committedResponses,
      startedAt: startedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      examProfileVersion: examProfileVersion,
      unitId: unitId,
      retrySourceSessionId: retrySourceSessionId,
    );
  }

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'session_id': sessionId,
        'app_key': appKey,
        'bank_revision': bankRevision,
        'mode': mode.wireName,
        'question_ids': questionIds,
        'current_index': currentIndex,
        'committed_responses': committedResponses.map(
          (key, response) => MapEntry(key, response.toJson()),
        ),
        'started_at': startedAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'exam_profile_version': examProfileVersion,
        'unit_id': unitId,
        'retry_source_session_id': retrySourceSessionId,
      };
}
