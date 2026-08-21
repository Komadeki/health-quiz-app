import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:quiz_engine/quiz_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class QualificationSessionStore {
  Future<QualificationSessionV1?> load();
  Future<void> save(QualificationSessionV1 session);
  Future<void> clear();
}

final class SharedPreferencesQualificationSessionStore
    implements QualificationSessionStore {
  const SharedPreferencesQualificationSessionStore({required this.appKey});

  final String appKey;

  String get _key => 'qualification_factory.$appKey.active_session.v1';

  @override
  Future<QualificationSessionV1?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('Session is not a map.');
      return QualificationSessionV1.fromJson(
        Map<String, dynamic>.from(decoded),
      );
    } on Object {
      await preferences.remove(_key);
      return null;
    }
  }

  @override
  Future<void> save(QualificationSessionV1 session) async {
    if (session.appKey != appKey) {
      throw ArgumentError.value(session.appKey, 'session.appKey');
    }
    await (await SharedPreferences.getInstance()).setString(
      _key,
      jsonEncode(session.toJson()),
    );
  }

  @override
  Future<void> clear() async {
    await (await SharedPreferences.getInstance()).remove(_key);
  }
}

typedef LearningDataDirectoryProvider = Future<Directory> Function();

/// Append-only, namespaced JSON Lines storage for growing local learning data.
///
/// The first record is a schema header. Future schema versions migrate by
/// reading the old journal and writing a new versioned file; unsupported
/// versions fail closed instead of rewriting history.
final class JsonLinesLearningRepository implements LearningRepository {
  JsonLinesLearningRepository({
    required this.appKey,
    LearningDataDirectoryProvider? directoryProvider,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const int storageSchemaVersion = 1;

  final String appKey;
  final LearningDataDirectoryProvider _directoryProvider;

  Future<File> get _journal async {
    final root = await _directoryProvider();
    final namespace = Directory(
      '${root.path}${Platform.pathSeparator}qualification_factory'
      '${Platform.pathSeparator}$appKey',
    );
    await namespace.create(recursive: true);
    return File('${namespace.path}${Platform.pathSeparator}learning.v1.jsonl');
  }

  Future<List<Map<String, dynamic>>> _readRecords() async {
    final file = await _journal;
    if (!await file.exists()) {
      await file.writeAsString('${jsonEncode(_header)}\n', flush: true);
      return const [];
    }
    final lines = await file.readAsLines();
    if (lines.isEmpty) {
      throw const FormatException('Learning journal header is missing.');
    }
    final header = jsonDecode(lines.first);
    if (header is! Map ||
        header['record_type'] != 'schema' ||
        header['schema_version'] != storageSchemaVersion ||
        header['app_key'] != appKey) {
      throw const FormatException('Unsupported learning journal schema.');
    }
    final records = <Map<String, dynamic>>[];
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      final decoded = jsonDecode(line);
      if (decoded is! Map) {
        throw const FormatException('Invalid learning journal record.');
      }
      records.add(Map<String, dynamic>.from(decoded));
    }
    return records;
  }

  Map<String, dynamic> get _header => {
        'record_type': 'schema',
        'schema_version': storageSchemaVersion,
        'app_key': appKey,
      };

  Future<void> _append(Map<String, dynamic> record) async {
    await _readRecords();
    final file = await _journal;
    await file.writeAsString(
      '${jsonEncode(record)}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  @override
  Future<void> recordAnswer(LearningEventV1 event) async {
    if (event.appKey != appKey) {
      throw ArgumentError.value(event.appKey, 'event.appKey');
    }
    final events = await loadAllEvents();
    final matching =
        events.where((existing) => existing.attemptId == event.attemptId);
    if (matching.isNotEmpty) {
      if (_sameLearningEvent(matching.single, event)) return;
      throw StateError('Conflicting learning attempt: ${event.attemptId}');
    }
    final expectedAttempt =
        events.where((item) => item.questionId == event.questionId).length + 1;
    if (event.attemptNumber != expectedAttempt) {
      throw StateError(
        'Expected attempt_number $expectedAttempt for ${event.questionId}.',
      );
    }
    await _append({'record_type': 'learning_event', 'payload': event.toJson()});
  }

  @override
  Future<List<LearningEventV1>> loadAllEvents() async {
    final records = await _readRecords();
    return List.unmodifiable([
      for (final record in records)
        if (record['record_type'] == 'learning_event')
          LearningEventV1.fromJson(
            Map<String, dynamic>.from(record['payload'] as Map),
          ),
    ]);
  }

  @override
  Future<List<LearningEventV1>> loadEventsByQuestion(String questionId) async {
    return List.unmodifiable(
      (await loadAllEvents()).where((event) => event.questionId == questionId),
    );
  }

  @override
  Future<List<LearningEventV1>> loadEventsByUnit(String unitId) async {
    return List.unmodifiable(
      (await loadAllEvents()).where((event) => event.unitId == unitId),
    );
  }

  @override
  Future<List<LearningEventV1>> loadRecentEvents({int limit = 50}) async {
    if (limit < 0) throw ArgumentError.value(limit, 'limit');
    final events = [...await loadAllEvents()]
      ..sort((left, right) => right.answeredAt.compareTo(left.answeredAt));
    return List.unmodifiable(events.take(limit));
  }

  @override
  Future<int> countAttempts(String questionId) async {
    return (await loadEventsByQuestion(questionId)).length;
  }

  @override
  Future<Set<String>> loadUnansweredQuestionIds(
    Iterable<String> eligibleQuestionIds,
  ) async {
    final answered =
        (await loadAllEvents()).map((event) => event.questionId).toSet();
    return eligibleQuestionIds.where((id) => !answered.contains(id)).toSet();
  }

  @override
  Future<Set<String>> loadIncorrectQuestionIds(
    Iterable<String> eligibleQuestionIds,
  ) async {
    final eligible = eligibleQuestionIds.toSet();
    final latest = <String, LearningEventV1>{};
    for (final event in await loadAllEvents()) {
      if (!eligible.contains(event.questionId)) continue;
      final previous = latest[event.questionId];
      if (previous == null || event.answeredAt.isAfter(previous.answeredAt)) {
        latest[event.questionId] = event;
      }
    }
    return latest.entries
        .where((entry) => !entry.value.correct)
        .map((entry) => entry.key)
        .toSet();
  }

  @override
  Future<void> recordSessionHistory(SessionHistoryV1 history) async {
    if (history.appKey != appKey) {
      throw ArgumentError.value(history.appKey, 'history.appKey');
    }
    final existing = await loadSessionHistory(limit: 1 << 30);
    final matching =
        existing.where((item) => item.sessionId == history.sessionId);
    if (matching.isNotEmpty) {
      if (_sameSessionHistory(matching.single, history)) return;
      throw StateError('Conflicting session history: ${history.sessionId}');
    }
    await _append({
      'record_type': 'session_history',
      'payload': history.toJson(),
    });
  }

  @override
  Future<List<SessionHistoryV1>> loadSessionHistory({int limit = 50}) async {
    if (limit < 0) throw ArgumentError.value(limit, 'limit');
    final records = await _readRecords();
    final history = [
      for (final record in records)
        if (record['record_type'] == 'session_history')
          SessionHistoryV1.fromJson(
            Map<String, dynamic>.from(record['payload'] as Map),
          ),
    ]..sort((left, right) => right.completedAt.compareTo(left.completedAt));
    return List.unmodifiable(history.take(limit));
  }

  @override
  Future<List<SessionHistoryV1>> loadMockExamHistory({int limit = 50}) async {
    return List.unmodifiable(
      (await loadSessionHistory(limit: 1 << 30))
          .where((history) => history.mode == LearningModeV1.mockExam)
          .take(limit),
    );
  }
}

final class InMemoryLearningRepository implements LearningRepository {
  final List<LearningEventV1> _events = [];
  final List<SessionHistoryV1> _history = [];

  @override
  Future<void> recordAnswer(LearningEventV1 event) async {
    final matching =
        _events.where((existing) => existing.attemptId == event.attemptId);
    if (matching.isNotEmpty) {
      if (_sameLearningEvent(matching.single, event)) return;
      throw StateError('Conflicting learning attempt: ${event.attemptId}');
    }
    final expected =
        _events.where((item) => item.questionId == event.questionId).length + 1;
    if (event.attemptNumber != expected) {
      throw StateError('Invalid deterministic attempt number.');
    }
    _events.add(event);
  }

  @override
  Future<int> countAttempts(String questionId) async =>
      _events.where((event) => event.questionId == questionId).length;

  @override
  Future<List<LearningEventV1>> loadAllEvents() async =>
      List.unmodifiable(_events);

  @override
  Future<List<LearningEventV1>> loadEventsByQuestion(String questionId) async =>
      List.unmodifiable(
        _events.where((event) => event.questionId == questionId),
      );

  @override
  Future<List<LearningEventV1>> loadEventsByUnit(String unitId) async =>
      List.unmodifiable(_events.where((event) => event.unitId == unitId));

  @override
  Future<List<LearningEventV1>> loadRecentEvents({int limit = 50}) async {
    final result = [..._events]
      ..sort((left, right) => right.answeredAt.compareTo(left.answeredAt));
    return List.unmodifiable(result.take(limit));
  }

  @override
  Future<Set<String>> loadUnansweredQuestionIds(
    Iterable<String> eligibleQuestionIds,
  ) async {
    final answered = _events.map((event) => event.questionId).toSet();
    return eligibleQuestionIds.where((id) => !answered.contains(id)).toSet();
  }

  @override
  Future<Set<String>> loadIncorrectQuestionIds(
    Iterable<String> eligibleQuestionIds,
  ) async {
    final latest = <String, LearningEventV1>{};
    final eligible = eligibleQuestionIds.toSet();
    for (final event in _events) {
      if (eligible.contains(event.questionId)) latest[event.questionId] = event;
    }
    return latest.entries
        .where((entry) => !entry.value.correct)
        .map((entry) => entry.key)
        .toSet();
  }

  @override
  Future<void> recordSessionHistory(SessionHistoryV1 history) async {
    final matching =
        _history.where((item) => item.sessionId == history.sessionId);
    if (matching.isNotEmpty) {
      if (_sameSessionHistory(matching.single, history)) return;
      throw StateError('Conflicting session history: ${history.sessionId}');
    }
    _history.add(history);
  }

  @override
  Future<List<SessionHistoryV1>> loadSessionHistory({int limit = 50}) async {
    final result = [..._history]
      ..sort((left, right) => right.completedAt.compareTo(left.completedAt));
    return List.unmodifiable(result.take(limit));
  }

  @override
  Future<List<SessionHistoryV1>> loadMockExamHistory({int limit = 50}) async =>
      List.unmodifiable(
        (await loadSessionHistory(limit: 1 << 30))
            .where((history) => history.mode == LearningModeV1.mockExam)
            .take(limit),
      );
}

final class MemoryQualificationSessionStore
    implements QualificationSessionStore {
  QualificationSessionV1? value;

  @override
  Future<void> clear() async => value = null;

  @override
  Future<QualificationSessionV1?> load() async => value;

  @override
  Future<void> save(QualificationSessionV1 session) async => value = session;
}

bool _sameLearningEvent(LearningEventV1 left, LearningEventV1 right) {
  return left.appKey == right.appKey &&
      left.sessionId == right.sessionId &&
      left.attemptId == right.attemptId &&
      left.questionId == right.questionId &&
      left.questionVersion == right.questionVersion &&
      left.bankRevision == right.bankRevision &&
      left.unitId == right.unitId &&
      left.knowledgeTarget == right.knowledgeTarget &&
      left.selectedChoice == right.selectedChoice &&
      left.correct == right.correct &&
      left.answeredAt == right.answeredAt &&
      left.responseDurationMs == right.responseDurationMs &&
      left.attemptNumber == right.attemptNumber &&
      left.mode == right.mode &&
      left.appVersion == right.appVersion;
}

bool _sameSessionHistory(SessionHistoryV1 left, SessionHistoryV1 right) {
  if (left.questionIds.length != right.questionIds.length) return false;
  for (var index = 0; index < left.questionIds.length; index += 1) {
    if (left.questionIds[index] != right.questionIds[index]) return false;
  }
  return left.appKey == right.appKey &&
      left.sessionId == right.sessionId &&
      left.mode == right.mode &&
      left.correctCount == right.correctCount &&
      left.completedAt == right.completedAt &&
      left.unitId == right.unitId &&
      left.examProfileVersion == right.examProfileVersion &&
      left.passed == right.passed;
}
