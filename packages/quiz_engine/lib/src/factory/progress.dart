import 'learning_event.dart';
import 'practice_engine.dart';

final class ProgressMetricV1 {
  const ProgressMetricV1({
    required this.totalQuestions,
    required this.completedQuestions,
    required this.attemptCount,
    required this.correctCount,
    required this.unansweredCount,
    required this.accuracy,
    required this.recentAccuracy,
  });

  final int totalQuestions;
  final int completedQuestions;
  final int attemptCount;
  final int correctCount;
  final int unansweredCount;
  final double? accuracy;
  final double? recentAccuracy;

  double get completion =>
      totalQuestions == 0 ? 0 : completedQuestions / totalQuestions;
}

final class ProgressSnapshotV1 {
  const ProgressSnapshotV1({required this.overall, required this.byUnit});

  final ProgressMetricV1 overall;
  final Map<String, ProgressMetricV1> byUnit;
}

final class ProgressCalculatorV1 {
  const ProgressCalculatorV1({this.recentWindow = 20});

  final int recentWindow;

  ProgressSnapshotV1 calculate(
    Iterable<QuestionCandidate> questions,
    Iterable<LearningEventV1> events,
  ) {
    final questionList = questions.toList(growable: false);
    final eventList = events.toList(growable: false)
      ..sort((left, right) => left.answeredAt.compareTo(right.answeredAt));
    final ids = questionList.map((question) => question.questionId).toSet();
    final relevantEvents = eventList
        .where((event) => ids.contains(event.questionId))
        .toList(growable: false);
    final unitIds = questionList.map((question) => question.unitId).toSet();
    final byUnit = <String, ProgressMetricV1>{};
    for (final unitId in unitIds.toList()..sort()) {
      final unitQuestionIds = questionList
          .where((question) => question.unitId == unitId)
          .map((question) => question.questionId)
          .toSet();
      byUnit[unitId] = _metric(
        unitQuestionIds,
        relevantEvents.where(
          (event) => unitQuestionIds.contains(event.questionId),
        ),
      );
    }
    return ProgressSnapshotV1(
      overall: _metric(ids, relevantEvents),
      byUnit: Map.unmodifiable(byUnit),
    );
  }

  ProgressMetricV1 _metric(
    Set<String> questionIds,
    Iterable<LearningEventV1> events,
  ) {
    final list = events.toList(growable: false);
    final completed = list.map((event) => event.questionId).toSet().length;
    final correct = list.where((event) => event.correct).length;
    final recent = list.length <= recentWindow
        ? list
        : list.sublist(list.length - recentWindow);
    final recentCorrect = recent.where((event) => event.correct).length;
    return ProgressMetricV1(
      totalQuestions: questionIds.length,
      completedQuestions: completed,
      attemptCount: list.length,
      correctCount: correct,
      unansweredCount: questionIds.length - completed,
      accuracy: list.isEmpty ? null : correct / list.length,
      recentAccuracy: recent.isEmpty ? null : recentCorrect / recent.length,
    );
  }
}
