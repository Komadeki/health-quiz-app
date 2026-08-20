import 'dart:convert';

import 'package:drone_second_class/src/domain/panel_assignment.dart';
import 'package:drone_second_class/src/domain/panel_route.dart';
import 'package:drone_second_class/src/presentation/panel_runner_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reference assignment compiles the same exact 28-question route',
      () async {
    final bundle = await loadValidationBundle();
    final assignment = PanelAssignmentV1.fromJson(
      (jsonDecode(referenceAssignmentJson)! as Map).cast<String, Object?>(),
    );
    final compiler = PanelRouteCompiler(bundle);
    final first = compiler.compile(assignment);
    final second = compiler.compile(
      PanelAssignmentV1.fromJson(assignment.toJson()),
    );

    expect(first.entries, hasLength(28));
    expect(
      first.routeHash,
      'sha256:2f1771fa83d118d61b25891ad0ac3c8727e0717c5d76bf336365e23120131947',
    );
    expect(first.questionIds, second.questionIds);
    expect(first.routeHash, second.routeHash);
    expect(
      first.entries.where((entry) => entry.phase == PanelPhase.observed),
      hasLength(13),
    );
    expect(
      first.entries.where((entry) => entry.phase == PanelPhase.heldOut),
      hasLength(8),
    );
    expect(
      first.entries.where((entry) => entry.phase == PanelPhase.replication),
      hasLength(1),
    );
    expect(
      first.entries.where((entry) => entry.phase == PanelPhase.sentinel),
      hasLength(4),
    );
    expect(
      first.entries.where(
        (entry) => entry.phase == PanelPhase.remainingCoverage,
      ),
      hasLength(2),
    );
    expect(
      first.entries
          .where((entry) => entry.analysisGroup == 'HB-2')
          .every((entry) => entry.partialCounterbalance),
      isTrue,
    );
    expect(
      first.entries
          .singleWhere((entry) => entry.analysisGroup == 'COV-52')
          .routeClass,
      'NON_THERMAL_FOG',
    );
    for (final pair in const <List<String>>[
      <String>['VS-002', 'VS-003'],
      <String>['VS-005', 'VS-006'],
      <String>['VS-007', 'VS-009'],
      <String>['VS-012', 'VS-014'],
    ]) {
      expect(
        first.entries.where((entry) => pair.contains(entry.slotId)).length,
        lessThanOrEqualTo(1),
      );
    }
    expect(
      first.questionIds.any(
        (id) => int.parse(id.split('-').last) > 100,
      ),
      isFalse,
    );
  });

  test('Group B reverses only the specified roles and keeps M3 H5 fixed',
      () async {
    final bundle = await loadValidationBundle();
    final assignment = PanelAssignmentV1(
      assignmentId: 'assignment-b',
      participantId: 'participant-b',
      assignmentGroup: AssignmentGroup.b,
      routeVersion: 'route-b-v1',
      deepTargetIds: const <String>[
        'HAZARD_RISK_M3',
        'THIRD_PARTY',
        'GNSS',
        'AUTO_MANUAL',
        'TEM',
      ],
      breadthGroupIds: const <String>[],
      sentinelIds: const <String>[],
      coverageIds: const <String>[],
      preS1CoverageIds: const <String>[],
      replicationForm: ReplicationForm.b,
      alternateSlotSelections: const <String, String>{
        'VS-002': 'VS-003',
        'VS-005': 'VS-006',
        'VS-007': 'VS-009',
        'VS-012': 'VS-014',
      },
      coverageRouteClasses: const <String, String>{},
    );
    final route = PanelRouteCompiler(bundle).compile(assignment);
    Set<String> groups(PanelPhase phase) => route.entries
        .where((entry) => entry.phase == phase)
        .map((entry) => entry.analysisGroup)
        .toSet();

    expect(
      groups(PanelPhase.observed),
      containsAll(
          <String>{'H1', 'H2', 'T1', 'T3', 'G2', 'G3', 'A2', 'A3', 'E1', 'E3'}),
    );
    expect(
      groups(PanelPhase.heldOut),
      containsAll(<String>{'H5', 'T2', 'G1', 'A1', 'A4', 'E2'}),
    );
    expect(groups(PanelPhase.replication), <String>{'H4'});
  });

  test('invalid pre-S1 exposure and missing COV-52 class fail closed',
      () async {
    final bundle = await loadValidationBundle();
    final compiler = PanelRouteCompiler(bundle);
    final base = smallAssignment(coverage: const <String>['COV-39']);
    final invalidExposure = PanelAssignmentV1.fromJson(<String, Object?>{
      ...base.toJson(),
      'pre_s1_coverage_ids': <String>['COV-39'],
    });
    expect(
      () => compiler.compile(invalidExposure),
      throwsA(isA<FormatException>()),
    );

    final invalidClass = PanelAssignmentV1.fromJson(<String, Object?>{
      ...base.toJson(),
      'coverage_ids': <String>['COV-52'],
    });
    expect(
      () => compiler.compile(invalidClass),
      throwsA(isA<FormatException>()),
    );
  });
}
