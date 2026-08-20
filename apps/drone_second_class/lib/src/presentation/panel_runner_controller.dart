import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/panel_assignment.dart';
import '../domain/panel_route.dart';
import '../domain/validation_bundle.dart';
import '../domain/validation_provenance.dart';
import '../session/session_models.dart';
import '../session/session_repository.dart';
import '../session/research_prediction_provider.dart';

class PanelRunnerController extends ChangeNotifier {
  PanelRunnerController({
    required this.bundle,
    required this.repository,
    this.predictionProvider = const ResearcherCommitGatePredictionProvider(),
  });

  final ValidationBundle bundle;
  final ValidationSessionRepository repository;
  final ResearchPredictionProvider predictionProvider;

  ValidationSessionDocument? document;
  ValidationSessionDocument? resumableDocument;
  ValidationQuestion? visibleQuestion;
  bool busy = false;
  String? errorMessage;

  PanelPhase? get phase => document?.session.currentPhase;

  bool get canResume => resumableDocument != null;

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

  Future<void> resume() async {
    await _run(() async {
      final loaded = resumableDocument;
      if (loaded == null) throw StateError('No session is available.');
      _validateLoaded(loaded);
      document = loaded;
      visibleQuestion = null;
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
            'Prediction payload must be a JSON object.');
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

  Future<void> continueAfterExplanation() async {
    final activeDocument = document;
    if (activeDocument == null) return;
    await _run(() async {
      final committed =
          await repository.continueAfterExplanation(activeDocument);
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
    for (final entry in loaded.route.entries) {
      if (!bundle.questionsById.containsKey(entry.questionId)) {
        throw FormatException(
            'Stored route question ${entry.questionId} is absent.');
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
