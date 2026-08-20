import 'panel_assignment.dart';
import 'panel_route.dart';

const pilotContractVersion = 'drone-second-class-v0p3-pilot-v1';
const pilotRouteVersion = 'drone-second-class-v0p3-route-v1';

enum SentinelSet { s1, s2 }

class PilotAssignmentSlot {
  const PilotAssignmentSlot({
    required this.slotId,
    required this.group,
    required this.rotationId,
    required this.deepTargetIds,
    required this.breadthGroupIds,
    required this.sentinelIds,
    required this.coverageIds,
    required this.preS1CoverageId,
    required this.replicationForm,
    required this.alternateSlotSelections,
    this.coverageRouteClasses = const <String, String>{},
  });

  final String slotId;
  final AssignmentGroup group;
  final String rotationId;
  final List<String> deepTargetIds;
  final List<String> breadthGroupIds;
  final List<String> sentinelIds;
  final List<String> coverageIds;
  final String preS1CoverageId;
  final ReplicationForm? replicationForm;
  final Map<String, String> alternateSlotSelections;
  final Map<String, String> coverageRouteClasses;

  SentinelSet get sentinelSet =>
      sentinelIds.first == 'US-A' ? SentinelSet.s1 : SentinelSet.s2;

  PanelAssignmentV1 assignmentFor(String participantId) {
    return PanelAssignmentV1(
      assignmentId: 'V0P3-$slotId',
      participantId: participantId,
      assignmentGroup: group,
      routeVersion: pilotRouteVersion,
      deepTargetIds: deepTargetIds,
      breadthGroupIds: breadthGroupIds,
      sentinelIds: sentinelIds,
      coverageIds: coverageIds,
      preS1CoverageIds: <String>[preS1CoverageId],
      replicationForm: replicationForm,
      alternateSlotSelections: alternateSlotSelections,
      coverageRouteClasses: coverageRouteClasses,
      assignmentSlotId: slotId,
      pilotContractVersion: pilotContractVersion,
      rotationId: rotationId,
    );
  }
}

class PilotProfileMetrics {
  const PilotProfileMetrics({
    required this.groupCounts,
    required this.deepCounts,
    required this.breadthCounts,
    required this.sentinelCounts,
    required this.coverageUnion,
    required this.replicationFormCounts,
    required this.alternateExposureCounts,
  });

  final Map<String, int> groupCounts;
  final Map<String, int> deepCounts;
  final Map<String, int> breadthCounts;
  final Map<String, int> sentinelCounts;
  final Set<String> coverageUnion;
  final Map<String, int> replicationFormCounts;
  final Map<String, Map<String, int>> alternateExposureCounts;
}

class DroneV0P3PilotProfile {
  const DroneV0P3PilotProfile();

  static final participantIdPattern = RegExp(r'^V0P3-[IE][0-9]{3}$');

  static const s1Sentinels = <String>['US-A', 'US-B', 'US-C', 'US-D'];
  static const s2Sentinels = <String>['US-E', 'US-F', 'US-G', 'US-H'];

