import 'dart:convert';
import 'dart:io';

import 'package:drone_second_class/src/domain/panel_route.dart';
import 'package:drone_second_class/src/domain/validation_provenance.dart';
import 'package:drone_second_class/src/session/session_repository.dart';
import 'package:drone_second_class/src/session/session_storage.dart';
import 'package:drone_second_class/src/session/research_prediction_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'AT-01/12-20,25-26,31-33 enforce Protocol A append-only ordering',
    () async {
      final bundle = await loadValidationBundle();
      final store = InMemoryValidationSessionStore();
      var tick = DateTime.utc(2026, 8, 20, 1);
      final repository = ValidationSessionRepository(
        store: store,
        clock: () {
          tick = tick.add(const Duration(seconds: 1));
          return tick;
        },
      );
      final assignment = smallAssignment();
      final route = PanelRouteCompiler(bundle).compile(assignment);
      var document = await repository.start(
        sessionId: 'session-protocol-a',
        assignment: assignment,
        route: route,
        provenance: bundle.provenance,
      );

      expect(document.snapshots.single.label, 'S0');
      expect(document.snapshots.single.responseIdsIncluded, isEmpty);
      expect(document.snapshots.single.sentinelState, 'UNKNOWN');
      expect(document.responses, isEmpty);

      document = await repository.ensureQuestionShown(document);
      final shownCount = document.events
          .where((event) => event.eventType == 'question_shown')
          .length;
      document = await repository.ensureQuestionShown(document);
      expect(
        document.events.where((event) => event.eventType == 'question_shown'),
        hasLength(shownCount),
      );
      expect(repository.pendingShownEvent(document), isNotNull);
      expect(document.responses, isEmpty);

      while (document.session.currentPhase == PanelPhase.observed) {
        document = await answerCurrent(
          repository: repository,
          document: document,
          bundle: bundle,
        );
      }
      expect(document.session.currentPhase, PanelPhase.predictionGate);
      final s1 = document.snapshots.singleWhere((item) => item.label == 'S1');
      expect(
        document.events.where(
          (event) =>
              event.eventType == 'question_shown' &&
              (event.phase == PanelPhase.heldOut ||
                  event.phase == PanelPhase.sentinel),
        ),
        isEmpty,
      );
      expect(document.baselineCandidateOutputs, isNotNull);
      final evidence = ResearchPredictionEvidence.fromDocument(document);
      expect(
        evidence.observedResponses.every(
          (response) => response.phase == PanelPhase.observed,
        ),
        isTrue,
      );
      expect(
        await const ResearcherCommitGatePredictionProvider().createDraft(
          evidence,
        ),
        isNull,
      );

      document = await repository.commitPrediction(
        document: document,
        algorithmVersion: 'external-research-v-test',
        payload: const <String, Object?>{'prediction': 'opaque'},
      );
      final committedPredictionDocument = document;
      await expectLater(
        repository.commitPrediction(
          document: committedPredictionDocument,
          algorithmVersion: 'edited',
          payload: const <String, Object?>{'prediction': 'changed'},
        ),
        throwsStateError,
      );
      final predictionSeq = document.researchPrediction!.eventSeq;
      document = await repository.ensureQuestionShown(document);
      final firstHeldOut = document.events.firstWhere(
        (event) =>
            event.eventType == 'question_shown' &&
            event.phase == PanelPhase.heldOut,
      );
      expect(firstHeldOut.eventSeq, greaterThan(predictionSeq));

      while (document.session.currentPhase == PanelPhase.heldOut) {
        document = await answerCurrent(
          repository: repository,
          document: document,
          bundle: bundle,
        );
      }
      expect(document.snapshots.any((item) => item.label == 'S2'), isTrue);
      expect(document.snapshots.any((item) => item.label == 'S3'), isFalse);
      expect(document.session.currentPhase, PanelPhase.sentinel);

      document = await answerCurrent(
        repository: repository,
        document: document,
        bundle: bundle,
      );
      expect(document.session.currentPhase, PanelPhase.sentinel);
      expect(
        document.events
            .any((event) => event.eventType == 'explanation_unlocked'),
        isFalse,
      );
      document = await answerCurrent(
        repository: repository,
        document: document,
        bundle: bundle,
      );
      expect(document.session.currentPhase, PanelPhase.explanation);
      final unlock = document.events.singleWhere(
        (event) => event.eventType == 'explanation_unlocked',
      );
      expect(unlock.payload['assigned_sentinel_count'], 2);

      document = await repository.continueAfterExplanation(document);
      expect(document.session.currentPhase, PanelPhase.complete);
      expect(document.session.completedAt, isNotNull);
      expect(
        document.events.map((event) => event.eventSeq),
        orderedEquals(
          List<int>.generate(document.events.length, (index) => index + 1),
        ),
      );
      expect(
        document.responses.every(
          (response) =>
              response.questionId.isNotEmpty &&
              response.questionVersion > 0 &&
              response.bankRevision.isNotEmpty,
        ),
        isTrue,
      );
      for (final snapshot in document.snapshots) {
        expect(
          replayResponseIdsAtSnapshot(document, snapshot),
          snapshot.responseIdsIncluded,
        );
      }
      final reproduced = buildBaselineCandidateOutputs(
        route: document.route,
        responses: document.responses,
        events: document.events,
        eventSeqCutoff: s1.eventSeqCutoff,
      );
      expect(
        canonicalJson(reproduced),
        canonicalJson(document.baselineCandidateOutputs),
      );
      final exported = (jsonDecode(buildValidationExport(document))! as Map)
          .cast<String, Object?>();
      for (final key in const <String>[
        'provenance',
        'assignment',
        'exact_route',
        'responses',
        'events',
        'snapshots',
        'research_prediction',
        'baseline_candidate_outputs',
      ]) {
        expect(exported, contains(key));
      }
    },
  );

  test('AT-27 persistence failure cannot advance or unlock feedback', () async {
    final bundle = await loadValidationBundle();
    final store = InMemoryValidationSessionStore();
    final repository = ValidationSessionRepository(store: store);
    final assignment = smallAssignment();
    var document = await repository.start(
      sessionId: 'session-failure',
      assignment: assignment,
      route: PanelRouteCompiler(bundle).compile(assignment),
      provenance: bundle.provenance,
    );
    document = await repository.ensureQuestionShown(document);
    store.failNextWrite = true;
    final question =
        bundle.questionsById[document.route.entries.first.questionId]!;

    await expectLater(
      repository.commitResponse(
        document: document,
        question: question,
        selectedIndex: 0,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(store.document!.responses, isEmpty);
    expect(store.document!.session.currentPhase, PanelPhase.observed);
    expect(
      store.document!.events.any(
        (event) => event.eventType == 'explanation_unlocked',
      ),
      isFalse,
    );
  });

  test('AT-29/30 resume preserves route and unanswered shown item', () async {
    final bundle = await loadValidationBundle();
    final store = InMemoryValidationSessionStore();
    final repository = ValidationSessionRepository(store: store);
    final assignment = smallAssignment();
    var document = await repository.start(
      sessionId: 'session-resume',
      assignment: assignment,
      route: PanelRouteCompiler(bundle).compile(assignment),
      provenance: bundle.provenance,
    );
    document = await repository.ensureQuestionShown(document);
    final eventCount = document.events.length;
    final loaded = await repository.loadActive();
    final resumed = await repository.ensureQuestionShown(loaded!);

    expect(resumed.route.routeHash, document.route.routeHash);
    expect(resumed.route.questionIds, document.route.questionIds);
    expect(resumed.assignment.toJson(), document.assignment.toJson());
    expect(resumed.session.currentPhase, document.session.currentPhase);
    expect(resumed.events, hasLength(eventCount));
    expect(repository.pendingShownEvent(resumed)!.questionId,
        document.route.entries.first.questionId);
  });

  test('AT-20 creates S3 only after the assigned M3 form completes', () async {
    final bundle = await loadValidationBundle();
    final repository = ValidationSessionRepository(
      store: InMemoryValidationSessionStore(),
    );
    final assignment = smallAssignment(m3: true, sentinels: const <String>[]);
    var document = await repository.start(
      sessionId: 'session-m3',
      assignment: assignment,
      route: PanelRouteCompiler(bundle).compile(assignment),
      provenance: bundle.provenance,
    );
    while (document.session.currentPhase == PanelPhase.observed) {
      document = await answerCurrent(
        repository: repository,
        document: document,
        bundle: bundle,
      );
    }
    document = await repository.commitPrediction(
      document: document,
      algorithmVersion: 'external-test',
      payload: const <String, Object?>{'value': 1},
    );
    while (document.session.currentPhase == PanelPhase.heldOut) {
      document = await answerCurrent(
        repository: repository,
        document: document,
        bundle: bundle,
      );
    }
    expect(document.snapshots.any((item) => item.label == 'S3'), isFalse);
    expect(document.session.currentPhase, PanelPhase.replication);
    document = await answerCurrent(
      repository: repository,
      document: document,
      bundle: bundle,
    );
    expect(
        document.snapshots.where((item) => item.label == 'S3'), hasLength(1));
    expect(document.session.currentPhase, PanelPhase.explanation);
  });

  test('file store atomically replaces and reloads the active session',
      () async {
    final bundle = await loadValidationBundle();
    final temporary = await Directory.systemTemp.createTemp('v0-panel-store-');
    try {
      final store = FileValidationSessionStore(
        supportDirectory: () async => temporary,
      );
      final repository = ValidationSessionRepository(store: store);
      final assignment = smallAssignment();
      var document = await repository.start(
        sessionId: 'session-file-store',
        assignment: assignment,
        route: PanelRouteCompiler(bundle).compile(assignment),
        provenance: bundle.provenance,
      );
      document = await repository.ensureQuestionShown(document);
      final loaded = await store.loadActive();
      expect(loaded!.session.sessionId, document.session.sessionId);
      expect(loaded.route.routeHash, document.route.routeHash);
      expect(repository.pendingShownEvent(loaded), isNotNull);
      expect(
        File(
          '${temporary.path}/drone_v0_panel/sessions/'
          'session-file-store.json.tmp',
        ).existsSync(),
        isFalse,
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  });
}
