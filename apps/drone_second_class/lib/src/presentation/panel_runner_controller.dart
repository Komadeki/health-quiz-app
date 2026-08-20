import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../domain/panel_assignment.dart';
import '../domain/panel_route.dart';
import '../domain/pilot_profile.dart';
import '../domain/validation_bundle.dart';
import '../domain/validation_provenance.dart';
import '../session/session_models.dart';
import '../session/session_repository.dart';
import '../session/research_prediction_provider.dart';
import '../session/pilot_export.dart';
import '../session/pilot_prediction.dart';
import 'pilot_export_transfer.dart';

class PilotPreflight {
  const PilotPreflight({required this.assignment, required this.route});

  final PanelAssignmentV1 assignment;
  final PanelRoute route;
}

class PanelRunnerController extends ChangeNotifier {
  PanelRunnerController({
    required this.bundle,
    required this.repository,
    this.predictionProvider = const ResearcherCommitGatePredictionProvider(),
    PilotExportWriter? exportWriter,
    this.exportTransfer = const NativePilotExportTransfer(),
    String? researcherPin,
  })  : exportWriter = exportWriter ?? PilotExportWriter(),
        _researcherPin = researcherPin ??
            const String.fromEnvironment('V0P3_RESEARCHER_PIN');

  final ValidationBundle bundle;
  final ValidationSessionRepository repository;
  final ResearchPredictionProvider predictionProvider;
  final PilotExportWriter exportWriter;
  final PilotExportTransfer exportTransfer;
  final String _researcherPin;
  final DroneV0P3PilotProfile pilotProfile = const DroneV0P3PilotProfile();

  ValidationSessionDocument? document;
  ValidationSessionDocument? resumableDocument;
  ValidationQuestion? visibleQuestion;
  PilotPreflight? pilotPreflight;
  PilotExportArtifact? exportArtifact;
  File? savedExportFile;
  bool researcherUnlocked = false;
  bool busy = false;
  String? errorMessage;

  PanelPhase? get phase => document?.session.currentPhase;

  bool get canResume => resumableDocument != null;

  bool get isPilotSession =>
      document?.assignment.pilotContractVersion == pilotContractVersion;

  PilotPredictionPlan? get pilotPredictionPlan {
    final active = document;
    if (active == null ||
        !isPilotSession ||
        active.session.currentPhase != PanelPhase.predictionGate) {
      return null;
    }
    return PilotPredictionPlan.fromDocument(active);
  }

  Future<void> initialize() async {
    try {
      final loaded = await repository.loadActive();
      if (loaded != null) {
        _validateLoaded(loaded);
        resumableDocument = loaded;
      }
    } catch (error) {
      errorMessage = 'Resume data rejected: $error';
    }
    notifyListeners();
  }

  Future<void> startFromJson(String source) async {
    await _run(() async {
      final decoded = jsonDecode(source);
      if (decoded is! Map) {
        throw const FormatException('Assignment must be a JSON object.');
      }
      final assignment = PanelAssignmentV1.fromJson(
        decoded.cast<String, Object?>(),
      );
      final route = PanelRouteCompiler(bundle).compile(assignment);
      final sessionId = 'V0P-${DateTime.now().toUtc().microsecondsSinceEpoch}';
      document = await repository.start(
        sessionId: sessionId,
        assignment: assignment,
        route: route,
        provenance: bundle.provenance,
      );
      resumableDocument = document;
      visibleQuestion = null;
      await _prepareCurrentQuestion();
    });
  }

  Future<void> compilePilot({
    required String assignmentSlotId,
    required String participantId,
  }) async {
    await _run(() async {
      pilotProfile.validateFixedSlots();
      final assignment = pilotProfile.assignment(
        slotId: assignmentSlotId,
        participantId: participantId,
      );
      final route = PanelRouteCompiler(bundle).compile(assignment);
      pilotPreflight = PilotPreflight(assignment: assignment, route: route);
      exportArtifact = null;
      savedExportFile = null;
    });
  }

  Future<void> confirmPilotPreflight() async {
    await _run(() async {
      final preflight = pilotPreflight;
      if (preflight == null) {
        throw StateError('Pilot Preflight has not been compiled.');
      }
      if (_researcherPin.isEmpty) {
        throw StateError(
          'Pilot execution rejected: Researcher PIN is not configured.',
        );
      }
      pilotProfile.validateAssignment(preflight.assignment);
      final sessionId = 'V0P3-${DateTime.now().toUtc().microsecondsSinceEpoch}';
      document = await repository.start(
        sessionId: sessionId,
        assignment: preflight.assignment,
        route: preflight.route,
        provenance: bundle.provenance,
      );
      pilotPreflight = null;
      resumableDocument = document;
      visibleQuestion = null;
      researcherUnlocked = false;
      await _prepareCurrentQuestion();
    });
  }

