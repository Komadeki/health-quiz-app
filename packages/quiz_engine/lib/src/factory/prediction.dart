import 'progress.dart';
import 'weakness.dart';

final class LearningFeatureSnapshot {
  const LearningFeatureSnapshot({
    required this.createdAt,
    required this.progress,
    required this.weakness,
  });

  final DateTime createdAt;
  final ProgressSnapshotV1 progress;
  final WeaknessSummaryV1 weakness;
}

final class PredictionEvaluation {
  const PredictionEvaluation.unavailable({this.reasonCode = 'unavailable'})
      : value = null,
        available = false;

  const PredictionEvaluation.available({
    required this.value,
    required this.reasonCode,
  }) : available = true;

  final bool available;
  final double? value;
  final String reasonCode;
}

abstract interface class PredictionEngine {
  PredictionEvaluation evaluate(LearningFeatureSnapshot snapshot);
}

final class UnavailablePredictionEngine implements PredictionEngine {
  const UnavailablePredictionEngine();

  @override
  PredictionEvaluation evaluate(LearningFeatureSnapshot snapshot) {
    return const PredictionEvaluation.unavailable(
      reasonCode: 'factory_v1_no_validated_model',
    );
  }
}
