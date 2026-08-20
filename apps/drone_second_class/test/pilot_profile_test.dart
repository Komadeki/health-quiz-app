import 'package:drone_second_class/src/domain/panel_assignment.dart';
import 'package:drone_second_class/src/domain/panel_route.dart';
import 'package:drone_second_class/src/domain/pilot_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profile = DroneV0P3PilotProfile();

  PanelAssignmentV1 mutate(
    PanelAssignmentV1 source,
    String key,
    Object? value,
  ) {
    return PanelAssignmentV1.fromJson(<String, Object?>{
      ...source.toJson(),
      key: value,
    });
  }

  test('AT-01..05 Pilot Profile rejects non-exact per-slot counts', () {
    final assignment = profile.assignment(
      slotId: 'EXT-S01',
      participantId: 'V0P3-E011',
    );
    for (final mutation in <PanelAssignmentV1>[
      mutate(assignment, 'deep_target_ids', <String>['HAZARD_RISK_M3']),
      mutate(assignment, 'breadth_group_ids', <String>['HB-1', 'HB-2']),
      mutate(assignment, 'sentinel_ids', <String>['US-A', 'US-B', 'US-C']),
      mutate(
        assignment,
        'coverage_ids',
        assignment.coverageIds.take(9).toList(growable: false),
      ),
      mutate(assignment, 'pre_s1_coverage_ids', const <String>[]),
    ]) {
      expect(() => profile.validateAssignment(mutation), throwsFormatException);
    }
  });

  test('AT-06..11 fixed slots satisfy aggregate exposure contract', () {
    final metrics = profile.validateFixedSlots();

    expect(metrics.groupCounts, <String, int>{'A': 5, 'B': 5});
    expect(
      metrics.deepCounts,
      <String, int>{
        'HAZARD_RISK_M3': 4,
        'THIRD_PARTY': 4,
        'GNSS': 4,
        'AUTO_MANUAL': 4,
        'TEM': 4,
      },
    );
    expect(metrics.replicationFormCounts, <String, int>{'A': 2, 'B': 2});
    expect(
      metrics.breadthCounts,
      <String, int>{
        'HB-1': 4,
        'HB-2': 4,
        'HB-3': 4,
        'HB-4': 4,
        'HB-5': 4,
        'HB-6': 4,
        'HB-7': 6,
      },
    );
    expect(
      metrics.sentinelCounts,
      <String, int>{
        'US-A': 4,
        'US-B': 4,
        'US-C': 4,
        'US-D': 4,
        'US-E': 6,
        'US-F': 6,
        'US-G': 6,
        'US-H': 6,
      },
    );
    expect(metrics.coverageUnion, hasLength(56));
    expect(
      metrics.coverageUnion,
      <String>{
        for (var index = 1; index <= 56; index += 1)
          'COV-${index.toString().padLeft(2, '0')}',
      },
    );
  });

  test('AT-12..16 Sentinel and routed Coverage constraints hold', () async {
    final bundle = await loadValidationBundle();
    final compiler = PanelRouteCompiler(bundle);

    for (final fixed in DroneV0P3PilotProfile.slots) {
      final assignment = profile.assignment(
        slotId: fixed.slotId,
        participantId: 'V0P3-I001',
      );
      final route = compiler.compile(assignment);
      if (assignment.deepTargetIds.contains('HAZARD_RISK_M3')) {
        expect(assignment.sentinelIds, isNot(contains('US-G')));
      }
      final isS1 = assignment.sentinelIds.first == 'US-A';
      expect(
        assignment.preS1CoverageIds,
        <String>[isS1 ? 'COV-25' : 'COV-37'],
      );
      if (isS1) {
        final usB = route.entries.indexWhere(
          (entry) => entry.analysisGroup == 'US-B',
        );
        final cov39 = route.entries.indexWhere(
          (entry) => entry.analysisGroup == 'COV-39',
        );
        expect(usB, greaterThanOrEqualTo(0));
        expect(cov39, greaterThan(usB));
        expect(route.entries[cov39].phase, PanelPhase.remainingCoverage);
      }
      if (assignment.coverageIds.contains('COV-52')) {
        expect(assignment.coverageRouteClasses['COV-52'], 'NON_THERMAL_FOG');
        expect(
          route.entries
              .singleWhere(
                (entry) => entry.analysisGroup == 'COV-52',
              )
              .routeClass,
          'NON_THERMAL_FOG',
        );
      }
    }
  });

  test('AT-17 alternate families are Primary 2 / Alternate 2 across A/B', () {
    final metrics = profile.validateFixedSlots();
    for (final counts in metrics.alternateExposureCounts.values) {
      expect(counts['Primary'], 2);
      expect(counts['Alternate'], 2);
      expect(counts['A Primary'], 1);
      expect(counts['A Alternate'], 1);
      expect(counts['B Primary'], 1);
      expect(counts['B Alternate'], 1);
    }
  });
}
