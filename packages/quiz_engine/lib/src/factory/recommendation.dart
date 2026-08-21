import 'practice_engine.dart';
import 'weakness.dart';

final class RecommendationV1 {
  const RecommendationV1({
    required this.unitId,
    required this.reasonCode,
    required this.supportingMetrics,
  });

  final String unitId;
  final String reasonCode;
  final Map<String, double> supportingMetrics;
}

abstract interface class RecommendationEngine {
  RecommendationV1? recommend({
    required Iterable<QuestionCandidate> questions,
    required WeaknessSummaryV1 weakness,
  });
}

/// Transparent local baseline: no-attempt units first, then lowest recent score.
final class DeterministicRecommendationEngine implements RecommendationEngine {
  const DeterministicRecommendationEngine();

  @override
  RecommendationV1? recommend({
    required Iterable<QuestionCandidate> questions,
    required WeaknessSummaryV1 weakness,
  }) {
    final units = questions.map((question) => question.unitId).toSet().toList()
      ..sort();
    if (units.isEmpty) return null;
    units.sort((left, right) {
      final leftMetric = weakness.byUnit[left];
      final rightMetric = weakness.byUnit[right];
      final leftAttempts = leftMetric?.attemptCount ?? 0;
      final rightAttempts = rightMetric?.attemptCount ?? 0;
      if (leftAttempts == 0 && rightAttempts != 0) return -1;
      if (rightAttempts == 0 && leftAttempts != 0) return 1;
      final leftScore =
          leftMetric?.recentCorrectness ?? leftMetric?.correctness ?? 0;
      final rightScore =
          rightMetric?.recentCorrectness ?? rightMetric?.correctness ?? 0;
      final scoreOrder = leftScore.compareTo(rightScore);
      return scoreOrder != 0 ? scoreOrder : left.compareTo(right);
    });
    final unitId = units.first;
    final metric = weakness.byUnit[unitId];
    if (metric == null || metric.attemptCount == 0) {
      return RecommendationV1(
        unitId: unitId,
        reasonCode: 'unanswered_unit',
        supportingMetrics: const {'attempt_count': 0},
      );
    }
    return RecommendationV1(
      unitId: unitId,
      reasonCode: 'lowest_recent_correctness',
      supportingMetrics: {
        'attempt_count': metric.attemptCount.toDouble(),
        'recent_correctness':
            metric.recentCorrectness ?? metric.correctness ?? 0,
      },
    );
  }
}
