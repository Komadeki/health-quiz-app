import 'dart:convert';
import 'dart:io';

import 'package:drone_second_class/src/app.dart';
import 'package:drone_second_class/src/domain/panel_assignment.dart';
import 'package:drone_second_class/src/domain/panel_route.dart';
import 'package:drone_second_class/src/domain/pilot_profile.dart';
import 'package:drone_second_class/src/domain/validation_provenance.dart';
import 'package:drone_second_class/src/presentation/panel_runner_controller.dart';
import 'package:drone_second_class/src/presentation/pilot_export_transfer.dart';
import 'package:drone_second_class/src/session/pilot_export.dart';
import 'package:drone_second_class/src/session/pilot_prediction.dart';
import 'package:drone_second_class/src/session/session_models.dart';
import 'package:drone_second_class/src/session/session_repository.dart';
import 'package:drone_second_class/src/session/session_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const profile = DroneV0P3PilotProfile();

  Map<String, Object?> validPrediction(ValidationSessionDocument document) {
    final plan = PilotPredictionPlan.fromDocument(document);
    return <String, Object?>{
      'schema_version': 1,
      'method_version': pilotPredictionMethodVersion,
      's1_snapshot_id': plan.s1SnapshotId,
      'predictions': plan.targets
          .map(
            (target) => <String, Object?>{
              'prediction_key': target.predictionKey,
              'target_id': target.targetId,
              'predicted_outcome': 'CORRECT',
              'confidence': 2,
              'evidence_response_ids': target.evidenceResponseIds,
            },
          )
          .toList(growable: false),
    };
  }

  Future<ValidationSessionDocument> reachS1({
    required ValidationSessionRepository repository,
    required ValidationSessionDocument document,
    required dynamic bundle,
  }) async {
    var current = document;
    while (current.session.currentPhase == PanelPhase.observed) {
      current = await answerCurrent(
        repository: repository,
        document: current,
        bundle: bundle,
      );
    }
    return current;
  }

  Future<ValidationSessionDocument> completePilot({
    required ValidationSessionRepository repository,
    required ValidationSessionDocument document,
    required dynamic bundle,
  }) async {
    var current = await reachS1(
      repository: repository,
      document: document,
      bundle: bundle,
    );
    current = await repository.commitPrediction(
      document: current,
      algorithmVersion: pilotPredictionMethodVersion,
      payload: validPrediction(current),
    );
    while (current.session.currentPhase == PanelPhase.heldOut ||
        current.session.currentPhase == PanelPhase.replication ||
        current.session.currentPhase == PanelPhase.sentinel) {
      current = await answerCurrent(
        repository: repository,
        document: current,
        bundle: bundle,
      );
    }
    expect(current.session.currentPhase, PanelPhase.explanation);
    current = await repository.continueAfterExplanation(current);
    while (current.session.currentPhase == PanelPhase.remainingCoverage) {
      current = await answerCurrent(
        repository: repository,
        document: current,
        bundle: bundle,
      );
    }
    expect(current.session.currentPhase, PanelPhase.complete);
    return current;
  }

  Future<PanelRunnerController> pumpPilotAtPredictionGate(
    WidgetTester tester, {
    required InMemoryValidationSessionStore store,
    required String participantId,
    required String researcherPin,
  }) async {
    final bundle = (await tester.runAsync(loadValidationBundle))!;
    final controller = PanelRunnerController(
      bundle: bundle,
      repository: ValidationSessionRepository(store: store),
      researcherPin: researcherPin,
    );
    await controller.compilePilot(
      assignmentSlotId: 'EXT-S01',
      participantId: participantId,
    );
    await controller.confirmPilotPreflight();
    for (var index = 0;
        index < 40 && controller.phase == PanelPhase.observed;
        index += 1) {
      await controller.commitChoice(0);
      expect(controller.errorMessage, isNull);
    }
    expect(controller.phase, PanelPhase.predictionGate);
    await tester.pumpWidget(DroneV0PanelApp(controller: controller));
    await tester.pump();
    return controller;
  }

  test('AT-18/19 Preflight is non-durable until operator Confirm', () async {
    final bundle = await loadValidationBundle();
    final store = InMemoryValidationSessionStore();
    final controller = PanelRunnerController(
      bundle: bundle,
      repository: ValidationSessionRepository(store: store),
      researcherPin: '4921',
    );

    await controller.compilePilot(
      assignmentSlotId: 'EXT-S01',
      participantId: 'V0P3-I001',
    );
    expect(controller.pilotPreflight, isNotNull);
    expect(store.document, isNull);
    expect(controller.document, isNull);

    await controller.confirmPilotPreflight();
    final events = controller.document!.events;
    expect(events[0].eventType, 'session_started');
    expect(events[1].eventType, 'snapshot_saved');
    expect(events[1].payload['label'], 'S0');
    expect(events[2].eventType, 'phase_started');
    expect(events[3].eventType, 'question_shown');
    expect(events[0].eventSeq, lessThan(events[3].eventSeq));
  });

  testWidgets(
      'AT-20..23 / AT-PIN-01 correct PIN dialog unlocks without exception',
      (tester) async {
    final store = InMemoryValidationSessionStore();
    final controller = await pumpPilotAtPredictionGate(
      tester,
      store: store,
      participantId: 'V0P3-I002',
      researcherPin: '4921',
    );

    expect(find.byKey(const Key('participant-handoff')), findsOneWidget);
    expect(
      find.text(
        'ここで端末を担当者へ渡してください。\n'
        '端末には触れず、そのままお待ちください。',
      ),
      findsOneWidget,
    );
    await controller
        .commitPilotPrediction(validPrediction(controller.document!));
    expect(controller.document!.researchPrediction, isNull);

    await tester.longPress(find.byKey(const Key('participant-handoff')));
    await tester.pumpAndSettle();
    expect(find.text('Researcher PIN'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('researcher-pin')), '4921');
    await tester.tap(find.byKey(const Key('unlock-researcher')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(controller.researcherUnlocked, isTrue);
    expect(
        find.byKey(const Key('pilot-researcher-prediction')), findsOneWidget);

    final bundle = controller.bundle;
    final document = controller.document!;
    final heldOut = document.route.entries.firstWhere(
      (entry) => entry.phase == PanelPhase.heldOut,
    );
    final sentinel = document.route.entries.firstWhere(
      (entry) => entry.phase == PanelPhase.sentinel,
    );
    final remaining = document.route.entries.firstWhere(
      (entry) => entry.phase == PanelPhase.remainingCoverage,
    );
    for (final entry in <PanelRouteEntry>[heldOut, sentinel, remaining]) {
      final question = bundle.questionsById[entry.questionId]!;
      expect(find.text(question.prompt), findsNothing);
      expect(find.text(question.explanation), findsNothing);
      for (final choice in question.choices) {
        expect(find.textContaining(choice), findsNothing);
      }
    }
    final durableJson = jsonEncode(document.toJson());
    expect(durableJson, isNot(contains('4921')));
  });

  testWidgets('AT-PIN-02 wrong PIN closes safely and keeps handoff',
      (tester) async {
    final controller = await pumpPilotAtPredictionGate(
      tester,
      store: InMemoryValidationSessionStore(),
      participantId: 'V0P3-I003',
      researcherPin: '4921',
    );

    await tester.longPress(find.byKey(const Key('participant-handoff')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('researcher-pin')), 'wrong');
    await tester.tap(find.byKey(const Key('unlock-researcher')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(controller.researcherUnlocked, isFalse);
    expect(controller.errorMessage, 'Researcher PIN rejected.');
    expect(find.byKey(const Key('participant-handoff')), findsOneWidget);
    expect(find.byKey(const Key('pilot-researcher-prediction')), findsNothing);
  });

  testWidgets('AT-PIN-03 Cancel closes safely and keeps handoff',
      (tester) async {
    final controller = await pumpPilotAtPredictionGate(
      tester,
      store: InMemoryValidationSessionStore(),
      participantId: 'V0P3-I004',
      researcherPin: '4921',
    );

    await tester.longPress(find.byKey(const Key('participant-handoff')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('researcher-pin')), '4921');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(controller.researcherUnlocked, isFalse);
    expect(controller.errorMessage, isNull);
    expect(find.byKey(const Key('participant-handoff')), findsOneWidget);
    expect(find.byKey(const Key('pilot-researcher-prediction')), findsNothing);
  });

  testWidgets('AT-PIN-04 PIN is absent from durable session and export',
      (tester) async {
    const pin = 'pin-value-must-not-persist-92841';
    final store = InMemoryValidationSessionStore();
    final controller = await pumpPilotAtPredictionGate(
      tester,
      store: store,
      participantId: 'V0P3-I005',
      researcherPin: pin,
    );

    await tester.longPress(find.byKey(const Key('participant-handoff')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('researcher-pin')), pin);
    await tester.tap(find.byKey(const Key('unlock-researcher')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(controller.researcherUnlocked, isTrue);
    expect(jsonEncode(store.document!.toJson()), isNot(contains(pin)));
    expect(controller.exportJson(), isNot(contains(pin)));
  });

  test('AT-20/21 empty or wrong PIN fails closed without persistence',
      () async {
    final bundle = await loadValidationBundle();
    final emptyStore = InMemoryValidationSessionStore();
    final emptyPinController = PanelRunnerController(
      bundle: bundle,
      repository: ValidationSessionRepository(store: emptyStore),
      researcherPin: '',
    );
    await emptyPinController.compilePilot(
      assignmentSlotId: 'EXT-S01',
      participantId: 'V0P3-I010',
    );
    await emptyPinController.confirmPilotPreflight();
    expect(emptyPinController.document, isNull);
    expect(emptyStore.document, isNull);
    expect(emptyPinController.errorMessage, contains('not configured'));

    for (final configuredPin in <String>['', '4921']) {
      final controller = PanelRunnerController(
        bundle: bundle,
        repository: ValidationSessionRepository(
          store: InMemoryValidationSessionStore(),
        ),
        researcherPin: configuredPin,
      );
      controller.unlockResearcher('wrong');
      expect(controller.researcherUnlocked, isFalse);
      expect(controller.errorMessage, isNotNull);
    }
  });

  test('AT-24..28 Structured Prediction is exact and immutable', () async {
    final bundle = await loadValidationBundle();
    final repository = ValidationSessionRepository(
      store: InMemoryValidationSessionStore(),
    );
    final assignment = profile.assignment(
      slotId: 'EXT-S02',
      participantId: 'V0P3-E001',
    );
    var document = await repository.start(
      sessionId: 'v0p3-prediction-contract',
      assignment: assignment,
      route: PanelRouteCompiler(bundle).compile(assignment),
      provenance: bundle.provenance,
    );
    document = await reachS1(
      repository: repository,
      document: document,
      bundle: bundle,
    );
    final valid = validPrediction(document);
    final predictions = (valid['predictions']! as List)
        .map((item) => Map<String, Object?>.from(item! as Map))
        .toList();

    await expectLater(
      repository.commitPrediction(
        document: document,
        algorithmVersion: pilotPredictionMethodVersion,
        payload: <String, Object?>{
          ...valid,
          'predictions': predictions.sublist(1),
        },
      ),
      throwsFormatException,
    );
    await expectLater(
      repository.commitPrediction(
        document: document,
        algorithmVersion: pilotPredictionMethodVersion,
        payload: <String, Object?>{
          ...valid,
          'predictions': <Object?>[
            ...predictions,
            <String, Object?>{
              ...predictions.first,
              'prediction_key': 'HP-999',
            },
          ],
        },
      ),
      throwsFormatException,
    );
    final invalidEvidence =
        predictions.map((item) => Map<String, Object?>.from(item)).toList();
    invalidEvidence.first['evidence_response_ids'] = <String>['outside-S1'];
    await expectLater(
      repository.commitPrediction(
        document: document,
        algorithmVersion: pilotPredictionMethodVersion,
        payload: <String, Object?>{
          ...valid,
          'predictions': invalidEvidence,
        },
      ),
      throwsFormatException,
    );

    document = await repository.commitPrediction(
      document: document,
      algorithmVersion: pilotPredictionMethodVersion,
      payload: valid,
    );
    expect(
      (document.researchPrediction!.predictionPayload['predictions']! as List),
      hasLength(PilotPredictionPlan.fromDocument(document).targets.length),
    );
    await expectLater(
      repository.commitPrediction(
        document: document,
        algorithmVersion: pilotPredictionMethodVersion,
        payload: valid,
      ),
      throwsStateError,
    );
  });

  test('AT-29..31 Simple Baseline freezes at S1 and stays researcher-blind',
      () async {
    final bundle = await loadValidationBundle();
    final repository = ValidationSessionRepository(
      store: InMemoryValidationSessionStore(),
    );
    final assignment = profile.assignment(
      slotId: 'EXT-S03',
      participantId: 'V0P3-I003',
    );
    var document = await repository.start(
      sessionId: 'v0p3-baseline-freeze',
      assignment: assignment,
      route: PanelRouteCompiler(bundle).compile(assignment),
      provenance: bundle.provenance,
    );
    document = await reachS1(
      repository: repository,
      document: document,
      bundle: bundle,
    );
    final frozen = canonicalJson(document.preRegisteredSimpleBaseline);
    expect(frozen, contains(preRegisteredSimpleBaselineVersion));
    expect(frozen, contains(sameTargetAllCorrectRuleVersion));
    expect(
      PilotPredictionPlan.fromDocument(document)
          .targets
          .expand((target) => target.evidenceResponseIds),
      everyElement(
        isIn(
          document.responses
              .where((response) => response.phase == PanelPhase.observed)
              .map((response) => response.responseId),
        ),
      ),
    );
    document = await repository.commitPrediction(
      document: document,
      algorithmVersion: pilotPredictionMethodVersion,
      payload: validPrediction(document),
    );
    document = await answerCurrent(
      repository: repository,
      document: document,
      bundle: bundle,
      selectedIndex: 1,
    );
    expect(canonicalJson(document.preRegisteredSimpleBaseline), frozen);
  });

  test('AT-32..35 resume recompiles exact route and preserves crash boundary',
      () async {
    final bundle = await loadValidationBundle();
    final store = InMemoryValidationSessionStore();
    final repository = ValidationSessionRepository(store: store);
    final assignment = profile.assignment(
      slotId: 'EXT-S04',
      participantId: 'V0P3-I004',
    );
    var document = await repository.start(
      sessionId: 'v0p3-resume',
      assignment: assignment,
      route: PanelRouteCompiler(bundle).compile(assignment),
      provenance: bundle.provenance,
    );
    document = await repository.ensureQuestionShown(document);
    final firstQuestion = document.route.entries.first.questionId;

    final resumed = PanelRunnerController(
      bundle: bundle,
      repository: repository,
      researcherPin: '4921',
    );
    await resumed.initialize();
    await resumed.resume();
    expect(resumed.visibleQuestion!.questionId, firstQuestion);
    expect(
      resumed.document!.events
          .where((event) => event.eventType == 'question_shown'),
      hasLength(1),
    );
    await resumed.commitChoice(0);
    final responseCount = resumed.document!.responses.length;
    final committedId = resumed.document!.responses.single.responseId;

    final afterCommit = PanelRunnerController(
      bundle: bundle,
      repository: repository,
      researcherPin: '4921',
    );
    await afterCommit.initialize();
    await afterCommit.resume();
    expect(afterCommit.document!.responses, hasLength(responseCount));
    expect(afterCommit.document!.responses.single.responseId, committedId);

    final alteredAssignment = PanelAssignmentV1.fromJson(<String, Object?>{
      ...afterCommit.document!.assignment.toJson(),
      'coverage_ids': <String>[
        ...afterCommit.document!.assignment.coverageIds.take(9),
        'COV-55',
      ],
    });
    final tampered = ValidationSessionDocument(
      session: afterCommit.document!.session,
      assignment: alteredAssignment,
      route: afterCommit.document!.route,
      responses: afterCommit.document!.responses,
      events: afterCommit.document!.events,
      snapshots: afterCommit.document!.snapshots,
      researchPrediction: afterCommit.document!.researchPrediction,
      baselineCandidateOutputs: afterCommit.document!.baselineCandidateOutputs,
      preRegisteredSimpleBaseline:
          afterCommit.document!.preRegisteredSimpleBaseline,
    );
    final rejected = PanelRunnerController(
      bundle: bundle,
      repository: ValidationSessionRepository(store: _StaticStore(tampered)),
      researcherPin: '4921',
    );
    await rejected.initialize();
    expect(rejected.canResume, isFalse);
    expect(rejected.errorMessage, contains('Resume data rejected'));
  });

  test('AT-36..40 archive turnover and export are byte deterministic',
      () async {
    final bundle = await loadValidationBundle();
    final store = InMemoryValidationSessionStore();
    var tick = DateTime.utc(2026, 8, 20, 3);
    final repository = ValidationSessionRepository(
      store: store,
      clock: () {
        tick = tick.add(const Duration(seconds: 1));
        return tick;
      },
    );
    final assignmentA = profile.assignment(
      slotId: 'EXT-S06',
      participantId: 'V0P3-E006',
    );
    var sessionA = await repository.start(
      sessionId: 'v0p3-session-a',
      assignment: assignmentA,
      route: PanelRouteCompiler(bundle).compile(assignmentA),
      provenance: bundle.provenance,
    );
    await expectLater(
      repository.start(
        sessionId: 'blocked-active',
        assignment: profile.assignment(
          slotId: 'EXT-S07',
          participantId: 'V0P3-E007',
        ),
        route: PanelRouteCompiler(bundle).compile(
          profile.assignment(
            slotId: 'EXT-S07',
            participantId: 'V0P3-E007',
          ),
        ),
        provenance: bundle.provenance,
      ),
      throwsStateError,
    );
    sessionA = await completePilot(
      repository: repository,
      document: sessionA,
      bundle: bundle,
    );
    final usBQuestionId = sessionA.route.entries
        .singleWhere((entry) => entry.analysisGroup == 'US-B')
        .questionId;
    final cov39QuestionId = sessionA.route.entries
        .singleWhere((entry) => entry.analysisGroup == 'COV-39')
        .questionId;
    final usBResponseId = sessionA.responses
        .singleWhere((response) => response.questionId == usBQuestionId)
        .responseId;
    final usBCommitted = sessionA.events.singleWhere(
      (event) =>
          event.eventType == 'response_committed' &&
          event.payload['response_id'] == usBResponseId,
    );
    final cov39Shown = sessionA.events.singleWhere(
      (event) =>
          event.eventType == 'question_shown' &&
          event.questionId == cov39QuestionId,
    );
    expect(usBCommitted.eventSeq, lessThan(cov39Shown.eventSeq));
    final beforeArchive = canonicalJson(sessionA.toJson());
    final artifact1 = buildPilotExportArtifact(sessionA);
    final artifact2 = buildPilotExportArtifact(sessionA);
    expect(artifact2.filename, artifact1.filename);
    expect(artifact2.sha256Digest, artifact1.sha256Digest);
    expect(artifact2.bytes, artifact1.bytes);
    expect(
      artifact1.filename,
      startsWith('v0p3_V0P3-E006_v0p3-session-a_EXT-S06_'),
    );
    final exported = (jsonDecode(utf8.decode(artifact1.bytes))! as Map)
        .cast<String, Object?>();
    for (final key in const <String>[
      'provenance',
      'assignment',
      'exact_route',
      'responses',
      'events',
      'snapshots',
      'research_prediction',
      'pre_registered_simple_baseline',
    ]) {
      expect(exported, contains(key));
    }
    final temporary = await Directory.systemTemp.createTemp('v0p3-export-');
    try {
      final writer = PilotExportWriter(
        supportDirectory: () async => temporary,
      );
      final firstFile = await writer.save(artifact1);
      final firstBytes = await firstFile.readAsBytes();
      final secondFile = await writer.save(artifact2);
      expect(secondFile.path, firstFile.path);
      expect(await secondFile.readAsBytes(), firstBytes);
    } finally {
      await temporary.delete(recursive: true);
    }

    await repository.archiveCompleted(sessionA);
    expect(store.document, isNull);
    expect(canonicalJson(store.archived['v0p3-session-a']!.toJson()),
        beforeArchive);
    await expectLater(
      repository.start(
        sessionId: 'duplicate-external',
        assignment: assignmentA,
        route: PanelRouteCompiler(bundle).compile(assignmentA),
        provenance: bundle.provenance,
      ),
      throwsStateError,
    );

    final assignmentB = profile.assignment(
      slotId: 'EXT-S07',
      participantId: 'V0P3-E007',
    );
    await repository.start(
      sessionId: 'v0p3-session-b',
      assignment: assignmentB,
      route: PanelRouteCompiler(bundle).compile(assignmentB),
      provenance: bundle.provenance,
    );
    expect(canonicalJson(store.archived['v0p3-session-a']!.toJson()),
        beforeArchive);
  });

  test('AT-36 file store archive preserves completed session bytes', () async {
    final bundle = await loadValidationBundle();
    final temporary = await Directory.systemTemp.createTemp('v0p3-archive-');
    try {
      final store = FileValidationSessionStore(
        supportDirectory: () async => temporary,
      );
      final repository = ValidationSessionRepository(store: store);
      final assignment = profile.assignment(
        slotId: 'EXT-S10',
        participantId: 'V0P3-E010',
      );
      var document = await repository.start(
        sessionId: 'v0p3-file-session-a',
        assignment: assignment,
        route: PanelRouteCompiler(bundle).compile(assignment),
        provenance: bundle.provenance,
      );
      document = await completePilot(
        repository: repository,
        document: document,
        bundle: bundle,
      );
      final active = File(
        '${temporary.path}/drone_v0_panel/sessions/'
        'v0p3-file-session-a.json',
      );
      final completedBytes = await active.readAsBytes();
      await repository.archiveCompleted(document);
      final archived = File(
        '${temporary.path}/drone_v0_panel/archive/'
        'v0p3-file-session-a.json',
      );
      expect(await archived.readAsBytes(), completedBytes);
      expect(active.existsSync(), isFalse);
      expect(
        File('${temporary.path}/drone_v0_panel/active_session_id.txt')
            .existsSync(),
        isFalse,
      );
    } finally {
      await temporary.delete(recursive: true);
    }
  });

  testWidgets('AT-47..51 saved JSON file transfer preserves exact custody',
      (tester) async {
    final bundle = (await tester.runAsync(loadValidationBundle))!;
    final temporary = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('v0p3-share-'),
    ))!;
    try {
      final store = InMemoryValidationSessionStore();
      var tick = DateTime.utc(2026, 8, 20, 8);
      final repository = ValidationSessionRepository(
        store: store,
        clock: () {
          tick = tick.add(const Duration(seconds: 1));
          return tick;
        },
      );
      final assignment = profile.assignment(
        slotId: 'EXT-S09',
        participantId: 'V0P3-E009',
      );
      final completed = (await tester.runAsync(() async {
        final started = await repository.start(
          sessionId: 'v0p3-share-session',
          assignment: assignment,
          route: PanelRouteCompiler(bundle).compile(assignment),
          provenance: bundle.provenance,
        );
        return completePilot(
          repository: repository,
          document: started,
          bundle: bundle,
        );
      }))!;
      final transfer = _RecordingPilotExportTransfer();
      final controller = PanelRunnerController(
        bundle: bundle,
        repository: repository,
        exportWriter: PilotExportWriter(
          supportDirectory: () async => temporary,
        ),
        exportTransfer: transfer,
        researcherPin: '4921',
      )..document = completed;
      await tester.runAsync(controller.savePilotExport);
      final firstArtifact = controller.exportArtifact!;
      final firstFile = controller.savedExportFile!;
      final sessionBefore = canonicalJson(completed.toJson());

      await tester.pumpWidget(DroneV0PanelApp(controller: controller));
      await tester.pump();
      expect(find.text('Save JSON file'), findsOneWidget);
      expect(find.byKey(const Key('export-filename')), findsOneWidget);
      expect(find.byKey(const Key('export-sha256')), findsOneWidget);
      expect(find.text('Share saved JSON file'), findsOneWidget);
      expect(find.byKey(const Key('export-path')), findsNothing);

      final shareButton = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Share saved JSON file'),
          matching: find.byWidgetPredicate(
            (widget) => widget is OutlinedButton,
          ),
        ),
      );
      expect(shareButton.onPressed, isNotNull);
      await tester.runAsync(
        () async {
          shareButton.onPressed!();
          for (var wait = 0; wait < 1000 && controller.busy; wait += 1) {
            await Future<void>.delayed(const Duration(milliseconds: 1));
          }
        },
      );
      await tester.pump();

      expect(controller.busy, isFalse);
      expect(controller.errorMessage, isNull);
      expect(transfer.requests, hasLength(1));
      expect(transfer.requests.single.file, same(firstFile));
      expect(transfer.requests.single.artifact, same(firstArtifact));
      expect(transfer.sharedBytes.single, firstArtifact.bytes);
      expect(
          transfer.requests.single.sharePositionOrigin.width, greaterThan(0));
      expect(
        transfer.requests.single.sharePositionOrigin.height,
        greaterThan(0),
      );
      expect(
        transfer.requests.single.file.uri.pathSegments.last,
        firstArtifact.filename,
      );
      expect(controller.document, same(completed));
      expect(canonicalJson(controller.document!.toJson()), sessionBefore);
      expect(controller.exportArtifact, same(firstArtifact));
      expect(controller.savedExportFile, same(firstFile));
      expect(controller.exportArtifact!.bytes, firstArtifact.bytes);
      expect(controller.exportArtifact!.filename, firstArtifact.filename);
      expect(
        controller.exportArtifact!.sha256Digest,
        firstArtifact.sha256Digest,
      );

      await tester.runAsync(controller.savePilotExport);
      final secondArtifact = controller.exportArtifact!;
      final secondFile = controller.savedExportFile!;
      await tester.runAsync(
        () => controller.shareSavedPilotExport(
          const Rect.fromLTWH(0, 0, 1, 1),
        ),
      );

      expect(controller.errorMessage, isNull);
      expect(transfer.requests, hasLength(2));
      expect(secondFile.path, firstFile.path);
      expect(secondArtifact.filename, firstArtifact.filename);
      expect(secondArtifact.bytes, firstArtifact.bytes);
      expect(secondArtifact.sha256Digest, firstArtifact.sha256Digest);
      expect(transfer.sharedBytes[1], firstArtifact.bytes);
      expect(canonicalJson(controller.document!.toJson()), sessionBefore);
    } finally {
      await tester.runAsync(() => temporary.delete(recursive: true));
    }
  });

  test('AT-43/44 production runtime stays empty and IDs stay <= 100', () async {
    final runtime = (jsonDecode(
      await File('assets/question_bank/drone_second_class_bank.json')
          .readAsString(),
    )! as Map)
        .cast<String, Object?>();
    expect(runtime['decks'], isEmpty);
    expect(runtime['examProfileVersion'], 'drone-second-class-unreleased');
    final bundle = await loadValidationBundle();
    expect(bundle.questions, hasLength(100));
    expect(
      bundle.questions
          .map((question) => int.parse(question.questionId.split('-').last))
          .reduce((left, right) => left > right ? left : right),
      100,
    );
  });
}

class _StaticStore implements ValidationSessionStore {
  _StaticStore(this.document);

  final ValidationSessionDocument document;

  @override
  Future<void> archive(ValidationSessionDocument document) async =>
      throw UnsupportedError('read only');

  @override
  Future<bool> hasParticipant(String participantId) async => false;

  @override
  Future<ValidationSessionDocument?> loadActive() async => document;

  @override
  Future<void> write(ValidationSessionDocument document) async =>
      throw UnsupportedError('read only');
}

class _RecordingPilotExportTransfer implements PilotExportTransfer {
  final List<PilotExportTransferRequest> requests =
      <PilotExportTransferRequest>[];
  final List<List<int>> sharedBytes = <List<int>>[];

  @override
  Future<void> share(PilotExportTransferRequest request) async {
    requests.add(request);
    sharedBytes.add(await request.file.readAsBytes());
  }
}
