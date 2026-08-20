import '../domain/panel_route.dart';
import 'session_models.dart';

class ResearchPredictionEvidence {
  const ResearchPredictionEvidence({
    required this.snapshot,
    required this.observedResponses,
  });

  final ValidationSnapshot snapshot;
  final List<ValidationResponse> observedResponses;

  factory ResearchPredictionEvidence.fromDocument(
    ValidationSessionDocument document,
  ) {
    final s1 = document.snapshots.singleWhere((item) => item.label == 'S1');
    final responses = document.responses.where((response) {
      final entry = document.route.entries[response.presentationIndex];
      return response.phase == PanelPhase.observed &&
          entry.measurement &&
          s1.responseIdsIncluded.contains(response.responseId);
    }).toList(growable: false);
    return ResearchPredictionEvidence(
      snapshot: s1,
      observedResponses: responses,
    );
  }
}

class ResearchPredictionDraft {
  const ResearchPredictionDraft({
    required this.algorithmVersion,
    required this.payload,
  });

  final String algorithmVersion;
  final Map<String, Object?> payload;
}

abstract interface class ResearchPredictionProvider {
  Future<ResearchPredictionDraft?> createDraft(
    ResearchPredictionEvidence evidence,
  );
}

/// V0P-2 deliberately produces no algorithmic draft. A researcher supplies the
/// immutable version and JSON payload through the explicit commit gate.
class ResearcherCommitGatePredictionProvider
    implements ResearchPredictionProvider {
  const ResearcherCommitGatePredictionProvider();

  @override
  Future<ResearchPredictionDraft?> createDraft(
    ResearchPredictionEvidence evidence,
  ) async =>
      null;
}
