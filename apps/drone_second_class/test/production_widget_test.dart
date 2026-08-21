import 'package:drone_second_class/generated/app_manifest.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';

import 'production_test_support.dart';

void main() {
  testWidgets('Drone renders shared practice/progress/history without V0 UX', (
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

    expect(find.text('二等無人航空機 学科対策'), findsOneWidget);
    expect(find.text('教則第5版を基にした全100問'), findsOneWidget);
    expect(find.byKey(const Key('unit-drone_rules')), findsOneWidget);
    expect(find.byKey(const Key('unit-drone_systems')), findsOneWidget);
    expect(find.byKey(const Key('unit-drone_operations')), findsOneWidget);
    expect(find.byKey(const Key('unit-drone_risk_management')), findsOneWidget);
    expect(find.byKey(const Key('overall-progress')), findsOneWidget);
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
    await tester.tap(find.byKey(const Key('unit-drone_rules')));
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
