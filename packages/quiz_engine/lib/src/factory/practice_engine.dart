import 'dart:math';

import 'learning_event.dart';

final class QuestionCandidate {
  const QuestionCandidate({
    required this.questionId,
    required this.unitId,
    required this.isPremium,
    this.knowledgeTarget,
  });

  final String questionId;
  final String unitId;
  final bool isPremium;
  final String? knowledgeTarget;
}

abstract interface class QuestionRandomizer {
  List<T> reorder<T>(Iterable<T> values);
}

final class DartQuestionRandomizer implements QuestionRandomizer {
  DartQuestionRandomizer([Random? random]) : _random = random ?? Random();

  final Random _random;

  @override
  List<T> reorder<T>(Iterable<T> values) {
    final result = values.toList(growable: false);
    for (var index = result.length - 1; index > 0; index -= 1) {
      final target = _random.nextInt(index + 1);
      final value = result[index];
      result[index] = result[target];
      result[target] = value;
    }
    return result;
  }
}

final class IdentityQuestionRandomizer implements QuestionRandomizer {
  const IdentityQuestionRandomizer();

  @override
  List<T> reorder<T>(Iterable<T> values) => values.toList(growable: false);
}

/// Shared selection rules. Premium filtering is injected from entitlement state.
final class PracticeSelectionEngine {
  PracticeSelectionEngine({
    required bool Function(QuestionCandidate candidate) canAccess,
    QuestionRandomizer? randomizer,
  })  : _canAccess = canAccess,
        _randomizer = randomizer ?? DartQuestionRandomizer();

  final bool Function(QuestionCandidate candidate) _canAccess;
  final QuestionRandomizer _randomizer;

  List<String> selectUnit(
    Iterable<QuestionCandidate> questions,
    String unitId,
  ) {
    return _ids(questions.where((question) => question.unitId == unitId));
  }

  List<String> selectRandom(
    Iterable<QuestionCandidate> questions, {
    required int count,
  }) {
    if (count < 1) throw ArgumentError.value(count, 'count');
    return _randomizer
        .reorder(questions.where(_canAccess))
        .take(count)
        .map((question) => question.questionId)
        .toList(growable: false);
  }

  List<String> selectUnanswered(
    Iterable<QuestionCandidate> questions,
    Iterable<LearningEventV1> events,
  ) {
    final answered = events.map((event) => event.questionId).toSet();
    return _ids(
      questions.where((question) => !answered.contains(question.questionId)),
    );
  }

  /// A later correct answer removes the question from the incorrect pool.
  List<String> selectIncorrect(
    Iterable<QuestionCandidate> questions,
    Iterable<LearningEventV1> events,
  ) {
    final latest = <String, LearningEventV1>{};
    for (final event in events) {
      final previous = latest[event.questionId];
      if (previous == null || event.answeredAt.isAfter(previous.answeredAt)) {
        latest[event.questionId] = event;
      }
    }
    return _ids(
      questions.where(
        (question) => latest[question.questionId]?.correct == false,
      ),
    );
  }

  List<String> selectRetry(
    Iterable<QuestionCandidate> questions,
    Iterable<String> resultQuestionIds,
  ) {
    final requested = resultQuestionIds.toSet();
    return _ids(
      questions.where((question) => requested.contains(question.questionId)),
    );
  }

  List<String> _ids(Iterable<QuestionCandidate> values) {
    final accessible = values.where(_canAccess).toList(growable: false)
      ..sort((left, right) => left.questionId.compareTo(right.questionId));
    return accessible
        .map((question) => question.questionId)
        .toList(growable: false);
  }
}
