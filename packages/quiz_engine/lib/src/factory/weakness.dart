import 'learning_event.dart';
import 'practice_engine.dart';

final class WeaknessMetricV1 {
  const WeaknessMetricV1({
    required this.attemptCount,
    required this.correctness,
    required this.recentCorrectness,
    required this.averageResponseDurationMs,
  });

  final int attemptCount;
  final double? correctness;
  final double? recentCorrectness;
  final double? averageResponseDurationMs;
}

final class WeaknessSummaryV1 {
  const WeaknessSummaryV1({
    required this.overall,
    required this.byUnit,
    required this.byKnowledgeTarget,
  });

  final WeaknessMetricV1 overall;
  final Map<String, WeaknessMetricV1> byUnit;
  final Map<String, WeaknessMetricV1> byKnowledgeTarget;
}

final class WeaknessCalculatorV1 {
  const WeaknessCalculatorV1({this.recentWindow = 10});

  final int recentWindow;

  WeaknessSummaryV1 calculate(
    Iterable<QuestionCandidate> questions,
    Iterable<LearningEventV1> events,
  ) {
    final metadata = {
      for (final question in questions) question.questionId: question,
    };
    final relevant = events
        .where((event) => metadata.containsKey(event.questionId))
        .toList(growable: false)
      ..sort((left, right) => left.answeredAt.compareTo(right.answeredAt));
    final units = <String, List<LearningEventV1>>{};
    final targets = <String, List<LearningEventV1>>{};
    for (final event in relevant) {
      units.putIfAbsent(event.unitId, () => []).add(event);
      final target = event.knowledgeTarget;
      if (target != null && target.isNotEmpty) {
        targets.putIfAbsent(target, () => []).add(event);
      }
    }
    return WeaknessSummaryV1(
      overall: _metric(relevant),
      byUnit: Map.unmodifiable({
        for (final key in units.keys.toList()..sort())
          key: _metric(units[key]!),
      }),
      byKnowledgeTarget: Map.unmodifiable({
        for (final key in targets.keys.toList()..sort())
          key: _metric(targets[key]!),
      }),
    );
  }

  WeaknessMetricV1 _metric(List<LearningEventV1> events) {
    final correct = events.where((event) => event.correct).length;
    final recent = events.length <= recentWindow
        ? events
        : events.sublist(events.length - recentWindow);
    final recentCorrect = recent.where((event) => event.correct).length;
    final duration = events.fold<int>(
      0,
      (sum, event) => sum + event.responseDurationMs,
    );
    return WeaknessMetricV1(
      attemptCount: events.length,
      correctness: events.isEmpty ? null : correct / events.length,
      recentCorrectness: recent.isEmpty ? null : recentCorrect / recent.length,
      averageResponseDurationMs:
          events.isEmpty ? null : duration / events.length,
    );
  }
}
