import 'dart:io';

import 'package:drone_second_class/src/domain/panel_assignment.dart';
import 'package:drone_second_class/src/domain/validation_bundle.dart';
import 'package:drone_second_class/src/session/session_models.dart';
import 'package:drone_second_class/src/session/session_repository.dart';

Future<ValidationBundle> loadValidationBundle() => ValidationBundleLoader(
  assetReader: (assetKey) {
    const validationRoot = '../../question_banks/drone_second_class/validation';
    final source = switch (assetKey) {
      'assets/validation/protocol.json' => '$validationRoot/protocol.json',
      'assets/validation/validation_bundle.json' =>
        '$validationRoot/generated/validation_bundle.json',
      'assets/validation/validation_manifest.json' =>
        '$validationRoot/generated/validation_manifest.json',
      _ => throw ArgumentError.value(assetKey, 'assetKey'),
    };
    return File(source).readAsString();
  },
).load();

PanelAssignmentV1 smallAssignment({
  String assignmentId = 'assignment-small',
  String participantId = 'participant-small',
  AssignmentGroup group = AssignmentGroup.a,
  bool m3 = false,
  List<String> sentinels = const <String>['US-A', 'US-B'],
  List<String> coverage = const <String>[],
}) {
  return PanelAssignmentV1(
    assignmentId: assignmentId,
    participantId: participantId,
    assignmentGroup: group,
    routeVersion: 'route-test-v1',
    deepTargetIds: <String>[m3 ? 'HAZARD_RISK_M3' : 'THIRD_PARTY'],
    breadthGroupIds: const <String>[],
    sentinelIds: sentinels,
    coverageIds: coverage,
    preS1CoverageIds: const <String>[],
    replicationForm: m3 ? ReplicationForm.a : null,
    alternateSlotSelections: const <String, String>{
      'VS-002': 'VS-002',
      'VS-005': 'VS-005',
      'VS-007': 'VS-007',
      'VS-012': 'VS-012',
    },
    coverageRouteClasses: const <String, String>{},
  );
}

Future<ValidationSessionDocument> answerCurrent({
  required ValidationSessionRepository repository,
  required ValidationSessionDocument document,
  required ValidationBundle bundle,
  int selectedIndex = 0,
}) async {
  final shown = await repository.ensureQuestionShown(document);
  final entry = shown.route.entries[shown.responses.length];
  return repository.commitResponse(
    document: shown,
    question: bundle.questionsById[entry.questionId]!,
    selectedIndex: selectedIndex,
  );
}
