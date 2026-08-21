import 'practice_engine.dart';

final class ExamUnitAllocationV1 {
  const ExamUnitAllocationV1({
    required this.unitId,
    required this.questionCount,
  });

  final String unitId;
  final int questionCount;
}

final class ExamSectionPassRuleV1 {
  const ExamSectionPassRuleV1({
    required this.unitId,
    required this.minimumPercent,
  });

  final String unitId;
  final int minimumPercent;
}

final class MockExamProfileV1 {
  MockExamProfileV1({
    required this.profileVersion,
    required this.questionCount,
    required this.timeLimitMinutes,
    required Iterable<ExamUnitAllocationV1> allocations,
    required this.overallPassPercent,
    required Iterable<ExamSectionPassRuleV1> sectionPassRules,
    required this.shuffleQuestions,
  })  : allocations = List.unmodifiable(allocations),
        sectionPassRules = List.unmodifiable(sectionPassRules) {
    if (profileVersion.trim().isEmpty || questionCount < 1) {
      throw ArgumentError('Mock exam profile identity and count are required.');
    }
    if (timeLimitMinutes != null && timeLimitMinutes! < 1) {
      throw ArgumentError.value(timeLimitMinutes, 'timeLimitMinutes');
    }
    if (overallPassPercent != null &&
        (overallPassPercent! < 1 || overallPassPercent! > 100)) {
      throw ArgumentError.value(overallPassPercent, 'overallPassPercent');
    }
    if (this.allocations.any((allocation) => allocation.questionCount < 1)) {
      throw ArgumentError.value(this.allocations, 'allocations');
    }
    if (this.allocations.isNotEmpty &&
        this.allocations.fold<int>(
                  0,
                  (sum, allocation) => sum + allocation.questionCount,
                ) !=
            questionCount) {
      throw ArgumentError('Mock exam allocations must sum to questionCount.');
    }
    if (this.sectionPassRules.any(
          (rule) => rule.minimumPercent < 1 || rule.minimumPercent > 100,
        )) {
      throw ArgumentError.value(this.sectionPassRules, 'sectionPassRules');
    }
  }

  final String profileVersion;
  final int questionCount;
  final int? timeLimitMinutes;
  final List<ExamUnitAllocationV1> allocations;
  final int? overallPassPercent;
  final List<ExamSectionPassRuleV1> sectionPassRules;
  final bool shuffleQuestions;
}

final class MockExamQuestionV1 {
  const MockExamQuestionV1({
    required this.questionId,
    required this.unitId,
    required this.correctChoiceIndex,
  });

  final String questionId;
  final String unitId;
  final int correctChoiceIndex;
}

final class MockExamSectionResultV1 {
  const MockExamSectionResultV1({
    required this.unitId,
    required this.correctCount,
    required this.totalCount,
    required this.passed,
  });

  final String unitId;
  final int correctCount;
  final int totalCount;
  final bool? passed;
}

final class MockExamResultV1 {
  const MockExamResultV1({
    required this.correctCount,
    required this.totalCount,
    required this.sections,
    required this.passed,
  });

  final int correctCount;
  final int totalCount;
  final Map<String, MockExamSectionResultV1> sections;
  final bool? passed;
}

final class MockExamEngineV1 {
  MockExamEngineV1({QuestionRandomizer? randomizer})
      : _randomizer = randomizer ?? DartQuestionRandomizer();

  final QuestionRandomizer _randomizer;

  List<String> createQuestionSequence({
    required MockExamProfileV1 profile,
    required Iterable<QuestionCandidate> accessibleQuestions,
  }) {
    final questions = accessibleQuestions.toList(growable: false);
    final selected = <QuestionCandidate>[];
    if (profile.allocations.isEmpty) {
      selected.addAll(
        _randomizer.reorder(questions).take(profile.questionCount),
      );
    } else {
      for (final allocation in profile.allocations) {
        final candidates = questions.where(
          (question) => question.unitId == allocation.unitId,
        );
        final unitSelection = _randomizer
            .reorder(candidates)
            .take(allocation.questionCount)
            .toList(growable: false);
        if (unitSelection.length != allocation.questionCount) {
          throw StateError(
            'Not enough accessible questions for ${allocation.unitId}.',
          );
        }
        selected.addAll(unitSelection);
      }
    }
    if (selected.length != profile.questionCount) {
      throw StateError('Not enough accessible questions for the mock exam.');
    }
    final sequence =
        profile.shuffleQuestions ? _randomizer.reorder(selected) : selected;
    return sequence
        .map((question) => question.questionId)
        .toList(growable: false);
  }

  MockExamResultV1 score({
    required MockExamProfileV1 profile,
    required Iterable<MockExamQuestionV1> questions,
    required Map<String, int> responses,
  }) {
    final questionList = questions.toList(growable: false);
    var correct = 0;
    final byUnit = <String, List<MockExamQuestionV1>>{};
    for (final question in questionList) {
      if (responses[question.questionId] == question.correctChoiceIndex) {
        correct += 1;
      }
      byUnit.putIfAbsent(question.unitId, () => []).add(question);
    }
    final rules = {
      for (final rule in profile.sectionPassRules) rule.unitId: rule,
    };
    final sections = <String, MockExamSectionResultV1>{};
    for (final unitId in byUnit.keys.toList()..sort()) {
      final unitQuestions = byUnit[unitId]!;
      final unitCorrect = unitQuestions
          .where(
            (question) =>
                responses[question.questionId] == question.correctChoiceIndex,
          )
          .length;
      final rule = rules[unitId];
      sections[unitId] = MockExamSectionResultV1(
        unitId: unitId,
        correctCount: unitCorrect,
        totalCount: unitQuestions.length,
        passed: rule == null
            ? null
            : unitCorrect * 100 >= unitQuestions.length * rule.minimumPercent,
      );
    }
    final overallRule = profile.overallPassPercent;
    final hasRule = overallRule != null || rules.isNotEmpty;
    final overallPassed = overallRule == null
        ? true
        : correct * 100 >= questionList.length * overallRule;
    final sectionsPassed = sections.values
        .where((section) => section.passed != null)
        .every((section) => section.passed!);
    return MockExamResultV1(
      correctCount: correct,
      totalCount: questionList.length,
      sections: Map.unmodifiable(sections),
      passed: hasRule ? overallPassed && sectionsPassed : null,
    );
  }
}
