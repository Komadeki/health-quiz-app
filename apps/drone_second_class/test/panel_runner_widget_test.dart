import 'dart:convert';

import 'package:drone_second_class/src/app.dart';
import 'package:drone_second_class/src/domain/panel_route.dart';
import 'package:drone_second_class/src/domain/validation_bundle.dart';
import 'package:drone_second_class/src/presentation/panel_runner_controller.dart';
import 'package:drone_second_class/src/session/session_repository.dart';
import 'package:drone_second_class/src/session/session_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ValidationBundle bundle;

  setUpAll(() async {
    bundle = await loadValidationBundle();
  });

  PanelRunnerController controllerFor(InMemoryValidationSessionStore store) {
    return PanelRunnerController(
      bundle: bundle,
      repository: ValidationSessionRepository(store: store),
    );
  }

  Future<PanelRunnerController> startSmall(
    WidgetTester tester,
    InMemoryValidationSessionStore store,
  ) async {
    final controller = controllerFor(store);
    await controller.startFromJson(jsonEncode(smallAssignment().toJson()));
    await tester.pumpWidget(DroneV0PanelApp(controller: controller));
    await tester.pump();
    return controller;
  }

  testWidgets('AT-21/27 measurement UI never reveals feedback before commit', (
    tester,
  ) async {
    final store = InMemoryValidationSessionStore();
    final controller = await startSmall(tester, store);

    expect(find.byKey(const Key('validation-only-banner')), findsOneWidget);
    expect(find.byKey(const Key('panel-question')), findsOneWidget);
    expect(find.byKey(const Key('explanation-screen')), findsNothing);
    expect(find.textContaining('正解:'), findsNothing);
    for (final label in const <String>[
      '合格可能性%',
      '合格圏',
      '本番力%',
      'AI合否',
      '最短合格',
      '最適学習',
      'Stable',
      'Unstable',
      'Known',
    ]) {
      expect(find.text(label), findsNothing);
    }

    await tester.tap(find.byKey(const Key('choice-0')));
    await tester.pump();
    store.failNextWrite = true;
    await tester.tap(find.byKey(const Key('commit-answer')));
    await tester.pumpAndSettle();

    expect(controller.document!.responses, isEmpty);
    expect(find.byKey(const Key('panel-question')), findsOneWidget);
    expect(find.byKey(const Key('runner-error')), findsOneWidget);
    expect(find.byKey(const Key('explanation-screen')), findsNothing);
  });

  testWidgets(
    'AT-16/22/24-26/28 prediction and assigned-Sentinel gates isolate feedback',
    (tester) async {
      final controller = await startSmall(
        tester,
        InMemoryValidationSessionStore(),
      );

      while (controller.phase == PanelPhase.observed) {
        await controller.commitChoice(0);
      }
      await tester.pump();
      expect(find.byKey(const Key('prediction-gate')), findsOneWidget);
      expect(find.byKey(const Key('panel-question')), findsNothing);
      expect(find.byKey(const Key('explanation-screen')), findsNothing);

      await controller.commitPrediction(
        algorithmVersion: 'external-widget-test',
        payloadSource: '{"opaque":true}',
      );
      await tester.pump();
      expect(controller.phase, PanelPhase.heldOut);
      expect(find.byKey(const Key('panel-question')), findsOneWidget);
      expect(find.textContaining('正解:'), findsNothing);

      while (controller.phase == PanelPhase.heldOut) {
        await controller.commitChoice(0);
      }
      await tester.pump();
      expect(controller.phase, PanelPhase.sentinel);
      expect(find.byKey(const Key('explanation-screen')), findsNothing);

      await controller.commitChoice(0);
      await tester.pump();
      expect(controller.phase, PanelPhase.sentinel);
      expect(find.byKey(const Key('explanation-screen')), findsNothing);
      expect(
        controller.document!.events.any(
          (event) => event.eventType == 'explanation_unlocked',
        ),
        isFalse,
      );

      await controller.commitChoice(0);
      await tester.pump();
      expect(controller.phase, PanelPhase.explanation);
      expect(find.byKey(const Key('explanation-screen')), findsOneWidget);
      expect(find.textContaining('正解:'), findsWidgets);
      final unlock = controller.document!.events.singleWhere(
        (event) => event.eventType == 'explanation_unlocked',
      );
      expect(unlock.payload['assigned_sentinel_count'], 2);
      expect(unlock.eventSeq,
          lessThan(controller.document!.events.last.eventSeq + 1));

      await controller.continueAfterExplanation();
      await tester.pump();
      expect(find.byKey(const Key('session-complete')), findsOneWidget);
      await tester.tap(find.byKey(const Key('generate-export')));
      await tester.pump();
      expect(find.byKey(const Key('export-json')), findsOneWidget);
      final exported = jsonDecode(controller.exportJson())! as Map;
      expect(exported['research_prediction'], isNotNull);
      expect(exported['baseline_candidate_outputs'], isNotNull);
    },
  );

  testWidgets('AT-23 replication UI remains feedback-free', (tester) async {
    final controller = controllerFor(InMemoryValidationSessionStore());
    await controller.startFromJson(
      jsonEncode(
        smallAssignment(m3: true, sentinels: const <String>[]).toJson(),
      ),
    );
    while (controller.phase == PanelPhase.observed) {
      await controller.commitChoice(0);
    }
    await controller.commitPrediction(
      algorithmVersion: 'external-widget-test',
      payloadSource: '{"opaque":true}',
    );
    while (controller.phase == PanelPhase.heldOut) {
      await controller.commitChoice(0);
    }
    expect(controller.phase, PanelPhase.replication);
    await tester.pumpWidget(DroneV0PanelApp(controller: controller));
    await tester.pump();

    expect(find.byKey(const Key('panel-question')), findsOneWidget);
    expect(find.textContaining('正解:'), findsNothing);
    expect(find.byKey(const Key('explanation-screen')), findsNothing);
  });

  testWidgets('AT-29/30 controller resume does not duplicate question_shown', (
    tester,
  ) async {
    final store = InMemoryValidationSessionStore();
    final first = controllerFor(store);
    await first.startFromJson(jsonEncode(smallAssignment().toJson()));
    final shownEvents = first.document!.events
        .where((event) => event.eventType == 'question_shown')
        .length;
    final routeHash = first.document!.route.routeHash;
    final questionId = first.visibleQuestion!.questionId;

    final resumed = controllerFor(store);
    await resumed.initialize();
    await resumed.resume();
    await tester.pumpWidget(DroneV0PanelApp(controller: resumed));
    await tester.pump();

    expect(resumed.document!.route.routeHash, routeHash);
    expect(resumed.visibleQuestion!.questionId, questionId);
    expect(
      resumed.document!.events
          .where((event) => event.eventType == 'question_shown'),
      hasLength(shownEvents),
    );
    expect(find.byKey(const Key('panel-question')), findsOneWidget);
  });
}