  void cancelPilotPreflight() {
    if (busy) return;
    pilotPreflight = null;
    errorMessage = null;
    notifyListeners();
  }

  Future<void> resume() async {
    await _run(() async {
      final loaded = resumableDocument;
      if (loaded == null) throw StateError('No session is available.');
      _validateLoaded(loaded);
      document = loaded;
      visibleQuestion = null;
      researcherUnlocked = false;
      await _prepareCurrentQuestion();
    });
  }

  Future<void> commitChoice(int selectedIndex) async {
    final activeDocument = document;
    final question = visibleQuestion;
    if (activeDocument == null || question == null) return;
    await _run(() async {
      final committed = await repository.commitResponse(
        document: activeDocument,
        question: question,
        selectedIndex: selectedIndex,
      );
      document = committed;
      resumableDocument = committed;
      visibleQuestion = null;
      notifyListeners();
      await _prepareCurrentQuestion();
    });
  }

  Future<void> commitPrediction({
    required String algorithmVersion,
    required String payloadSource,
  }) async {
    final activeDocument = document;
    if (activeDocument == null) return;
    await _run(() async {
      final decoded = jsonDecode(payloadSource);
      if (decoded is! Map) {
        throw const FormatException(
          'Prediction payload must be a JSON object.',
        );
      }
      final committed = await repository.commitPrediction(
        document: activeDocument,
        algorithmVersion: algorithmVersion,
        payload: decoded.cast<String, Object?>(),
      );
      document = committed;
      resumableDocument = committed;
      visibleQuestion = null;
      notifyListeners();
      await _prepareCurrentQuestion();
    });
  }

  void unlockResearcher(String pin) {
    errorMessage = null;
    if (_researcherPin.isEmpty) {
      errorMessage =
          'Pilot execution rejected: Researcher PIN is not configured.';
      researcherUnlocked = false;
    } else if (pin != _researcherPin) {
      errorMessage = 'Researcher PIN rejected.';
      researcherUnlocked = false;
    } else {
      researcherUnlocked = true;
    }
    notifyListeners();
  }

  Future<void> commitPilotPrediction(Map<String, Object?> payload) async {
    final activeDocument = document;
    if (activeDocument == null) return;
    await _run(() async {
      if (!isPilotSession || !researcherUnlocked) {
        throw StateError('Researcher PIN gate is locked.');
      }
      final committed = await repository.commitPrediction(
        document: activeDocument,
        algorithmVersion: pilotPredictionMethodVersion,
        payload: payload,
      );
      document = committed;
      resumableDocument = committed;
      visibleQuestion = null;
      researcherUnlocked = false;
      notifyListeners();
      await _prepareCurrentQuestion();
    });
  }

  Future<void> continueAfterExplanation() async {
    final activeDocument = document;
    if (activeDocument == null) return;
    await _run(() async {
      final committed = await repository.continueAfterExplanation(
        activeDocument,
      );
      document = committed;
      resumableDocument = committed;
      visibleQuestion = null;
      notifyListeners();
      await _prepareCurrentQuestion();
    });
  }

  String exportJson() {
    final activeDocument = document;
    if (activeDocument == null) {
      throw StateError('No validation session is loaded.');
    }
    return buildValidationExport(activeDocument);
  }

  Future<File?> savePilotExport() async {
    File? result;
    await _run(() async {
      final active = document;
      if (active == null) throw StateError('No Pilot session is loaded.');
      final artifact = buildPilotExportArtifact(active);
      final file = await exportWriter.save(artifact);
      exportArtifact = artifact;
      savedExportFile = file;
      result = file;
    });
    return result;
  }

