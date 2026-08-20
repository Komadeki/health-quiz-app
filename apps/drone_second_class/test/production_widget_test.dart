import 'package:drone_second_class/production/production_app.dart';
import 'package:drone_second_class/production/production_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'production_test_support.dart';

void main() {
  Future<DroneProductionController> createController() async {
    final controller = DroneProductionController(
      bankLoader: FixedDroneBankLoader(loadProductionBank()),
      sessionStore: MemoryDroneSessionStore(),
      purchaseGateway: FakeDronePurchaseGateway(),
      entitlementCache: MemoryDroneEntitlementCache(),
    );
    await controller.initialize();
    return controller;
  }

  testWidgets('production Home shows four units and no validation-only UX',
      (tester) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(DroneProductionApp(controller: controller));

    expect(find.text('二等無人航空機 学科対策'), findsOneWidget);
    expect(find.text('教則第5版を基にした全100問'), findsOneWidget);
    expect(find.byKey(const Key('unit-drone_rules')), findsOneWidget);
    expect(find.byKey(const Key('unit-drone_systems')), findsOneWidget);
    expect(find.byKey(const Key('unit-drone_operations')), findsOneWidget);
    expect(find.byKey(const Key('unit-drone_risk_management')), findsOneWidget);
    expect(find.byKey(const Key('resume-session')), findsNothing);

    for (final forbidden in [
      'VALIDATION ONLY',
      'Researcher PIN',
      'Research Prediction',
      'Sentinel',
      'S0',
      'S1',
      'S2',
      'S3',
      '合格可能性',
      '合格圏',
      '本番力',
      'AI判定',
      '最短合格',
      '最適学習',
    ]) {
      expect(find.textContaining(forbidden), findsNothing);
    }
  });

  testWidgets('answer commit shows correct feedback and Explanation',
      (tester) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(DroneProductionApp(controller: controller));
    await tester.tap(find.byKey(const Key('unit-drone_rules')));
    await tester.pump();

    final correctIndex = controller.currentCard!.answerIndex;
    await tester.tap(find.byKey(Key('choice-$correctIndex')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('commit-answer')));
    await tester.pump();

    expect(find.text('正解'), findsOneWidget);
    expect(find.text('解説（Explanation）'), findsOneWidget);
    expect(find.text(controller.currentCard!.explanation!), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('next-question')),
      200,
    );
    expect(find.byKey(const Key('next-question')), findsOneWidget);
    expect(find.byKey(const Key('commit-answer')), findsNothing);
  });

  testWidgets('incorrect answer is locked after commit and next advances once',
      (tester) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(DroneProductionApp(controller: controller));
    await tester.tap(find.byKey(const Key('unit-drone_systems')));
    await tester.pump();

    final firstId = controller.activeSession!.currentQuestionId;
    final card = controller.currentCard!;
    final incorrectIndex = (card.answerIndex + 1) % card.choices.length;
    await tester.tap(find.byKey(Key('choice-$incorrectIndex')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('commit-answer')));
    await tester.pump();

    expect(find.text('不正解'), findsOneWidget);
    expect(controller.activeSession!.responses[firstId], incorrectIndex);
    await tester.tap(find.byKey(Key('choice-${card.answerIndex}')));
    await tester.pump();
    expect(controller.activeSession!.responses[firstId], incorrectIndex);

    await tester.tap(find.byKey(const Key('next-question')));
    await tester.pump();
    expect(controller.activeSession!.currentIndex, 1);
    expect(find.text('2 / 5'), findsOneWidget);
  });

  testWidgets('active session alone adds the resume action', (tester) async {
    final controller = await createController();
    addTearDown(controller.dispose);
    await controller.startUnit('drone_operations');
    controller.returnHome();
    await tester.pumpWidget(DroneProductionApp(controller: controller));

    expect(find.byKey(const Key('resume-session')), findsOneWidget);
    await tester.tap(find.byKey(const Key('resume-session')));
    await tester.pump();
    expect(find.text('1 / 5'), findsOneWidget);
  });
}
