import 'learning_event.dart';

final class SessionHistoryV1 {
  SessionHistoryV1({
    required this.appKey,
    required this.sessionId,
    required this.mode,
    required Iterable<String> questionIds,
    required this.correctCount,
    required this.completedAt,
    this.unitId,
    this.examProfileVersion,
    this.passed,
  }) : questionIds = List.unmodifiable(questionIds) {
    if (!completedAt.isUtc) {
      throw ArgumentError.value(completedAt, 'completedAt', 'must be UTC');
    }
    if (correctCount < 0 || correctCount > this.questionIds.length) {
      throw ArgumentError.value(correctCount, 'correctCount');
    }
  }

  factory SessionHistoryV1.fromJson(Map<String, dynamic> json) {
    if (json['schema_version'] != schemaVersion) {
      throw const FormatException('Unsupported session-history schema.');
    }
    final questionIds = json['question_ids'];
    final correctCount = json['correct_count'];
    final completedAt = DateTime.tryParse('${json['completed_at'] ?? ''}');
    if (questionIds is! List ||
        correctCount is! int ||
        completedAt == null ||
        !completedAt.isUtc) {
      throw const FormatException('Invalid session-history payload.');
    }
    return SessionHistoryV1(
      appKey: '${json['app_key'] ?? ''}',
      sessionId: '${json['session_id'] ?? ''}',
      mode: LearningModeV1.fromWireName('${json['mode'] ?? ''}'),
      questionIds: questionIds.map((value) => '$value'),
      correctCount: correctCount,
      completedAt: completedAt,
      unitId: json['unit_id'] as String?,
      examProfileVersion: json['exam_profile_version'] as String?,
      passed: json['passed'] as bool?,
    );
  }

  static const int schemaVersion = 1;

  final String appKey;
  final String sessionId;
  final LearningModeV1 mode;
  final List<String> questionIds;
  final int correctCount;
  final DateTime completedAt;
  final String? unitId;
  final String? examProfileVersion;
  final bool? passed;

  int get totalCount => questionIds.length;

  Map<String, dynamic> toJson() => {
        'schema_version': schemaVersion,
        'app_key': appKey,
        'session_id': sessionId,
        'mode': mode.wireName,
        'question_ids': questionIds,
        'correct_count': correctCount,
        'completed_at': completedAt.toIso8601String(),
        'unit_id': unitId,
        'exam_profile_version': examProfileVersion,
        'passed': passed,
      };
}

abstract interface class LearningRepository {
  Future<void> recordAnswer(LearningEventV1 event);

  Future<List<LearningEventV1>> loadEventsByQuestion(String questionId);

  Future<List<LearningEventV1>> loadEventsByUnit(String unitId);

  Future<List<LearningEventV1>> loadRecentEvents({int limit = 50});

  Future<List<LearningEventV1>> loadAllEvents();

  Future<int> countAttempts(String questionId);

  Future<Set<String>> loadUnansweredQuestionIds(
    Iterable<String> eligibleQuestionIds,
  );

  Future<Set<String>> loadIncorrectQuestionIds(
    Iterable<String> eligibleQuestionIds,
  );

  Future<void> recordSessionHistory(SessionHistoryV1 history);

  Future<List<SessionHistoryV1>> loadSessionHistory({int limit = 50});

  Future<List<SessionHistoryV1>> loadMockExamHistory({int limit = 50});
}
