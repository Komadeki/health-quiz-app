import 'package:drone_second_class/generated/app_manifest.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';

import 'production_test_support.dart';

void main() {
  testWidgets('Drone renders shared practice/progress/history without V0 UX', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = createProductionController();
    await controller.initialize();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: GeneratedAppManifest.definition,
        controller: controller,
      ),
    );

    expect(find.text('二等無人航空機'), findsOneWidget);
    expect(find.text('教則第5版準拠'), findsOneWidget);
    expect(find.text('学科試験対策'), findsOneWidget);
    expect(
      GeneratedAppManifest.definition.learningProduct.homeHeadline,
      isNot(matches(RegExp(r'全\d+問'))),
    );
    expect(
      find.text('${controller.freeQuestionCount}問を無料で体験'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('overall-progress')), findsOneWidget);
    final performanceChart = find.byKey(const Key('unit-performance-chart'));
    expect(performanceChart, findsOneWidget);
    expect(
      find.descendant(of: performanceChart, matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
    for (final metricKey in [
      'progress-metric-completed',
      'progress-metric-accuracy',
      'progress-metric-review',
      'progress-metric-mock-best',
    ]) {
      expect(find.byKey(Key(metricKey)), findsOneWidget);
    }

    for (final unitKey in [
      'unit-drone_rules',
      'unit-drone_systems',
      'unit-drone_operations',
      'unit-drone_risk_management',
    ]) {
      final unit = find.byKey(Key(unitKey));
      await tester.scrollUntilVisible(unit, 200);
      expect(unit, findsOneWidget);
    }

    await tester.scrollUntilVisible(
      find.byKey(const Key('start-random')),
      300,
    );
    expect(find.byKey(const Key('start-random')), findsOneWidget);
    expect(find.byKey(const Key('start-unanswered')), findsOneWidget);
    expect(find.byKey(const Key('start-incorrect')), findsOneWidget);
    expect(find.byKey(const Key('start-mock-exam')), findsOneWidget);

    for (final forbidden in [
      'VALIDATION ONLY',
      'Researcher PIN',
      'Research Prediction',
      '合格可能性',
      'AI合否',
      '本番力',
    ]) {
      expect(find.textContaining(forbidden), findsNothing);
    }
  });

  testWidgets('Drone answer commit preserves feedback and Explanation', (
    tester,
  ) async {
    final controller = createProductionController();
    await controller.initialize();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: GeneratedAppManifest.definition,
        controller: controller,
      ),
    );
    final rulesUnit = find.byKey(const Key('unit-drone_rules'));
    await tester.scrollUntilVisible(rulesUnit, 200);
    await tester.ensureVisible(rulesUnit);
    await tester.pumpAndSettle();
    await tester.tap(rulesUnit);
    await tester.pump();
    final correctIndex = controller.currentCard!.answerIndex;
    await tester.tap(find.byKey(Key('choice-$correctIndex')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('commit-answer')));
    await tester.pump();

    expect(find.text('正解'), findsOneWidget);
    expect(find.text('解説（Explanation）'), findsOneWidget);
  });
}
