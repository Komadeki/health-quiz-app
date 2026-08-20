import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'panel_assignment.dart';
import 'validation_bundle.dart';
import 'validation_provenance.dart';

enum PanelPhase {
  observed,
  predictionGate,
  heldOut,
  replication,
  sentinel,
  explanation,
  remainingCoverage,
  complete,
}

extension PanelPhaseWire on PanelPhase {
  String get wireName => switch (this) {
        PanelPhase.observed => 'OBSERVED',
        PanelPhase.predictionGate => 'PREDICTION_GATE',
        PanelPhase.heldOut => 'HELD_OUT',
        PanelPhase.replication => 'REPLICATION',
        PanelPhase.sentinel => 'SENTINEL',
        PanelPhase.explanation => 'EXPLANATION',
        PanelPhase.remainingCoverage => 'REMAINING_COVERAGE',
        PanelPhase.complete => 'COMPLETE',
      };

  static PanelPhase parse(String value) => PanelPhase.values.firstWhere(
        (phase) => phase.wireName == value,
        orElse: () => throw FormatException('Unknown phase: $value'),
      );
}

class PanelRouteEntry {
  const PanelRouteEntry({
    required this.questionId,
    required this.slotId,
    required this.phase,
    required this.assignmentRole,
    required this.analysisGroup,
    required this.measurement,
    required this.partialCounterbalance,
    required this.routeClass,
  });

  final String questionId;
  final String slotId;
  final PanelPhase phase;
  final String assignmentRole;
  final String analysisGroup;
  final bool measurement;
  final bool partialCounterbalance;
  final String? routeClass;

  Map<String, Object?> toJson() => <String, Object?>{
        'question_id': questionId,
        'slot_id': slotId,
        'phase': phase.wireName,
        'assignment_role': assignmentRole,
        'analysis_group': analysisGroup,
        'measurement': measurement,
        'partial_counterbalance': partialCounterbalance,
        'route_class': routeClass,
      };

  factory PanelRouteEntry.fromJson(Map<String, Object?> json) {
    return PanelRouteEntry(
      questionId: json['question_id']! as String,
      slotId: json['slot_id']! as String,
      phase: PanelPhaseWire.parse(json['phase']! as String),
      assignmentRole: json['assignment_role']! as String,
      analysisGroup: json['analysis_group']! as String,
      measurement: json['measurement']! as bool,
      partialCounterbalance: json['partial_counterbalance']! as bool,
      routeClass: json['route_class'] as String?,
    );
  }
}

class PanelRoute {
  const PanelRoute({required this.entries, required this.routeHash});

  final List<PanelRouteEntry> entries;
  final String routeHash;

  List<String> get questionIds =>
      entries.map((entry) => entry.questionId).toList(growable: false);

  Map<String, Object?> toJson() => <String, Object?>{
        'entries':
            entries.map((entry) => entry.toJson()).toList(growable: false),
        'route_hash': routeHash,
      };

  factory PanelRoute.fromJson(Map<String, Object?> json) {
    final entries = (json['entries']! as List)
        .map(
          (item) => PanelRouteEntry.fromJson(
            (item! as Map).cast<String, Object?>(),
          ),
        )
        .toList(growable: false);
    final route = PanelRoute(
      entries: entries,
      routeHash: json['route_hash']! as String,
    );
    if (PanelRouteCompiler.hashEntries(entries) != route.routeHash) {
      throw const FormatException(
          'Stored route hash does not match its route.');
    }
    return route;
  }
}

class PanelRouteCompiler {
  const PanelRouteCompiler(this.bundle);

  final ValidationBundle bundle;

  static const deepTargets = <String>{
    'HAZARD_RISK_M3',
    'THIRD_PARTY',
    'GNSS',
    'AUTO_MANUAL',
    'TEM',
  };

