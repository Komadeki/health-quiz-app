import '../domain/panel_assignment.dart';
import '../domain/panel_route.dart';
import '../domain/validation_provenance.dart';

class ValidationSession {
  const ValidationSession({
    required this.sessionId,
    required this.participantId,
    required this.assignmentId,
    required this.assignmentGroup,
    required this.replicationForm,
    required this.routeVersion,
    required this.routeQuestionIds,
    required this.routeHash,
    required this.provenance,
    required this.startedAt,
    required this.completedAt,
    required this.currentPhase,
  });

  final String sessionId;
  final String participantId;
  final String assignmentId;
  final AssignmentGroup assignmentGroup;
  final ReplicationForm? replicationForm;
  final String routeVersion;
  final List<String> routeQuestionIds;
  final String routeHash;
  final ValidationProvenance provenance;
  final DateTime startedAt;
  final DateTime? completedAt;
  final PanelPhase currentPhase;

  ValidationSession withPhase(PanelPhase phase, {DateTime? completedAt}) {
    return ValidationSession(
      sessionId: sessionId,
      participantId: participantId,
      assignmentId: assignmentId,
      assignmentGroup: assignmentGroup,
      replicationForm: replicationForm,
      routeVersion: routeVersion,
      routeQuestionIds: routeQuestionIds,
      routeHash: routeHash,
      provenance: provenance,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      currentPhase: phase,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'session_id': sessionId,
        'participant_id': participantId,
        'assignment_id': assignmentId,
        'assignment_group': assignmentGroup == AssignmentGroup.a ? 'A' : 'B',
        'replication_form': switch (replicationForm) {
          ReplicationForm.a => 'A',
          ReplicationForm.b => 'B',
          null => null,
        },
        'route_version': routeVersion,
        'route_question_ids': routeQuestionIds,
        'route_hash': routeHash,
        ...provenance.toJson(),
        'started_at': startedAt.toUtc().toIso8601String(),
        'completed_at': completedAt?.toUtc().toIso8601String(),
        'current_phase': currentPhase.wireName,
      };

  factory ValidationSession.fromJson(Map<String, Object?> json) {
    return ValidationSession(
      sessionId: json['session_id']! as String,
      participantId: json['participant_id']! as String,
      assignmentId: json['assignment_id']! as String,
      assignmentGroup: json['assignment_group'] == 'A'
          ? AssignmentGroup.a
          : AssignmentGroup.b,
      replicationForm: switch (json['replication_form']) {
        'A' => ReplicationForm.a,
        'B' => ReplicationForm.b,
        _ => null,
      },
      routeVersion: json['route_version']! as String,
      routeQuestionIds: (json['route_question_ids']! as List).cast<String>(),
      routeHash: json['route_hash']! as String,
      provenance: ValidationProvenance.fromJson(json),
      startedAt: DateTime.parse(json['started_at']! as String),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at']! as String),
      currentPhase: PanelPhaseWire.parse(json['current_phase']! as String),
    );
  }
}

class ValidationResponse {
  const ValidationResponse({
    required this.responseId,
    required this.sessionId,
    required this.questionId,
    required this.questionVersion,
    required this.bankRevision,
    required this.phase,
    required this.presentationIndex,
    required this.selectedChoice,
    required this.isCorrect,
    required this.questionShownAt,
    required this.responseCommittedAt,
    required this.durationMs,
  });

  final String responseId;
  final String sessionId;
  final String questionId;
  final int questionVersion;
  final String bankRevision;
  final PanelPhase phase;
  final int presentationIndex;
  final String selectedChoice;
  final bool isCorrect;
  final DateTime questionShownAt;
  final DateTime responseCommittedAt;
  final int durationMs;

  Map<String, Object?> toJson() => <String, Object?>{
        'response_id': responseId,
        'session_id': sessionId,
        'question_id': questionId,
        'question_version': questionVersion,
        'bank_revision': bankRevision,
        'phase': phase.wireName,
        'presentation_index': presentationIndex,
        'selected_choice': selectedChoice,
        'is_correct': isCorrect,
        'question_shown_at': questionShownAt.toUtc().toIso8601String(),
        'response_committed_at': responseCommittedAt.toUtc().toIso8601String(),
        'duration_ms': durationMs,
      };

  factory ValidationResponse.fromJson(Map<String, Object?> json) {
    return ValidationResponse(
      responseId: json['response_id']! as String,
      sessionId: json['session_id']! as String,
      questionId: json['question_id']! as String,
      questionVersion: json['question_version']! as int,
      bankRevision: json['bank_revision']! as String,
      phase: PanelPhaseWire.parse(json['phase']! as String),
      presentationIndex: json['presentation_index']! as int,
      selectedChoice: json['selected_choice']! as String,
      isCorrect: json['is_correct']! as bool,
      questionShownAt: DateTime.parse(json['question_shown_at']! as String),
      responseCommittedAt: DateTime.parse(
        json['response_committed_at']! as String,
      ),
      durationMs: json['duration_ms']! as int,
    );
  }
}

class ValidationEvent {
  const ValidationEvent({
    required this.eventSeq,
    required this.sessionId,
    required this.eventType,
    required this.occurredAt,
    required this.phase,
    required this.questionId,
    required this.payload,
  });