  Future<void> shareSavedPilotExport(Rect sharePositionOrigin) async {
    await _run(() async {
      final active = document;
      final artifact = exportArtifact;
      final file = savedExportFile;
      if (active == null || artifact == null || file == null) {
        throw StateError('Save the durable export before sharing.');
      }
      final sessionBefore = canonicalJson(active.toJson());
      final artifactBytesBefore = List<int>.of(artifact.bytes);
      final fileBytesBefore = await file.readAsBytes();
      _requireMatchingSavedExport(
        document: active,
        artifact: artifact,
        file: file,
        fileBytes: fileBytesBefore,
      );

      await exportTransfer.share(
        PilotExportTransferRequest(
          file: file,
          artifact: artifact,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );

      final fileBytesAfter = await file.readAsBytes();
      _requireMatchingSavedExport(
        document: active,
        artifact: artifact,
        file: file,
        fileBytes: fileBytesAfter,
      );
      if (!identical(document, active) ||
          canonicalJson(active.toJson()) != sessionBefore ||
          !identical(exportArtifact, artifact) ||
          !identical(savedExportFile, file) ||
          !_samePilotExportBytes(artifact.bytes, artifactBytesBefore) ||
          !_samePilotExportBytes(fileBytesAfter, fileBytesBefore)) {
        throw StateError('Sharing modified the completed Pilot export.');
      }
    });
  }

  void _requireMatchingSavedExport({
    required ValidationSessionDocument document,
    required PilotExportArtifact artifact,
    required File file,
    required List<int> fileBytes,
  }) {
    final rebuilt = buildPilotExportArtifact(document);
    if (file.uri.pathSegments.last != artifact.filename ||
        rebuilt.filename != artifact.filename ||
        rebuilt.sha256Digest != artifact.sha256Digest ||
        !_samePilotExportBytes(rebuilt.bytes, artifact.bytes) ||
        !_samePilotExportBytes(fileBytes, artifact.bytes)) {
      throw StateError('Saved Pilot export does not match its artifact.');
    }
  }

  bool _samePilotExportBytes(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }

  Future<void> archiveAndClose() async {
    await _run(() async {
      final active = document;
      if (active == null) throw StateError('No Pilot session is loaded.');
      if (savedExportFile == null || exportArtifact == null) {
        throw StateError('Save the durable export before archiving.');
      }
      await repository.archiveCompleted(active);
      document = null;
      resumableDocument = null;
      visibleQuestion = null;
      pilotPreflight = null;
      researcherUnlocked = false;
      exportArtifact = null;
      savedExportFile = null;
    });
  }

  Future<void> _prepareCurrentQuestion() async {
    final activeDocument = document;
    if (activeDocument == null || !_acceptsQuestion(activeDocument)) return;
    final shown = await repository.ensureQuestionShown(activeDocument);
    document = shown;
    resumableDocument = shown;
    final entry = shown.route.entries[shown.responses.length];
    visibleQuestion = bundle.questionsById[entry.questionId];
    if (visibleQuestion == null) {
      throw StateError('Route question ${entry.questionId} is missing.');
    }
  }

  bool _acceptsQuestion(ValidationSessionDocument value) {
    if (value.responses.length >= value.route.entries.length) return false;
    final phase = value.session.currentPhase;
    return phase == PanelPhase.observed ||
        phase == PanelPhase.heldOut ||
        phase == PanelPhase.replication ||
        phase == PanelPhase.sentinel ||
        phase == PanelPhase.remainingCoverage;
  }

  void _validateLoaded(ValidationSessionDocument loaded) {
    loaded.validate();
    bundle.provenance.requireExpected();
    if (canonicalJson(loaded.session.provenance.toJson()) !=
        canonicalJson(bundle.provenance.toJson())) {
      throw const FormatException('Stored session provenance is stale.');
    }
    if (loaded.assignment.pilotContractVersion != null) {
      pilotProfile.validateAssignment(loaded.assignment);
    }
    final recompiled = PanelRouteCompiler(bundle).compile(loaded.assignment);
    if (canonicalJson(recompiled.toJson()) !=
            canonicalJson(loaded.route.toJson()) ||
        canonicalJson(recompiled.questionIds) !=
            canonicalJson(loaded.session.routeQuestionIds) ||
        recompiled.routeHash != loaded.session.routeHash) {
      throw const FormatException(
        'RESUME REJECT: recompiled assignment route does not match exactly.',
      );
    }
    for (final entry in loaded.route.entries) {
      if (!bundle.questionsById.containsKey(entry.questionId)) {
        throw FormatException(
          'Stored route question ${entry.questionId} is absent.',
        );
      }
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (busy) return;
    busy = true;
    errorMessage = null;
    notifyListeners();
    try {
      await operation();
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}

const referenceAssignmentJson = '''
{
  "assignment_id": "reference-assignment-v1",
  "participant_id": "participant-pseudonym-001",
  "assignment_group": "A",
  "route_version": "reference-route-v1",
  "deep_target_ids": [
    "HAZARD_RISK_M3",
    "THIRD_PARTY",
    "GNSS",
    "AUTO_MANUAL",
    "TEM"
  ],
  "breadth_group_ids": ["HB-1", "HB-2"],
  "sentinel_ids": ["US-A", "US-B", "US-C", "US-D"],
  "coverage_ids": ["COV-01", "COV-39", "COV-52"],
  "pre_s1_coverage_ids": ["COV-01"],
  "replication_form": "A",
  "alternate_slot_selections": {
    "VS-002": "VS-002",
    "VS-005": "VS-005",
    "VS-007": "VS-007",
    "VS-012": "VS-012"
  },
  "coverage_route_classes": {
    "COV-52": "NON_THERMAL_FOG"
  }
}
''';
