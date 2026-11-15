import 'dart:math';

import 'exam_question.dart';

/// Builds a test only from the units the learner selected. The caller must
/// pre-filter premium cards using the live Gate entitlements before invoking.
class ExamRangeSelector {
  const ExamRangeSelector();

  List<ExamQuestion> select({
    required Iterable<ExamQuestion> accessibleQuestions,
    required Set<String> selectedUnitIds,
    required int questionCount,
    Random? random,
  }) {
    if (questionCount <= 0 || selectedUnitIds.isEmpty) return const [];
    final rng = random ?? Random();

    // Deduplicate both identity and identical question text. A question is
    // never inserted twice just to meet the requested count.
    final ids = <String>{};
    final prompts = <String>{};
    final candidates = <ExamQuestion>[];
    for (final q in accessibleQuestions) {
      if (!selectedUnitIds.contains(q.unitId) ||
          !ids.add(q.id) ||
          !prompts.add(q.question.trim())) {
        continue;
      }
      candidates.add(q);
    }

    if (candidates.isEmpty) return const [];

    final units = selectedUnitIds.toList(growable: false)..shuffle(rng);
    final byType = <ExamQuestionType, Map<String, List<ExamQuestion>>>{};
    for (final type in ExamQuestionType.values) {
      byType[type] = {
        for (final unitId in units) unitId: <ExamQuestion>[],
      };
    }
    for (final q in candidates) {
      byType[q.type]![q.unitId]!.add(q);
    }
    for (final byUnit in byType.values) {
      for (final items in byUnit.values) {
        items.shuffle(rng);
      }
    }

    final typeCounts = {
      for (final type in ExamQuestionType.values) type: 0,
    };
    final unitCounts = {
      for (final unit in units) unit: 0,
    };
    final representedTypes = candidates.map((q) => q.type).toSet();
    final result = <ExamQuestion>[];

    while (result.length < questionCount) {
      final minimum =
          representedTypes.map((type) => typeCounts[type]!).reduce(min);
      final types = ExamQuestionType.values
          .where((type) =>
              typeCounts[type]! <= minimum &&
              byType[type]!.values.any((pool) => pool.isNotEmpty))
          .toList(growable: false);
      if (types.isEmpty) break;

      // Prefer underrepresented formats, then underrepresented units.
      // A depleted format still constrains the others: never pad a shortage
      // with only choice questions. The displayed counts differ by at most one.
      types.sort((a, b) => typeCounts[a]!.compareTo(typeCounts[b]!));
      final chosenType = types.first;
      final matchingUnits = units
          .where(
            (id) => byType[chosenType]![id]!.isNotEmpty,
          )
          .toList(growable: false);
      matchingUnits.sort((a, b) => unitCounts[a]!.compareTo(unitCounts[b]!));
      final unit = matchingUnits.first;
      result.add(byType[chosenType]![unit]!.removeLast());
      typeCounts[chosenType] = typeCounts[chosenType]! + 1;
      unitCounts[unit] = unitCounts[unit]! + 1;
    }
    result.shuffle(rng);
    return List.unmodifiable(result);
  }

  int availableCount({
    required Iterable<ExamQuestion> accessibleQuestions,
    required Set<String> selectedUnitIds,
  }) {
    final counts = availableCountsByType(
        accessibleQuestions: accessibleQuestions,
        selectedUnitIds: selectedUnitIds);
    if (counts.isEmpty) return 0;
    final limit = counts.values.reduce(min) + 1;
    return counts.values.fold(0, (sum, count) => sum + min(count, limit));
  }

  /// Counts unique eligible items, using the same deduplication as selection.
  Map<ExamQuestionType, int> availableCountsByType({
    required Iterable<ExamQuestion> accessibleQuestions,
    required Set<String> selectedUnitIds,
  }) {
    // Pure O(n) count; never run the full selection algorithm during rebuild.
    final ids = <String>{};
    final prompts = <String>{};
    final counts = <ExamQuestionType, int>{};
    for (final q in accessibleQuestions) {
      if (!selectedUnitIds.contains(q.unitId) ||
          !ids.add(q.id) ||
          !prompts.add(q.question.trim())) {
        continue;
      }
      counts.update(q.type, (n) => n + 1, ifAbsent: () => 1);
    }
    return Map.unmodifiable(counts);
  }
}