  final int eventSeq;
  final String sessionId;
  final String eventType;
  final DateTime occurredAt;
  final PanelPhase phase;
  final String? questionId;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() => <String, Object?>{
        'event_seq': eventSeq,
        'session_id': sessionId,
        'event_type': eventType,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'phase': phase.wireName,
        'question_id': questionId,
        'payload': payload,
      };

  factory ValidationEvent.fromJson(Map<String, Object?> json) {
    return ValidationEvent(
      eventSeq: json['event_seq']! as int,
      sessionId: json['session_id']! as String,
      eventType: json['event_type']! as String,
      occurredAt: DateTime.parse(json['occurred_at']! as String),
      phase: PanelPhaseWire.parse(json['phase']! as String),
      questionId: json['question_id'] as String?,
      payload: (json['payload']! as Map).cast<String, Object?>(),
    );
  }
}

class ValidationSnapshot {
  const ValidationSnapshot({
    required this.snapshotId,
    required this.sessionId,
    required this.label,
    required this.eventSeqCutoff,
    required this.capturedAt,
    required this.responseIdsIncluded,
    required this.currentPhase,
    required this.routeVersion,
    required this.stateHash,
    required this.sentinelState,
  });

  final String snapshotId;
  final String sessionId;
  final String label;
  final int eventSeqCutoff;
  final DateTime capturedAt;
  final List<String> responseIdsIncluded;
  final PanelPhase currentPhase;
  final String routeVersion;
  final String stateHash;
  final String sentinelState;

  Map<String, Object?> toJson() => <String, Object?>{
        'snapshot_id': snapshotId,
        'session_id': sessionId,
        'label': label,
        'event_seq_cutoff': eventSeqCutoff,
        'captured_at': capturedAt.toUtc().toIso8601String(),
        'response_ids_included': responseIdsIncluded,
        'current_phase': currentPhase.wireName,
        'route_version': routeVersion,
        'state_hash': stateHash,
        'sentinel_state': sentinelState,
      };

  factory ValidationSnapshot.fromJson(Map<String, Object?> json) {
    return ValidationSnapshot(
      snapshotId: json['snapshot_id']! as String,
      sessionId: json['session_id']! as String,
      label: json['label']! as String,
      eventSeqCutoff: json['event_seq_cutoff']! as int,
      capturedAt: DateTime.parse(json['captured_at']! as String),
      responseIdsIncluded:
          (json['response_ids_included']! as List).cast<String>(),
      currentPhase: PanelPhaseWire.parse(json['current_phase']! as String),
      routeVersion: json['route_version']! as String,
      stateHash: json['state_hash']! as String,
      sentinelState: json['sentinel_state']! as String,
    );
  }
}

class ResearchPrediction {
  const ResearchPrediction({
    required this.predictionId,
    required this.sessionId,
    required this.snapshotId,
    required this.predictionAlgorithmVersion,
    required this.predictionPayload,
    required this.observedResponseIds,
    required this.bestSimpleBaseline,
    required this.committedAt,
    required this.eventSeq,
  });

  final String predictionId;
  final String sessionId;
  final String snapshotId;
  final String predictionAlgorithmVersion;
  final Map<String, Object?> predictionPayload;
  final List<String> observedResponseIds;
  final Map<String, Object?> bestSimpleBaseline;
  final DateTime committedAt;
  final int eventSeq;

  Map<String, Object?> toJson() => <String, Object?>{
        'prediction_id': predictionId,
        'session_id': sessionId,
        'snapshot_id': snapshotId,
        'prediction_algorithm_version': predictionAlgorithmVersion,
        'prediction_payload': predictionPayload,
        'observed_response_ids': observedResponseIds,
        'best_simple_baseline': bestSimpleBaseline,
        'committed_at': committedAt.toUtc().toIso8601String(),
        'event_seq': eventSeq,
      };

  factory ResearchPrediction.fromJson(Map<String, Object?> json) {
    return ResearchPrediction(
      predictionId: json['prediction_id']! as String,
      sessionId: json['session_id']! as String,
      snapshotId: json['snapshot_id']! as String,
      predictionAlgorithmVersion:
          json['prediction_algorithm_version']! as String,
      predictionPayload:
          (json['prediction_payload']! as Map).cast<String, Object?>(),
      observedResponseIds:
          (json['observed_response_ids']! as List).cast<String>(),
      bestSimpleBaseline:
          (json['best_simple_baseline']! as Map).cast<String, Object?>(),
      committedAt: DateTime.parse(json['committed_at']! as String),
      eventSeq: json['event_seq']! as int,
    );
  }
}

class ValidationSessionDocument {
  const ValidationSessionDocument({
    required this.session,
    required this.assignment,
    required this.route,
    required this.responses,
    required this.events,
    required this.snapshots,
    required this.researchPrediction,
    required this.baselineCandidateOutputs,
    required this.preRegisteredSimpleBaseline,
  });