  static const slots = <PilotAssignmentSlot>[
    PilotAssignmentSlot(
      slotId: 'EXT-S01',
      group: AssignmentGroup.a,
      rotationId: 'R1',
      deepTargetIds: <String>['HAZARD_RISK_M3', 'THIRD_PARTY'],
      breadthGroupIds: <String>['HB-1', 'HB-2', 'HB-3'],
      sentinelIds: s1Sentinels,
      coverageIds: <String>[
        'COV-01',
        'COV-02',
        'COV-03',
        'COV-04',
        'COV-05',
        'COV-06',
        'COV-07',
        'COV-08',
        'COV-25',
        'COV-39',
      ],
      preS1CoverageId: 'COV-25',
      replicationForm: ReplicationForm.a,
      alternateSlotSelections: <String, String>{
        'VS-002': 'VS-002',
        'VS-005': 'VS-005',
      },
    ),
    PilotAssignmentSlot(
      slotId: 'EXT-S02',
      group: AssignmentGroup.b,
      rotationId: 'R2',
      deepTargetIds: <String>['GNSS', 'AUTO_MANUAL'],
      breadthGroupIds: <String>['HB-4', 'HB-5', 'HB-6'],
      sentinelIds: s2Sentinels,
      coverageIds: <String>[
        'COV-09',
        'COV-10',
        'COV-11',
        'COV-12',
        'COV-13',
        'COV-14',
        'COV-15',
        'COV-16',
        'COV-17',
        'COV-37',
      ],
      preS1CoverageId: 'COV-37',
      replicationForm: null,
      alternateSlotSelections: <String, String>{'VS-007': 'VS-007'},
    ),
    PilotAssignmentSlot(
      slotId: 'EXT-S03',
      group: AssignmentGroup.a,
      rotationId: 'R3',
      deepTargetIds: <String>['HAZARD_RISK_M3', 'TEM'],
      breadthGroupIds: <String>['HB-7', 'HB-1', 'HB-4'],
      sentinelIds: s1Sentinels,
      coverageIds: <String>[
        'COV-18',
        'COV-19',
        'COV-20',
        'COV-21',
        'COV-22',
        'COV-23',
        'COV-24',
        'COV-25',
        'COV-39',
        'COV-40',
      ],
      preS1CoverageId: 'COV-25',
      replicationForm: ReplicationForm.b,
      alternateSlotSelections: <String, String>{
        'VS-002': 'VS-003',
        'VS-012': 'VS-012',
      },
    ),
    PilotAssignmentSlot(
      slotId: 'EXT-S04',
      group: AssignmentGroup.b,
      rotationId: 'R4',
      deepTargetIds: <String>['THIRD_PARTY', 'GNSS'],
      breadthGroupIds: <String>['HB-2', 'HB-5', 'HB-7'],
      sentinelIds: s2Sentinels,
      coverageIds: <String>[
        'COV-26',
        'COV-27',
        'COV-28',
        'COV-29',
        'COV-30',
        'COV-31',
        'COV-32',
        'COV-33',
        'COV-34',
        'COV-37',
      ],
      preS1CoverageId: 'COV-37',
      replicationForm: null,
      alternateSlotSelections: <String, String>{
        'VS-005': 'VS-005',
        'VS-007': 'VS-009',
      },
    ),
    PilotAssignmentSlot(
      slotId: 'EXT-S05',
      group: AssignmentGroup.a,
      rotationId: 'R5',
      deepTargetIds: <String>['AUTO_MANUAL', 'TEM'],
      breadthGroupIds: <String>['HB-3', 'HB-6', 'HB-7'],
      sentinelIds: s2Sentinels,
      coverageIds: <String>[
        'COV-35',
        'COV-36',
        'COV-37',
        'COV-38',
        'COV-41',
        'COV-42',
        'COV-43',
        'COV-44',
        'COV-45',
        'COV-46',
      ],
      preS1CoverageId: 'COV-37',
      replicationForm: null,
      alternateSlotSelections: <String, String>{'VS-012': 'VS-014'},
    ),
    PilotAssignmentSlot(
      slotId: 'EXT-S06',
      group: AssignmentGroup.b,
      rotationId: 'R1',
      deepTargetIds: <String>['HAZARD_RISK_M3', 'THIRD_PARTY'],
      breadthGroupIds: <String>['HB-1', 'HB-2', 'HB-3'],
      sentinelIds: s1Sentinels,
      coverageIds: <String>[
        'COV-25',
        'COV-39',
        'COV-47',
        'COV-48',
        'COV-49',
        'COV-50',
        'COV-51',
        'COV-52',
        'COV-53',
        'COV-54',
      ],
      preS1CoverageId: 'COV-25',
      replicationForm: ReplicationForm.a,
      alternateSlotSelections: <String, String>{
        'VS-002': 'VS-002',
        'VS-005': 'VS-006',
      },
      coverageRouteClasses: <String, String>{'COV-52': 'NON_THERMAL_FOG'},
    ),
    PilotAssignmentSlot(
      slotId: 'EXT-S07',
      group: AssignmentGroup.a,
      rotationId: 'R2',
      deepTargetIds: <String>['GNSS', 'AUTO_MANUAL'],
      breadthGroupIds: <String>['HB-4', 'HB-5', 'HB-6'],
      sentinelIds: s2Sentinels,
      coverageIds: <String>[
        'COV-01',
        'COV-09',
        'COV-18',
        'COV-26',
        'COV-35',
        'COV-37',
        'COV-41',
        'COV-47',
        'COV-55',
        'COV-56',
      ],
      preS1CoverageId: 'COV-37',
      replicationForm: null,
      alternateSlotSelections: <String, String>{'VS-007': 'VS-007'},
    ),
    PilotAssignmentSlot(
      slotId: 'EXT-S08',
      group: AssignmentGroup.b,
      rotationId: 'R3',
      deepTargetIds: <String>['HAZARD_RISK_M3', 'TEM'],
      breadthGroupIds: <String>['HB-7', 'HB-1', 'HB-4'],
      sentinelIds: s1Sentinels,
      coverageIds: <String>[
        'COV-02',
        'COV-10',
        'COV-19',
        'COV-25',
        'COV-27',
        'COV-36',
        'COV-39',
        'COV-42',
        'COV-48',
        'COV-55',
      ],
      preS1CoverageId: 'COV-25',
      replicationForm: ReplicationForm.b,
      alternateSlotSelections: <String, String>{
        'VS-002': 'VS-003',
        'VS-012': 'VS-012',
      },
    ),
    PilotAssignmentSlot(
      slotId: 'EXT-S09',
      group: AssignmentGroup.a,
      rotationId: 'R4',
      deepTargetIds: <String>['THIRD_PARTY', 'GNSS'],
      breadthGroupIds: <String>['HB-2', 'HB-5', 'HB-7'],
      sentinelIds: s2Sentinels,
      coverageIds: <String>[
        'COV-03',
        'COV-11',
        'COV-20',
        'COV-28',
        'COV-37',
        'COV-38',
        'COV-43',
        'COV-49',
        'COV-53',
        'COV-56',
      ],
      preS1CoverageId: 'COV-37',
      replicationForm: null,
      alternateSlotSelections: <String, String>{
        'VS-005': 'VS-006',
        'VS-007': 'VS-009',
      },
    ),
    PilotAssignmentSlot(
      slotId: 'EXT-S10',
      group: AssignmentGroup.b,
      rotationId: 'R5',
      deepTargetIds: <String>['AUTO_MANUAL', 'TEM'],
      breadthGroupIds: <String>['HB-3', 'HB-6', 'HB-7'],
      sentinelIds: s2Sentinels,
      coverageIds: <String>[
        'COV-04',
        'COV-12',
        'COV-21',
        'COV-29',
        'COV-37',
        'COV-40',
        'COV-44',
        'COV-50',
        'COV-52',
        'COV-54',
      ],
      preS1CoverageId: 'COV-37',
      replicationForm: null,
      alternateSlotSelections: <String, String>{'VS-012': 'VS-014'},
      coverageRouteClasses: <String, String>{'COV-52': 'NON_THERMAL_FOG'},
    ),
  ];