  PanelRoute compile(PanelAssignmentV1 assignment) {
    _validateAssignment(assignment);
    final entries = <PanelRouteEntry>[];
    final observed = <PanelRouteEntry>[];
    final heldOut = <PanelRouteEntry>[];
    final replication = <PanelRouteEntry>[];

    void addDeep(
      List<PanelRouteEntry> target,
      String group,
      PanelPhase phase,
    ) {
      final question = _questionForGroup(group, assignment);
      target.add(
        _entry(
          question,
          phase,
          phase == PanelPhase.observed ? 'DEEP_OBSERVED' : 'DEEP_HELD_OUT',
          group,
          measurement: true,
        ),
      );
    }

    for (final target in assignment.deepTargetIds) {
      switch (target) {
        case 'HAZARD_RISK_M3':
          addDeep(observed, 'H1', PanelPhase.observed);
          addDeep(observed, 'H2', PanelPhase.observed);
          addDeep(heldOut, 'H5', PanelPhase.heldOut);
          final form = assignment.replicationForm!;
          final group = form == ReplicationForm.a ? 'H3' : 'H4';
          final question = _questionForGroup(group, assignment);
          replication.add(
            _entry(
              question,
              PanelPhase.replication,
              'DEEP_REPLICATION_${form == ReplicationForm.a ? 'A' : 'B'}',
              group,
              measurement: true,
            ),
          );
        case 'THIRD_PARTY':
          addDeep(observed, 'T1', PanelPhase.observed);
          if (assignment.assignmentGroup == AssignmentGroup.a) {
            addDeep(observed, 'T2', PanelPhase.observed);
            addDeep(heldOut, 'T3', PanelPhase.heldOut);
          } else {
            addDeep(observed, 'T3', PanelPhase.observed);
            addDeep(heldOut, 'T2', PanelPhase.heldOut);
          }
        case 'GNSS':
          if (assignment.assignmentGroup == AssignmentGroup.a) {
            addDeep(observed, 'G1', PanelPhase.observed);
            addDeep(observed, 'G2', PanelPhase.observed);
            addDeep(heldOut, 'G3', PanelPhase.heldOut);
          } else {
            addDeep(observed, 'G2', PanelPhase.observed);
            addDeep(observed, 'G3', PanelPhase.observed);
            addDeep(heldOut, 'G1', PanelPhase.heldOut);
          }
        case 'AUTO_MANUAL':
          final observedGroups = assignment.assignmentGroup == AssignmentGroup.a
              ? const <String>['A1', 'A4']
              : const <String>['A2', 'A3'];
          final heldGroups = assignment.assignmentGroup == AssignmentGroup.a
              ? const <String>['A2', 'A3']
              : const <String>['A1', 'A4'];
          for (final group in observedGroups) {
            addDeep(observed, group, PanelPhase.observed);
          }
          for (final group in heldGroups) {
            addDeep(heldOut, group, PanelPhase.heldOut);
          }
        case 'TEM':
          addDeep(observed, 'E1', PanelPhase.observed);
          if (assignment.assignmentGroup == AssignmentGroup.a) {
            addDeep(observed, 'E2', PanelPhase.observed);
            addDeep(heldOut, 'E3', PanelPhase.heldOut);
          } else {
            addDeep(observed, 'E3', PanelPhase.observed);
            addDeep(heldOut, 'E2', PanelPhase.heldOut);
          }
      }
    }

    _compileBreadth(assignment, observed, heldOut);
    for (final coverageId in assignment.preS1CoverageIds) {
      observed.add(
        _entry(
          bundle.questionsByCoverage[coverageId]!,
          PanelPhase.observed,
          'PRE_S1_COVERAGE',
          coverageId,
          measurement: false,
          routeClass: assignment.coverageRouteClasses[coverageId],
        ),
      );
    }
    entries.addAll(_ordered(observed, assignment));
    entries.addAll(_ordered(heldOut, assignment));
    entries.addAll(_ordered(replication, assignment));

    final sentinels = assignment.sentinelIds
        .map(
          (id) => _entry(
            bundle.questionsBySentinel[id]!,
            PanelPhase.sentinel,
            'UNKNOWN_SENTINEL',
            id,
            measurement: false,
          ),
        )
        .toList(growable: false);
    entries.addAll(_ordered(sentinels, assignment));

    final remainingCoverage = assignment.coverageIds
        .where((id) => !assignment.preS1CoverageIds.contains(id))
        .map(
          (id) => _entry(
            bundle.questionsByCoverage[id]!,
            PanelPhase.remainingCoverage,
            'COVERAGE',
            id,
            measurement: false,
            routeClass: assignment.coverageRouteClasses[id],
          ),
        )
        .toList(growable: false);
    entries.addAll(_ordered(remainingCoverage, assignment));

    final ids = entries.map((entry) => entry.questionId).toList();
    if (ids.toSet().length != ids.length) {
      throw const FormatException(
          'A participant route cannot repeat a question.');
    }
    return PanelRoute(
      entries: List<PanelRouteEntry>.unmodifiable(entries),
      routeHash: hashEntries(entries),
    );
  }

  void _compileBreadth(
    PanelAssignmentV1 assignment,
    List<PanelRouteEntry> observed,
    List<PanelRouteEntry> heldOut,
  ) {
    final breadth = (bundle.protocol['breadth_measurements']! as List)
        .map((item) => (item! as Map).cast<String, Object?>())
        .toList(growable: false);
    for (final groupId in assignment.breadthGroupIds) {
      final contract = breadth.firstWhere(
        (item) => item['contamination_group'] == groupId,
      );
      final swap = assignment.assignmentGroup == AssignmentGroup.b;
      final observedSlot = (swap
          ? contract['heldout_slot_id']
          : contract['observed_slot_id'])! as String;
      final heldSlot = (swap
          ? contract['observed_slot_id']
          : contract['heldout_slot_id'])! as String;
      final partial = contract['counterbalance'] == 'PARTIAL_ONLY';
      observed.add(
        _entry(
          bundle.questionsBySlot[observedSlot]!,
          PanelPhase.observed,
          'BREADTH_OBSERVED',
          groupId,
          measurement: true,
          partialCounterbalance: partial,
        ),
      );
      heldOut.add(
        _entry(
          bundle.questionsBySlot[heldSlot]!,
          PanelPhase.heldOut,
          'BREADTH_HELD_OUT',
          groupId,
          measurement: true,
          partialCounterbalance: partial,
        ),
      );
    }
  }