  final ValidationSession session;
  final PanelAssignmentV1 assignment;
  final PanelRoute route;
  final List<ValidationResponse> responses;
  final List<ValidationEvent> events;
  final List<ValidationSnapshot> snapshots;
  final ResearchPrediction? researchPrediction;
  final Map<String, Object?>? baselineCandidateOutputs;
  final Map<String, Object?>? preRegisteredSimpleBaseline;

  int get nextEventSeq => events.isEmpty ? 1 : events.last.eventSeq + 1;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema_version': 1,
        'session': session.toJson(),
        'assignment': assignment.toJson(),
        'route': route.toJson(),
        'responses':
            responses.map((item) => item.toJson()).toList(growable: false),
        'events': events.map((item) => item.toJson()).toList(growable: false),
        'snapshots':
            snapshots.map((item) => item.toJson()).toList(growable: false),
        'research_prediction': researchPrediction?.toJson(),
        'baseline_candidate_outputs': baselineCandidateOutputs,
        'pre_registered_simple_baseline': preRegisteredSimpleBaseline,
      };

  factory ValidationSessionDocument.fromJson(Map<String, Object?> json) {
    final document = ValidationSessionDocument(
      session: ValidationSession.fromJson(
        (json['session']! as Map).cast<String, Object?>(),
      ),
      assignment: PanelAssignmentV1.fromJson(
        (json['assignment']! as Map).cast<String, Object?>(),
      ),
      route: PanelRoute.fromJson(
        (json['route']! as Map).cast<String, Object?>(),
      ),
      responses: (json['responses']! as List)
          .map(
            (item) => ValidationResponse.fromJson(
              (item! as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
      events: (json['events']! as List)
          .map(
            (item) => ValidationEvent.fromJson(
              (item! as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
      snapshots: (json['snapshots']! as List)
          .map(
            (item) => ValidationSnapshot.fromJson(
              (item! as Map).cast<String, Object?>(),
            ),
          )
          .toList(growable: false),
      researchPrediction: json['research_prediction'] == null
          ? null
          : ResearchPrediction.fromJson(
              (json['research_prediction']! as Map).cast<String, Object?>(),
            ),
      baselineCandidateOutputs: json['baseline_candidate_outputs'] == null
          ? null
          : (json['baseline_candidate_outputs']! as Map)
              .cast<String, Object?>(),
      preRegisteredSimpleBaseline:
          json['pre_registered_simple_baseline'] == null
              ? null
              : (json['pre_registered_simple_baseline']! as Map)
                  .cast<String, Object?>(),
    );
    document.validate();
    return document;
  }

  ValidationSessionDocument copyWith({
    ValidationSession? session,
    List<ValidationResponse>? responses,
    List<ValidationEvent>? events,
    List<ValidationSnapshot>? snapshots,
    ResearchPrediction? researchPrediction,
    Map<String, Object?>? baselineCandidateOutputs,
    Map<String, Object?>? preRegisteredSimpleBaseline,
  }) {
    return ValidationSessionDocument(
      session: session ?? this.session,
      assignment: assignment,
      route: route,
      responses: responses ?? this.responses,
      events: events ?? this.events,
      snapshots: snapshots ?? this.snapshots,
      researchPrediction: researchPrediction ?? this.researchPrediction,
      baselineCandidateOutputs:
          baselineCandidateOutputs ?? this.baselineCandidateOutputs,
      preRegisteredSimpleBaseline:
          preRegisteredSimpleBaseline ?? this.preRegisteredSimpleBaseline,
    );
  }

  void validate() {
    session.provenance.requireExpected();
    if (session.participantId != assignment.participantId ||
        session.assignmentId != assignment.assignmentId ||
        session.assignmentGroup != assignment.assignmentGroup ||
        session.replicationForm != assignment.replicationForm ||
        session.routeVersion != assignment.routeVersion) {
      throw const FormatException('Session assignment provenance mismatch.');
    }
    if (session.routeHash != route.routeHash ||
        !_sameStrings(session.routeQuestionIds, route.questionIds)) {
      throw const FormatException('Session route provenance mismatch.');
    }
    for (var index = 0; index < events.length; index += 1) {
      if (events[index].eventSeq != index + 1) {
        throw const FormatException('event_seq must be strictly monotonic.');
      }
    }
    for (var index = 0; index < responses.length; index += 1) {
      final response = responses[index];
      if (response.presentationIndex != index ||
          response.questionId != route.entries[index].questionId ||
          response.sessionId != session.sessionId) {
        throw const FormatException(
          'Response append-only ordering is invalid.',
        );
      }
    }
    if (researchPrediction != null &&
        researchPrediction!.snapshotId !=
            snapshots.firstWhere((item) => item.label == 'S1').snapshotId) {
      throw const FormatException('Prediction is not bound to S1.');
    }
  }
}

bool _sameStrings(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
