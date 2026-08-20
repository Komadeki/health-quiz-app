import 'dart:convert';

import '../domain/panel_assignment.dart';
import '../domain/panel_route.dart';
import '../domain/validation_bundle.dart';
import '../domain/validation_provenance.dart';
import 'session_models.dart';
import 'session_storage.dart';
import 'research_prediction_provider.dart';
import 'pilot_prediction.dart';

const requiredValidationEventTypes = <String>{
  'session_started',
  'phase_started',
  'question_shown',
  'response_committed',
  'snapshot_saved',
  'prediction_committed',
  'explanation_unlocked',
  'phase_completed',
  'session_completed',
};

class ValidationSessionRepository {
  ValidationSessionRepository({required this.store, DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  final ValidationSessionStore store;
  final DateTime Function() _clock;

  Future<ValidationSessionDocument> start({
    required String sessionId,
    required PanelAssignmentV1 assignment,
    required PanelRoute route,
    required ValidationProvenance provenance,
  }) async {
    if (await store.loadActive() != null) {
      throw StateError('An active unarchived session blocks a new start.');
    }
    if (assignment.participantId.startsWith('V0P3-E') &&
        await store.hasParticipant(assignment.participantId)) {
      throw StateError(
        'A fresh second external session for this participant is rejected.',
      );
    }
    final now = _clock().toUtc();
    final session = ValidationSession(
      sessionId: sessionId,
      participantId: assignment.participantId,
      assignmentId: assignment.assignmentId,
      assignmentGroup: assignment.assignmentGroup,
      replicationForm: assignment.replicationForm,
      routeVersion: assignment.routeVersion,
      routeQuestionIds: route.questionIds,
      routeHash: route.routeHash,
      provenance: provenance,
      startedAt: now,
      completedAt: null,
      currentPhase: PanelPhase.observed,
    );
    final started = ValidationEvent(
      eventSeq: 1,
      sessionId: sessionId,
      eventType: 'session_started',
      occurredAt: now,
      phase: PanelPhase.observed,
      questionId: null,
      payload: <String, Object?>{'route_hash': route.routeHash},
    );
    final s0 = _snapshot(
      session: session,
      label: 'S0',
      cutoff: 1,
      capturedAt: now,
      responses: const <ValidationResponse>[],
      phase: PanelPhase.observed,
    );
    final snapshotSaved = ValidationEvent(
      eventSeq: 2,
      sessionId: sessionId,
      eventType: 'snapshot_saved',
      occurredAt: now,
      phase: PanelPhase.observed,
      questionId: null,
      payload: <String, Object?>{
        'snapshot_id': s0.snapshotId,
        'label': 'S0',
        'event_seq_cutoff': s0.eventSeqCutoff,
      },
    );
    final phaseStarted = ValidationEvent(
      eventSeq: 3,
      sessionId: sessionId,
      eventType: 'phase_started',
      occurredAt: now,
      phase: PanelPhase.observed,
      questionId: null,
      payload: const <String, Object?>{},
    );
    final document = ValidationSessionDocument(
      session: session,
      assignment: assignment,
      route: route,
      responses: const <ValidationResponse>[],
      events: <ValidationEvent>[started, snapshotSaved, phaseStarted],
      snapshots: <ValidationSnapshot>[s0],
      researchPrediction: null,
      baselineCandidateOutputs: null,
      preRegisteredSimpleBaseline: null,
    );
    return _persist(document);
  }

  Future<ValidationSessionDocument?> loadActive() => store.loadActive();

  Future<void> archiveCompleted(ValidationSessionDocument document) =>
      store.archive(document);

  ValidationEvent? pendingShownEvent(ValidationSessionDocument document) {
    if (document.responses.length >= document.route.entries.length) return null;
    final index = document.responses.length;
    for (final event in document.events.reversed) {
      if (event.eventType == 'question_shown' &&
          event.payload['presentation_index'] == index) {
        return event;
      }
    }
    return null;
  }

  Future<ValidationSessionDocument> ensureQuestionShown(
    ValidationSessionDocument document,
  ) async {
    final index = document.responses.length;
    if (index >= document.route.entries.length) {
      throw StateError('No route question remains to be shown.');
    }
    final entry = document.route.entries[index];
    if (entry.phase != document.session.currentPhase) {
      throw StateError(
        'Question phase ${entry.phase.wireName} is locked while '
        '${document.session.currentPhase.wireName} is active.',
      );
    }
    final existing = pendingShownEvent(document);
    if (existing != null) {
      if (existing.questionId != entry.questionId) {
        throw StateError('A different unanswered question is pending.');
      }
      return document;
    }
    final event = ValidationEvent(
      eventSeq: document.nextEventSeq,
      sessionId: document.session.sessionId,
      eventType: 'question_shown',
      occurredAt: _clock().toUtc(),
      phase: entry.phase,
      questionId: entry.questionId,
      payload: <String, Object?>{
        'presentation_index': index,
        'slot_id': entry.slotId,
        'assignment_role': entry.assignmentRole,
      },
    );
    return _persist(
      document.copyWith(events: <ValidationEvent>[...document.events, event]),
    );
  }

  Future<ValidationSessionDocument> commitResponse({
    required ValidationSessionDocument document,
    required ValidationQuestion question,
    required int selectedIndex,
  }) async {
    if (selectedIndex < 0 || selectedIndex >= question.choices.length) {
      throw RangeError('Selected choice is outside the question choices.');
    }
    final presentationIndex = document.responses.length;
    final entry = document.route.entries[presentationIndex];
    if (entry.questionId != question.questionId ||
        entry.phase != document.session.currentPhase) {
      throw StateError('The response does not match the active route item.');
    }
    final shown = pendingShownEvent(document);
    if (shown == null || shown.questionId != question.questionId) {
      throw StateError('A durable question_shown event is required.');
    }
    final now = _clock().toUtc();
    final duration = now.difference(shown.occurredAt).inMilliseconds;
    final response = ValidationResponse(
      responseId: '${document.session.sessionId}-R-${presentationIndex + 1}',
      sessionId: document.session.sessionId,
      questionId: question.questionId,
      questionVersion: question.questionVersion,
      bankRevision: document.session.provenance.bankRevision,
      phase: entry.phase,
      presentationIndex: presentationIndex,
      selectedChoice: String.fromCharCode(65 + selectedIndex),
      isCorrect: selectedIndex == question.correctIndex,
      questionShownAt: shown.occurredAt,
      responseCommittedAt: now,
      durationMs: duration < 0 ? 0 : duration,
    );
    final responses = <ValidationResponse>[...document.responses, response];
    var events = <ValidationEvent>[
      ...document.events,
      ValidationEvent(
        eventSeq: document.nextEventSeq,
        sessionId: document.session.sessionId,
        eventType: 'response_committed',
        occurredAt: now,
        phase: entry.phase,
        questionId: entry.questionId,
        payload: <String, Object?>{
          'response_id': response.responseId,
          'presentation_index': presentationIndex,
        },
      ),
    ];
    var snapshots = document.snapshots;
    var session = document.session;
    var baseline = document.baselineCandidateOutputs;
    var preRegisteredBaseline = document.preRegisteredSimpleBaseline;

    final nextEntry = presentationIndex + 1 < document.route.entries.length
        ? document.route.entries[presentationIndex + 1]
        : null;
    if (nextEntry?.phase != entry.phase) {
      events = _appendEvent(
        events,
        session,
        type: 'phase_completed',
        phase: entry.phase,
        now: now,
      );
      switch (entry.phase) {
        case PanelPhase.observed:
          final result = _appendSnapshot(
            session: session,
            events: events,
            snapshots: snapshots,
            responses: responses,
            label: 'S1',
            phase: PanelPhase.observed,
            now: now,
          );
          events = result.events;
          snapshots = result.snapshots;
          baseline = buildBaselineCandidateOutputs(
            route: document.route,
            responses: responses,
            events: events,
            eventSeqCutoff: result.snapshot.eventSeqCutoff,
          );
          if (document.assignment.pilotContractVersion != null) {
            preRegisteredBaseline = buildPreRegisteredSimpleBaseline(
              document: document.copyWith(
                session: session,
                responses: responses,
                events: events,
                snapshots: snapshots,
              ),
            );
          }
          session = session.withPhase(PanelPhase.predictionGate);
          events = _appendEvent(
            events,
            session,
            type: 'phase_started',
            phase: PanelPhase.predictionGate,
            now: now,
          );
        case PanelPhase.heldOut:
          final result = _appendSnapshot(
            session: session,
            events: events,
            snapshots: snapshots,
            responses: responses,
            label: 'S2',
            phase: PanelPhase.heldOut,
            now: now,
          );
          events = result.events;
          snapshots = result.snapshots;
          final transition = _nextAfterBlock(
            session: session,
            route: document.route,
            responseCount: responses.length,
            events: events,
            now: now,
          );
          session = transition.session;
          events = transition.events;
        case PanelPhase.replication:
          final result = _appendSnapshot(
            session: session,
            events: events,
            snapshots: snapshots,
            responses: responses,
            label: 'S3',
            phase: PanelPhase.replication,
            now: now,
          );
          events = result.events;
          snapshots = result.snapshots;
          final transition = _nextAfterBlock(
            session: session,
            route: document.route,
            responseCount: responses.length,
            events: events,
            now: now,
          );
          session = transition.session;
          events = transition.events;
        case PanelPhase.sentinel:
          final assignedSentinels = document.route.entries
              .where((item) => item.phase == PanelPhase.sentinel)
              .length;
          final committedSentinels = responses
              .where((item) => item.phase == PanelPhase.sentinel)
              .length;
          if (committedSentinels != assignedSentinels) {
            throw StateError(
              'Explanation requires all participant-assigned Sentinels.',
            );
          }
          session = session.withPhase(PanelPhase.explanation);
          events = _appendEvent(
            events,
            session,
            type: 'explanation_unlocked',
            phase: PanelPhase.explanation,
            now: now,
            payload: <String, Object?>{
              'assigned_sentinel_count': assignedSentinels,
            },
          );
          events = _appendEvent(
            events,
            session,
            type: 'phase_started',
            phase: PanelPhase.explanation,
            now: now,
          );
        case PanelPhase.remainingCoverage:
          session = session.withPhase(PanelPhase.complete, completedAt: now);
          events = _appendEvent(
            events,
            session,
            type: 'session_completed',
            phase: PanelPhase.complete,
            now: now,
          );
        case PanelPhase.predictionGate ||
              PanelPhase.explanation ||
              PanelPhase.complete:
          throw StateError(
            'Responses are not accepted in ${entry.phase.wireName}.',
          );
      }
    }

    return _persist(
      document.copyWith(
        session: session,
        responses: responses,
        events: events,
        snapshots: snapshots,
        baselineCandidateOutputs: baseline,
        preRegisteredSimpleBaseline: preRegisteredBaseline,
      ),
    );
  }

  Future<ValidationSessionDocument> commitPrediction({
    required ValidationSessionDocument document,
    required String algorithmVersion,
    required Map<String, Object?> payload,
  }) async {
    if (document.session.currentPhase != PanelPhase.predictionGate) {
      throw StateError('Research Prediction is not currently available.');
    }
    if (document.researchPrediction != null) {
      throw StateError('Research Prediction is immutable after commit.');
    }
    if (algorithmVersion.trim().isEmpty || payload.isEmpty) {
      throw const FormatException(
        'Prediction algorithm version and payload are required.',
      );
    }
    final s1 = document.snapshots.firstWhere((item) => item.label == 'S1');
    final baseline = document.baselineCandidateOutputs;
    if (baseline == null) {
      throw StateError('S1 baseline candidate artifact is missing.');
    }
    if (document.events.any(
      (event) =>
          event.eventType == 'question_shown' &&
          (event.phase == PanelPhase.heldOut ||
              event.phase == PanelPhase.sentinel),
    )) {
      throw StateError('S1 evidence boundary has already been crossed.');
    }
    final now = _clock().toUtc();
    final predictionSeq = document.nextEventSeq;
    final evidence = ResearchPredictionEvidence.fromDocument(document);
    final observedIds = evidence.observedResponses
        .map((response) => response.responseId)
        .toList(growable: false);
    final isPilot = document.assignment.pilotContractVersion != null;
    final normalizedPayload = isPilot
        ? const PilotPredictionContract().validate(
            document: document,
            payload: payload,
          )
        : payload;
    if (isPilot && algorithmVersion.trim() != pilotPredictionMethodVersion) {
      throw const FormatException(
        'Pilot prediction method_version is invalid.',
      );
    }
    final prediction = ResearchPrediction(
      predictionId: '${document.session.sessionId}-P-1',
      sessionId: document.session.sessionId,
      snapshotId: s1.snapshotId,
      predictionAlgorithmVersion: algorithmVersion.trim(),
      predictionPayload: Map<String, Object?>.unmodifiable(normalizedPayload),
      observedResponseIds: observedIds,
      bestSimpleBaseline: baseline,
      committedAt: now,
      eventSeq: predictionSeq,
    );
    var events = _appendEvent(
      document.events,
      document.session,
      type: 'prediction_committed',
      phase: PanelPhase.predictionGate,
      now: now,
      payload: <String, Object?>{'prediction_id': prediction.predictionId},
    );
    final session = document.session.withPhase(PanelPhase.heldOut);
    events = _appendEvent(
      events,
      session,
      type: 'phase_started',
      phase: PanelPhase.heldOut,
      now: now,
    );
    return _persist(
      document.copyWith(
        session: session,
        events: events,
        researchPrediction: prediction,
      ),
    );
  }

  Future<ValidationSessionDocument> continueAfterExplanation(
    ValidationSessionDocument document,
  ) async {
    if (document.session.currentPhase != PanelPhase.explanation ||
        !document.events.any(
          (event) => event.eventType == 'explanation_unlocked',
        )) {
      throw StateError('Explanation is still locked.');
    }
    final now = _clock().toUtc();
    var events = _appendEvent(
      document.events,
      document.session,
      type: 'phase_completed',
      phase: PanelPhase.explanation,
      now: now,
    );
    ValidationSession session;
    final hasCoverage =
        document.responses.length < document.route.entries.length;
    if (hasCoverage) {
      final next = document.route.entries[document.responses.length];
      if (next.phase != PanelPhase.remainingCoverage) {
        throw StateError('Unexpected route entry after Explanation.');
      }
      session = document.session.withPhase(PanelPhase.remainingCoverage);
      events = _appendEvent(
        events,
        session,
        type: 'phase_started',
        phase: PanelPhase.remainingCoverage,
        now: now,
      );
    } else {
      session = document.session.withPhase(
        PanelPhase.complete,
        completedAt: now,
      );
      events = _appendEvent(
        events,
        session,
        type: 'session_completed',
        phase: PanelPhase.complete,
        now: now,
      );
    }
    return _persist(document.copyWith(session: session, events: events));
  }

  Future<ValidationSessionDocument> _persist(
    ValidationSessionDocument document,
  ) async {
    document.validate();
    await store.write(document);
    return document;
  }
}

class _SnapshotAppendResult {
  const _SnapshotAppendResult({
    required this.events,
    required this.snapshots,
    required this.snapshot,
  });

  final List<ValidationEvent> events;
  final List<ValidationSnapshot> snapshots;
  final ValidationSnapshot snapshot;
}

_SnapshotAppendResult _appendSnapshot({
  required ValidationSession session,
  required List<ValidationEvent> events,
  required List<ValidationSnapshot> snapshots,
  required List<ValidationResponse> responses,
  required String label,
  required PanelPhase phase,
  required DateTime now,
}) {
  final snapshot = _snapshot(
    session: session,
    label: label,
    cutoff: events.last.eventSeq,
    capturedAt: now,
    responses: responses,
    phase: phase,
  );
  final nextEvents = _appendEvent(
    events,
    session,
    type: 'snapshot_saved',
    phase: phase,
    now: now,
    payload: <String, Object?>{
      'snapshot_id': snapshot.snapshotId,
      'label': label,
      'event_seq_cutoff': snapshot.eventSeqCutoff,
    },
  );
  return _SnapshotAppendResult(
    events: nextEvents,
    snapshots: <ValidationSnapshot>[...snapshots, snapshot],
    snapshot: snapshot,
  );
}

ValidationSnapshot _snapshot({
  required ValidationSession session,
  required String label,
  required int cutoff,
  required DateTime capturedAt,
  required List<ValidationResponse> responses,
  required PanelPhase phase,
}) {
  final responseIds =
      responses.map((response) => response.responseId).toList(growable: false);
  return ValidationSnapshot(
    snapshotId: '${session.sessionId}-$label',
    sessionId: session.sessionId,
    label: label,
    eventSeqCutoff: cutoff,
    capturedAt: capturedAt,
    responseIdsIncluded: responseIds,
    currentPhase: phase,
    routeVersion: session.routeVersion,
    stateHash: canonicalSha256(<String, Object?>{
      'event_seq_cutoff': cutoff,
      'phase': phase.wireName,
      'response_ids': responseIds,
      'route_version': session.routeVersion,
    }),
    sentinelState: 'UNKNOWN',
  );
}

List<ValidationEvent> _appendEvent(
  List<ValidationEvent> events,
  ValidationSession session, {
  required String type,
  required PanelPhase phase,
  required DateTime now,
  Map<String, Object?> payload = const <String, Object?>{},
}) {
  return <ValidationEvent>[
    ...events,
    ValidationEvent(
      eventSeq: events.isEmpty ? 1 : events.last.eventSeq + 1,
      sessionId: session.sessionId,
      eventType: type,
      occurredAt: now,
      phase: phase,
      questionId: null,
      payload: payload,
    ),
  ];
}

class _PhaseTransition {
  const _PhaseTransition({required this.session, required this.events});

  final ValidationSession session;
  final List<ValidationEvent> events;
}

_PhaseTransition _nextAfterBlock({
  required ValidationSession session,
  required PanelRoute route,
  required int responseCount,
  required List<ValidationEvent> events,
  required DateTime now,
}) {
  final next = responseCount < route.entries.length
      ? route.entries[responseCount]
      : null;
  if (next?.phase == PanelPhase.replication ||
      next?.phase == PanelPhase.sentinel) {
    final phase = next!.phase;
    final nextSession = session.withPhase(phase);
    return _PhaseTransition(
      session: nextSession,
      events: _appendEvent(
        events,
        nextSession,
        type: 'phase_started',
        phase: phase,
        now: now,
      ),
    );
  }
  final nextSession = session.withPhase(PanelPhase.explanation);
  var nextEvents = _appendEvent(
    events,
    nextSession,
    type: 'explanation_unlocked',
    phase: PanelPhase.explanation,
    now: now,
    payload: const <String, Object?>{'assigned_sentinel_count': 0},
  );
  nextEvents = _appendEvent(
    nextEvents,
    nextSession,
    type: 'phase_started',
    phase: PanelPhase.explanation,
    now: now,
  );
  return _PhaseTransition(session: nextSession, events: nextEvents);
}

Map<String, Object?> buildBaselineCandidateOutputs({
  required PanelRoute route,
  required List<ValidationResponse> responses,
  required List<ValidationEvent> events,
  required int eventSeqCutoff,
}) {
  final measurementEntries = route.entries
      .asMap()
      .entries
      .where(
        (item) =>
            item.value.phase == PanelPhase.observed && item.value.measurement,
      )
      .toList(growable: false);
  final responseByIndex = <int, ValidationResponse>{
    for (final response in responses)
      if (response.phase == PanelPhase.observed)
        response.presentationIndex: response,
  };
  final stats = <String, List<ValidationResponse>>{};
  final unanswered = <String>[];
  for (final item in measurementEntries) {
    final response = responseByIndex[item.key];
    if (response == null) {
      unanswered.add(item.value.questionId);
    } else {
      stats
          .putIfAbsent(item.value.analysisGroup, () => <ValidationResponse>[])
          .add(response);
    }
  }
  final summaries = stats.entries.map((item) {
    final errors = item.value.where((response) => !response.isCorrect).length;
    return <String, Object?>{
      'analysis_group': item.key,
      'accuracy': item.value.isEmpty
          ? null
          : (item.value.length - errors) / item.value.length,
      'errors': errors,
      'response_count': item.value.length,
    };
  }).toList(growable: false);
  final accuracies = summaries
      .map((item) => item['accuracy'])
      .whereType<double>()
      .toList(growable: false);
  final lowest = accuracies.isEmpty
      ? null
      : accuracies.reduce((left, right) => left < right ? left : right);
  final errorCounts =
      summaries.map((item) => item['errors']! as int).toList(growable: false);
  final mostErrors = errorCounts.isEmpty
      ? 0
      : errorCounts.reduce((left, right) => left > right ? left : right);
  ValidationResponse? recentError;
  int? recentErrorSeq;
  for (final event in events.where(
    (item) =>
        item.eventSeq <= eventSeqCutoff &&
        item.eventType == 'response_committed',
  )) {
    final response = responses.cast<ValidationResponse?>().firstWhere(
          (item) => item?.responseId == event.payload['response_id'],
          orElse: () => null,
        );
    if (response != null &&
        response.phase == PanelPhase.observed &&
        !response.isCorrect) {
      recentError = response;
      recentErrorSeq = event.eventSeq;
    }
  }
  return <String, Object?>{
    'artifact_version': 'best-simple-baseline-candidates-v1',
    'event_seq_cutoff': eventSeqCutoff,
    'lowest_accuracy': <String, Object?>{
      'accuracy': lowest,
      'analysis_groups': summaries
          .where((item) => item['accuracy'] == lowest)
          .map((item) => item['analysis_group'])
          .toList(growable: false),
    },
    'most_errors': <String, Object?>{
      'error_count': mostErrors,
      'analysis_groups': summaries
          .where((item) => item['errors'] == mostErrors)
          .map((item) => item['analysis_group'])
          .toList(growable: false),
    },
    'unanswered': <String, Object?>{'question_ids': unanswered},
    'most_recent_error': recentError == null
        ? null
        : <String, Object?>{
            'question_id': recentError.questionId,
            'response_id': recentError.responseId,
            'event_seq': recentErrorSeq,
          },
  };
}

List<String> replayResponseIdsAtSnapshot(
  ValidationSessionDocument document,
  ValidationSnapshot snapshot,
) {
  return document.events
      .where(
        (event) =>
            event.eventSeq <= snapshot.eventSeqCutoff &&
            event.eventType == 'response_committed',
      )
      .map((event) => event.payload['response_id']! as String)
      .toList(growable: false);
}

String buildValidationExport(ValidationSessionDocument document) {
  final export = <String, Object?>{
    'schema_version': 1,
    'artifact_purpose': 'VALIDATION_ONLY',
    'provenance': document.session.provenance.toJson(),
    'session': document.session.toJson(),
    'assignment': document.assignment.toJson(),
    'exact_route': document.route.toJson(),
    'responses':
        document.responses.map((item) => item.toJson()).toList(growable: false),
    'events':
        document.events.map((item) => item.toJson()).toList(growable: false),
    'snapshots':
        document.snapshots.map((item) => item.toJson()).toList(growable: false),
    'research_prediction': document.researchPrediction?.toJson(),
    'baseline_candidate_outputs': document.baselineCandidateOutputs,
    'pre_registered_simple_baseline': document.preRegisteredSimpleBaseline,
  };
  return const JsonEncoder.withIndent('  ').convert(export);
}
