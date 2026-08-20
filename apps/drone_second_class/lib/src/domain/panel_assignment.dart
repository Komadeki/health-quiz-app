enum AssignmentGroup { a, b }

enum ReplicationForm { a, b }

class PanelAssignmentV1 {
  PanelAssignmentV1({
    required this.assignmentId,
    required this.participantId,
    required this.assignmentGroup,
    required this.routeVersion,
    required this.deepTargetIds,
    required this.breadthGroupIds,
    required this.sentinelIds,
    required this.coverageIds,
    required this.preS1CoverageIds,
    required this.replicationForm,
    required this.alternateSlotSelections,
    required this.coverageRouteClasses,
    this.assignmentSlotId,
    this.pilotContractVersion,
    this.rotationId,
  });

  final String assignmentId;
  final String participantId;
  final AssignmentGroup assignmentGroup;
  final String routeVersion;
  final List<String> deepTargetIds;
  final List<String> breadthGroupIds;
  final List<String> sentinelIds;
  final List<String> coverageIds;
  final List<String> preS1CoverageIds;
  final ReplicationForm? replicationForm;
  final Map<String, String> alternateSlotSelections;
  final Map<String, String> coverageRouteClasses;
  final String? assignmentSlotId;
  final String? pilotContractVersion;
  final String? rotationId;

  factory PanelAssignmentV1.fromJson(Map<String, Object?> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('$key must be a non-empty string.');
      }
      return value.trim();
    }

    List<String> strings(String key) {
      final value = json[key];
      if (value is! List || value.any((item) => item is! String)) {
        throw FormatException('$key must be a string list.');
      }
      final result = value.cast<String>();
      if (result.toSet().length != result.length) {
        throw FormatException('$key must not contain duplicates.');
      }
      return List<String>.unmodifiable(result);
    }

    Map<String, String> stringMap(String key) {
      final value = json[key];
      if (value is! Map ||
          value.keys.any((item) => item is! String) ||
          value.values.any((item) => item is! String)) {
        throw FormatException('$key must be a string map.');
      }
      return Map<String, String>.unmodifiable(value.cast<String, String>());
    }

    final groupValue = requiredString('assignment_group');
    final formValue = json['replication_form'];
    if (formValue != null && formValue != 'A' && formValue != 'B') {
      throw const FormatException('replication_form must be A, B, or null.');
    }
    return PanelAssignmentV1(
      assignmentId: requiredString('assignment_id'),
      participantId: requiredString('participant_id'),
      assignmentGroup: switch (groupValue) {
        'A' => AssignmentGroup.a,
        'B' => AssignmentGroup.b,
        _ => throw const FormatException('assignment_group must be A or B.'),
      },
      routeVersion: requiredString('route_version'),
      deepTargetIds: strings('deep_target_ids'),
      breadthGroupIds: strings('breadth_group_ids'),
      sentinelIds: strings('sentinel_ids'),
      coverageIds: strings('coverage_ids'),
      preS1CoverageIds: strings('pre_s1_coverage_ids'),
      replicationForm: switch (formValue) {
        'A' => ReplicationForm.a,
        'B' => ReplicationForm.b,
        _ => null,
      },
      alternateSlotSelections: stringMap('alternate_slot_selections'),
      coverageRouteClasses: stringMap('coverage_route_classes'),
      assignmentSlotId: json['assignment_slot_id'] as String?,
      pilotContractVersion: json['pilot_contract_version'] as String?,
      rotationId: json['rotation_id'] as String?,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'assignment_id': assignmentId,
    'participant_id': participantId,
    'assignment_group': assignmentGroup == AssignmentGroup.a ? 'A' : 'B',
    'route_version': routeVersion,
    'deep_target_ids': deepTargetIds,
    'breadth_group_ids': breadthGroupIds,
    'sentinel_ids': sentinelIds,
    'coverage_ids': coverageIds,
    'pre_s1_coverage_ids': preS1CoverageIds,
    'replication_form': switch (replicationForm) {
      ReplicationForm.a => 'A',
      ReplicationForm.b => 'B',
      null => null,
    },
    'alternate_slot_selections': alternateSlotSelections,
    'coverage_route_classes': coverageRouteClasses,
    'assignment_slot_id': assignmentSlotId,
    'pilot_contract_version': pilotContractVersion,
    'rotation_id': rotationId,
  };
}