  PilotAssignmentSlot slot(String slotId) => slots.singleWhere(
        (item) => item.slotId == slotId,
        orElse: () => throw FormatException('Unknown assignment slot: $slotId'),
      );

  PanelAssignmentV1 assignment({
    required String slotId,
    required String participantId,
  }) {
    final normalizedParticipantId = participantId.trim().toUpperCase();
    if (!participantIdPattern.hasMatch(normalizedParticipantId)) {
      throw const FormatException(
        'participant_id must match V0P3-Ixxx or V0P3-Exxx.',
      );
    }
    if (normalizedParticipantId == slotId) {
      throw const FormatException(
        'participant_id and assignment_slot_id must be different.',
      );
    }
    final result = slot(slotId).assignmentFor(normalizedParticipantId);
    validateAssignment(result);
    return result;
  }

  void validateAssignment(PanelAssignmentV1 assignment) {
    if (!participantIdPattern.hasMatch(assignment.participantId) ||
        assignment.participantId == assignment.assignmentSlotId) {
      throw const FormatException('Pilot participant_id is invalid.');
    }
    if (assignment.pilotContractVersion != pilotContractVersion ||
        assignment.routeVersion != pilotRouteVersion) {
      throw const FormatException('Unknown V0P-3 Pilot profile version.');
    }
    if (assignment.deepTargetIds.length != 2) {
      throw const FormatException('Pilot Deep Targets must equal 2.');
    }
    if (assignment.breadthGroupIds.length != 3) {
      throw const FormatException('Pilot Breadth Groups must equal 3.');
    }
    if (assignment.sentinelIds.length != 4) {
      throw const FormatException('Pilot Sentinels must equal 4.');
    }
    if (assignment.coverageIds.length != 10) {
      throw const FormatException('Pilot Coverage must equal 10.');
    }
    if (assignment.preS1CoverageIds.length != 1) {
      throw const FormatException('Pilot pre-S1 Coverage must equal 1.');
    }
    final expected = slot(assignment.assignmentSlotId ?? '');
    final expectedJson =
        expected.assignmentFor(assignment.participantId).toJson();
    if (!_samePilotAssignment(expectedJson, assignment.toJson())) {
      throw const FormatException('Pilot assignment differs from fixed slot.');
    }
    final isS1 = _sameStrings(assignment.sentinelIds, s1Sentinels);
    final isS2 = _sameStrings(assignment.sentinelIds, s2Sentinels);
    if (!isS1 && !isS2) {
      throw const FormatException('Pilot Sentinel quartet is invalid.');
    }
    final expectedPreS1 = isS1 ? 'COV-25' : 'COV-37';
    if (assignment.preS1CoverageIds.single != expectedPreS1) {
      throw FormatException('$expectedPreS1 is required before S1.');
    }
    if (isS1 &&
        (!assignment.coverageIds.contains('COV-39') ||
            assignment.preS1CoverageIds.contains('COV-39'))) {
      throw const FormatException(
        'S1 quartet requires COV-39 as Remaining Coverage.',
      );
    }
    if (assignment.deepTargetIds.contains('HAZARD_RISK_M3') &&
        assignment.sentinelIds.contains('US-G')) {
      throw const FormatException('HAZARD_RISK_M3 cannot contain US-G.');
    }
    if (assignment.coverageIds.contains('COV-52') &&
        assignment.coverageRouteClasses['COV-52'] != 'NON_THERMAL_FOG') {
      throw const FormatException('COV-52 requires NON_THERMAL_FOG.');
    }
  }