  void _validateAssignment(PanelAssignmentV1 assignment) {
    final invalidTargets =
        assignment.deepTargetIds.toSet().difference(deepTargets);
    if (invalidTargets.isNotEmpty) {
      throw FormatException('Unknown deep target IDs: $invalidTargets');
    }
    if (assignment.deepTargetIds.isEmpty &&
        assignment.breadthGroupIds.isEmpty) {
      throw const FormatException(
          'At least one measurement target is required.');
    }
    if (assignment.deepTargetIds.contains('HAZARD_RISK_M3') !=
        (assignment.replicationForm != null)) {
      throw const FormatException(
        'replication_form is required only when HAZARD_RISK_M3 is assigned.',
      );
    }
    const breadthIds = <String>{
      'HB-1',
      'HB-2',
      'HB-3',
      'HB-4',
      'HB-5',
      'HB-6',
      'HB-7',
    };
    if (assignment.breadthGroupIds.toSet().difference(breadthIds).isNotEmpty) {
      throw const FormatException('Unknown breadth group ID.');
    }
    if (assignment.sentinelIds.any(
      (id) => !bundle.questionsBySentinel.containsKey(id),
    )) {
      throw const FormatException('Unknown Sentinel ID.');
    }
    if (assignment.coverageIds.any(
      (id) => !bundle.questionsByCoverage.containsKey(id),
    )) {
      throw const FormatException('Unknown coverage ID.');
    }
    if (!assignment.coverageIds
        .toSet()
        .containsAll(assignment.preS1CoverageIds)) {
      throw const FormatException(
          'pre_s1_coverage_ids must be assigned coverage.');
    }
    for (final coverageId in assignment.preS1CoverageIds) {
      if (!_isAllowedPreS1Reference(coverageId, assignment.sentinelIds)) {
        throw FormatException(
            '$coverageId is not an allowed pre-S1 reference.');
      }
    }
    if (assignment.coverageIds.contains('COV-52') &&
        assignment.coverageRouteClasses['COV-52'] != 'NON_THERMAL_FOG') {
      throw const FormatException(
        'COV-52 requires coverage_route_classes.COV-52 = NON_THERMAL_FOG.',
      );
    }
  }

  bool _isAllowedPreS1Reference(String coverageId, List<String> sentinelIds) {
    final sentinelContracts = (bundle.protocol['sentinels']! as List)
        .map((item) => (item! as Map).cast<String, Object?>())
        .where((item) => sentinelIds.contains(item['sentinel_id']));
    for (final sentinel in sentinelContracts) {
      final constraints = (sentinel['routing_constraints']! as List)
          .map((item) => (item! as Map).cast<String, Object?>());
      for (final constraint in constraints) {
        final type = constraint['constraint_type'];
        if (constraint['reference_id'] == coverageId &&
            (type == 'EXPOSURE_ALLOWED' || type == 'CLEAN_NEIGHBOR_REQUIRED')) {
          return true;
        }
      }
    }
    return false;
  }

  ValidationQuestion _questionForGroup(
    String group,
    PanelAssignmentV1 assignment,
  ) {
    final candidates = bundle.questions
        .where((question) => question.contaminationGroup == group)
        .toList(growable: false);
    if (candidates.length == 1) return candidates.single;
    final canonical = candidates.firstWhere(
      (question) => question.alternateOf == null,
    );
    final selectedSlot = assignment.alternateSlotSelections[canonical.slotId];
    if (selectedSlot == null ||
        !candidates.any((question) => question.slotId == selectedSlot)) {
      throw FormatException(
        'alternate_slot_selections.${canonical.slotId} must explicitly select '
        'one same-family slot.',
      );
    }
    return candidates.firstWhere((question) => question.slotId == selectedSlot);
  }

  PanelRouteEntry _entry(
    ValidationQuestion question,
    PanelPhase phase,
    String role,
    String group, {
    required bool measurement,
    bool partialCounterbalance = false,
    String? routeClass,
  }) {
    return PanelRouteEntry(
      questionId: question.questionId,
      slotId: question.slotId,
      phase: phase,
      assignmentRole: role,
      analysisGroup: group,
      measurement: measurement,
      partialCounterbalance: partialCounterbalance,
      routeClass: routeClass,
    );
  }

  List<PanelRouteEntry> _ordered(
    List<PanelRouteEntry> entries,
    PanelAssignmentV1 assignment,
  ) {
    final result = List<PanelRouteEntry>.of(entries);
    result.sort((left, right) {
      String key(PanelRouteEntry entry) => sha256
          .convert(
            utf8.encode(
              '${assignment.participantId}${assignment.assignmentId}'
              '${assignment.routeVersion}${entry.phase.wireName}'
              '${entry.questionId}',
            ),
          )
          .toString();
      return key(left).compareTo(key(right));
    });
    return result;
  }

  static String hashEntries(List<PanelRouteEntry> entries) {
    return canonicalSha256(
      entries.map((entry) => entry.toJson()).toList(growable: false),
    );
  }
}
