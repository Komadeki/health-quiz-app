import '../domain/panel_route.dart';
import 'session_models.dart';

const pilotPredictionMethodVersion = 'v0p3-researcher-judgment-v1';
const preRegisteredSimpleBaselineVersion = 'PRE_REGISTERED_SIMPLE_BASELINE_V1';
const sameTargetAllCorrectRuleVersion = 'SAME_TARGET_ALL_CORRECT_V1';

class PilotPredictionTarget {
  const PilotPredictionTarget({
    required this.predictionKey,
    required this.targetId,
    required this.routeEntry,
    required this.evidenceResponseIds,
  });

  final String predictionKey;
  final String targetId;
  final PanelRouteEntry routeEntry;
  final List<String> evidenceResponseIds;
}

class PilotPredictionPlan {
  const PilotPredictionPlan({
    required this.s1SnapshotId,
    required this.targets,
    required this.allowedEvidenceResponseIds,
  });

  final String s1SnapshotId;
  final List<PilotPredictionTarget> targets;
  final Set<String> allowedEvidenceResponseIds;

  factory PilotPredictionPlan.fromDocument(ValidationSessionDocument document) {
    final s1 = document.snapshots.singleWhere((item) => item.label == 'S1');
    final observedByTarget = <String, List<String>>{};
    for (final response in document.responses) {
      if (response.phase != PanelPhase.observed ||
          !s1.responseIdsIncluded.contains(response.responseId)) {
        continue;
      }
      final entry = document.route.entries[response.presentationIndex];
      if (!entry.measurement) continue;
      observedByTarget
          .putIfAbsent(_targetId(entry), () => <String>[])
          .add(response.responseId);
    }
    final heldOut = document.route.entries
        .where((entry) => entry.phase == PanelPhase.heldOut)
        .toList(growable: false);
    final targets = <PilotPredictionTarget>[];
    for (var index = 0; index < heldOut.length; index += 1) {
      final entry = heldOut[index];
      final targetId = _targetId(entry);
      final evidence = observedByTarget[targetId] ?? const <String>[];
      if (evidence.isEmpty) {
        throw StateError('No Observed measurement exists for $targetId.');
      }
      targets.add(
        PilotPredictionTarget(
          predictionKey: 'HP-${(index + 1).toString().padLeft(3, '0')}',
          targetId: targetId,
          routeEntry: entry,
          evidenceResponseIds: List<String>.unmodifiable(evidence),
        ),
      );
    }
    return PilotPredictionPlan(
      s1SnapshotId: s1.snapshotId,
      targets: List<PilotPredictionTarget>.unmodifiable(targets),
      allowedEvidenceResponseIds: Set<String>.unmodifiable(
        observedByTarget.values.expand((items) => items),
      ),
    );
  }
}

class PilotPredictionContract {
  const PilotPredictionContract();

  Map<String, Object?> validate({
    required ValidationSessionDocument document,
    required Map<String, Object?> payload,
  }) {
    final plan = PilotPredictionPlan.fromDocument(document);
    if (payload['schema_version'] != 1 ||
        payload['method_version'] != pilotPredictionMethodVersion ||
        payload['s1_snapshot_id'] != plan.s1SnapshotId) {
      throw const FormatException('Structured Prediction header is invalid.');
    }
    final rawPredictions = payload['predictions'];
    if (rawPredictions is! List) {
      throw const FormatException('predictions must be a list.');
    }
    if (rawPredictions.length != plan.targets.length) {
      throw FormatException(
        'Prediction count must equal ${plan.targets.length}.',
      );
    }
    final expectedByKey = <String, PilotPredictionTarget>{
      for (final target in plan.targets) target.predictionKey: target,
    };
    final seen = <String>{};
    final normalized = <Map<String, Object?>>[];
    for (final raw in rawPredictions) {
      if (raw is! Map) {
        throw const FormatException('Each prediction must be an object.');
      }
      final prediction = raw.cast<String, Object?>();
      final key = prediction['prediction_key'];
      if (key is! String || !seen.add(key) || !expectedByKey.containsKey(key)) {
        throw const FormatException('Prediction keys must match exactly.');
      }
      final expected = expectedByKey[key]!;
      if (prediction['target_id'] != expected.targetId) {
        throw FormatException('target_id does not match $key.');
      }
      final outcome = prediction['predicted_outcome'];
      if (outcome != 'CORRECT' && outcome != 'INCORRECT') {
        throw const FormatException(
          'predicted_outcome must be CORRECT or INCORRECT.',
        );
      }
      final confidence = prediction['confidence'];
      if (confidence is! int || confidence < 1 || confidence > 3) {
        throw const FormatException('confidence must be 1, 2, or 3.');
      }
      final rawEvidence = prediction['evidence_response_ids'];
      if (rawEvidence is! List || rawEvidence.any((item) => item is! String)) {
        throw const FormatException(
          'evidence_response_ids must be a string list.',
        );
      }
      final evidence = rawEvidence.cast<String>();
      if (evidence.toSet().length != evidence.length ||
          evidence.any(
            (responseId) =>
                !plan.allowedEvidenceResponseIds.contains(responseId),
          )) {
        throw const FormatException(
          'Evidence must contain only S1 Observed measurement responses.',
        );
      }
      normalized.add(<String, Object?>{
        'prediction_key': key,
        'target_id': expected.targetId,
        'predicted_outcome': outcome,
        'confidence': confidence,
        'evidence_response_ids': List<String>.unmodifiable(evidence),
      });
    }
    if (seen.length != expectedByKey.length) {
      throw const FormatException('Prediction keys must match exactly.');
    }
    normalized.sort(
      (left, right) => (left['prediction_key']! as String).compareTo(
        right['prediction_key']! as String,
      ),
    );
    return <String, Object?>{
      'schema_version': 1,
      'method_version': pilotPredictionMethodVersion,
      's1_snapshot_id': plan.s1SnapshotId,
      'predictions': List<Map<String, Object?>>.unmodifiable(normalized),
    };
  }
}

Map<String, Object?> buildPreRegisteredSimpleBaseline({
  required ValidationSessionDocument document,
}) {
  final plan = PilotPredictionPlan.fromDocument(document);
  final responsesById = <String, ValidationResponse>{
    for (final response in document.responses) response.responseId: response,
  };
  return <String, Object?>{
    'method_version': preRegisteredSimpleBaselineVersion,
    'rule_version': sameTargetAllCorrectRuleVersion,
    's1_snapshot_id': plan.s1SnapshotId,
    'predictions': plan.targets
        .map((target) {
          final allCorrect = target.evidenceResponseIds
              .map((id) => responsesById[id]!)
              .every((response) => response.isCorrect);
          return <String, Object?>{
            'prediction_key': target.predictionKey,
            'target_id': target.targetId,
            'predicted_outcome': allCorrect ? 'CORRECT' : 'INCORRECT',
          };
        })
        .toList(growable: false),
  };
}

String _targetId(PanelRouteEntry entry) {
  if (entry.assignmentRole == 'BREADTH_OBSERVED' ||
      entry.assignmentRole == 'BREADTH_HELD_OUT') {
    return entry.analysisGroup;
  }
  return switch (entry.analysisGroup.substring(0, 1)) {
    'H' => 'HAZARD_RISK_M3',
    'T' => 'THIRD_PARTY',
    'G' => 'GNSS',
    'A' => 'AUTO_MANUAL',
    'E' => 'TEM',
    _ => throw FormatException(
      'Unknown prediction target for ${entry.analysisGroup}.',
    ),
  };
}