  PilotProfileMetrics validateFixedSlots() {
    final groupCounts = <String, int>{'A': 0, 'B': 0};
    final deepCounts = <String, int>{
      for (final target in PanelRouteCompiler.deepTargets) target: 0,
    };
    final breadthCounts = <String, int>{
      for (var index = 1; index <= 7; index += 1) 'HB-$index': 0,
    };
    final sentinelCounts = <String, int>{
      for (final id in <String>[...s1Sentinels, ...s2Sentinels]) id: 0,
    };
    final coverageUnion = <String>{};
    final formCounts = <String, int>{'A': 0, 'B': 0};
    final alternates = <String, Map<String, int>>{
      for (final id in <String>['VS-002', 'VS-005', 'VS-007', 'VS-012'])
        id: <String, int>{
          'Primary': 0,
          'Alternate': 0,
          'A Primary': 0,
          'A Alternate': 0,
          'B Primary': 0,
          'B Alternate': 0,
        },
    };

    for (final fixed in slots) {
      final assignment = fixed.assignmentFor('V0P3-I001');
      validateAssignment(assignment);
      final group = fixed.group == AssignmentGroup.a ? 'A' : 'B';
      groupCounts[group] = groupCounts[group]! + 1;
      for (final id in fixed.deepTargetIds) {
        deepCounts[id] = deepCounts[id]! + 1;
      }
      for (final id in fixed.breadthGroupIds) {
        breadthCounts[id] = breadthCounts[id]! + 1;
      }
      for (final id in fixed.sentinelIds) {
        sentinelCounts[id] = sentinelCounts[id]! + 1;
      }
      coverageUnion.addAll(fixed.coverageIds);
      if (fixed.replicationForm != null) {
        final form = fixed.replicationForm == ReplicationForm.a ? 'A' : 'B';
        formCounts[form] = formCounts[form]! + 1;
      }
      for (final selection in fixed.alternateSlotSelections.entries) {
        final type = selection.key == selection.value ? 'Primary' : 'Alternate';
        alternates[selection.key]![type] =
            alternates[selection.key]![type]! + 1;
        alternates[selection.key]!['$group $type'] =
            alternates[selection.key]!['$group $type']! + 1;
      }
    }

    if (groupCounts['A'] != 5 || groupCounts['B'] != 5) {
      throw const FormatException('Pilot Group aggregate must be A/B = 5/5.');
    }
    if (deepCounts.values.any((count) => count != 4)) {
      throw const FormatException('Each Deep Target must occur 4 times.');
    }
    if (formCounts['A'] != 2 || formCounts['B'] != 2) {
      throw const FormatException('M3 Form aggregate must be A/B = 2/2.');
    }
    if (breadthCounts.values.any((count) => count < 4)) {
      throw const FormatException('Each Breadth Group needs 4 exposures.');
    }
    if (sentinelCounts.values.any((count) => count < 4)) {
      throw const FormatException('Each Sentinel needs 4 exposures.');
    }
    final expectedCoverage = <String>{
      for (var index = 1; index <= 56; index += 1)
        'COV-${index.toString().padLeft(2, '0')}',
    };
    if (coverageUnion.length != 56 ||
        !coverageUnion.containsAll(expectedCoverage)) {
      throw const FormatException('Coverage union must equal COV-01..COV-56.');
    }
    for (final counts in alternates.values) {
      if (counts['Primary'] != 2 ||
          counts['Alternate'] != 2 ||
          counts['A Primary'] != 1 ||
          counts['A Alternate'] != 1 ||
          counts['B Primary'] != 1 ||
          counts['B Alternate'] != 1) {
        throw const FormatException('Alternate exposure balance is invalid.');
      }
    }
    return PilotProfileMetrics(
      groupCounts: Map<String, int>.unmodifiable(groupCounts),
      deepCounts: Map<String, int>.unmodifiable(deepCounts),
      breadthCounts: Map<String, int>.unmodifiable(breadthCounts),
      sentinelCounts: Map<String, int>.unmodifiable(sentinelCounts),
      coverageUnion: Set<String>.unmodifiable(coverageUnion),
      replicationFormCounts: Map<String, int>.unmodifiable(formCounts),
      alternateExposureCounts: Map<String, Map<String, int>>.unmodifiable(
        alternates.map(
          (key, value) => MapEntry(key, Map<String, int>.unmodifiable(value)),
        ),
      ),
    );
  }
}

bool _samePilotAssignment(
  Map<String, Object?> expected,
  Map<String, Object?> actual,
) {
  for (final key in expected.keys) {
    if (key == 'participant_id') continue;
    final left = expected[key];
    final right = actual[key];
    if (left is List && right is List) {
      if (!_sameObjects(left, right)) return false;
    } else if (left is Map && right is Map) {
      if (!_sameMaps(left, right)) return false;
    } else if (left != right) {
      return false;
    }
  }
  return true;
}

bool _sameObjects(List<Object?> left, List<Object?> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

bool _sameMaps(Map<Object?, Object?> left, Map<Object?, Object?> right) {
  if (left.length != right.length) return false;
  for (final key in left.keys) {
    if (left[key] != right[key]) return false;
  }
  return true;
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
