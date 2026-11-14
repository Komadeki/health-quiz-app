import '../../models/score_record.dart';
import 'exam_question.dart';

/// A separate, versioned snapshot keeps mixed answer formats out of legacy
/// choice-only sessions, while retaining the original question identities.
class ExamSession {
  ExamSession({
    required this.id,
    required List<ExamQuestion> questions,
    required Map<String, String> unitTitles,
    required this.startedAt,
    Map<String, String> responses = const {},
    this.index = 0,
    this.elapsedSeconds = 0,
    this.submittedAt,
  })  : questions = List.unmodifiable(questions),
        unitTitles = Map.unmodifiable(unitTitles),
        responses = Map.unmodifiable(responses) {
    if (id.isEmpty ||
        questions.isEmpty ||
        questions.length > 30 ||
        index < 0 ||
        index >= questions.length ||
        elapsedSeconds < 0 ||
        questions.map((q) => q.id).toSet().length != questions.length ||
        responses.keys.any((id) => !questions.any((q) => q.id == id))) {
      throw const FormatException('Invalid exam session');
    }
    for (final q in questions) {
      final answer = responses[q.id];
      if (answer == null || answer.isEmpty) continue;
      if (q.type == ExamQuestionType.choice) {
        final selected = int.tryParse(answer);
        if (selected == null || selected < 0 || selected >= q.choices.length) {
          throw const FormatException('Invalid saved choice');
        }
      }
      if (q.type == ExamQuestionType.trueFalse &&
          answer != '○' &&
          answer != '×') {
        throw const FormatException('Invalid saved true/false response');
      }
    }
  }

  final String id;
  final List<ExamQuestion> questions;
  final Map<String, String> unitTitles;
  final Map<String, String> responses;
  final DateTime startedAt;
  final DateTime? submittedAt;
  final int index;
  final int elapsedSeconds;
  bool get submitted => submittedAt != null;
  int get score => questions.where((q) => q.isCorrect(responses[q.id])).length;

  ExamSession progress(
          {required Map<String, String> responses,
          required int index,
          required int elapsedSeconds,
          DateTime? submittedAt}) =>
      ExamSession(
          id: id,
          questions: questions,
          unitTitles: unitTitles,
          startedAt: startedAt,
          responses: responses,
          index: index,
          elapsedSeconds: elapsedSeconds,
          submittedAt: submittedAt ?? this.submittedAt);

  factory ExamSession.fromJson(Map<String, dynamic> json) {
    if (json['schemaVersion'] != 1) {
      throw const FormatException('Unsupported exam session');
    }
    return ExamSession(
      id: json['id'] as String,
      questions: (json['questions'] as List)
          .map(
              (q) => ExamQuestion.fromJson(Map<String, dynamic>.from(q as Map)))
          .toList(),
      unitTitles: Map<String, String>.from(json['unitTitles'] as Map),
      responses: Map<String, String>.from(json['responses'] as Map),
      index: json['index'] as int,
      elapsedSeconds: json['elapsedSeconds'] as int,
      startedAt: DateTime.parse(json['startedAt'] as String),
      submittedAt: json['submittedAt'] == null
          ? null
          : DateTime.parse(json['submittedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': 1,
        'id': id,
        'questions': questions.map((q) => q.toJson()).toList(),
        'unitTitles': unitTitles,
        'responses': responses,
        'index': index,
        'elapsedSeconds': elapsedSeconds,
        'startedAt': startedAt.toIso8601String(),
        if (submittedAt != null) 'submittedAt': submittedAt!.toIso8601String(),
      };

  ScoreRecord toScoreRecord() {
    if (!submitted) throw StateError('Exam has not been submitted');
    final units = <String, int>{};
    final stats = <String, TagStat>{};
    for (final q in questions) {
      units.update(q.unitId, (n) => n + 1, ifAbsent: () => 1);
      final correct = q.isCorrect(responses[q.id]);
      for (final key in [
        '単元:${unitTitles[q.unitId] ?? q.unitId}',
        '形式:${q.typeLabel}'
      ]) {
        final previous = stats[key];
        stats[key] = TagStat(
            correct: (previous?.correct ?? 0) + (correct ? 1 : 0),
            wrong: (previous?.wrong ?? 0) + (correct ? 0 : 1));
      }
    }
    return ScoreRecord(
        id: id,
        sessionId: id,
        deckId: 'exam',
        deckTitle: '定期テスト対策',
        score: score,
        total: questions.length,
        timestamp: submittedAt!.millisecondsSinceEpoch,
        durationSec: elapsedSeconds,
        selectedUnitIds: units.keys.toList(),
        unitBreakdown: units,
        tags: stats,
        examProfileVersion: 'health-term-exam-v1');
  }
}
