import 'package:drone_second_class/generated/app_manifest.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'production_test_support.dart';

void main() {
  MemoryEntitlementCache fullUnlockCache() {
    final productId = GeneratedAppManifest
        .definition.monetization.productCatalog.fullUnlockProductId!;
    return MemoryEntitlementCache()
      ..value = EntitlementSnapshot(ownedProductIds: {productId});
  }

  Future<void> pumpHome(
    WidgetTester tester,
    QualificationProductionController controller,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: GeneratedAppManifest.definition,
        controller: controller,
      ),
    );
  }

  testWidgets(
    'Drone shows 20-question random practice and full unanswered count options',
    (tester) async {
      final controller = createProductionController(
        entitlementCache: fullUnlockCache(),
      );
      await controller.initialize();
      addTearDown(controller.dispose);
      await pumpHome(tester, controller);

      final random = find.byKey(const Key('start-random'));
      await tester.scrollUntilVisible(random, 240);
      expect(
        find.descendant(
          of: random,
          matching: find.text('ランダム演習（20問）'),
        ),
        findsOneWidget,
      );

      final unanswered = find.byKey(const Key('start-unanswered'));
      await tester.tap(unanswered);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('practice-count-sheet-unanswered')),
        findsOneWidget,
      );
      for (final count in [5, 10, 20, 30, 50, 100, 150, 200]) {
        expect(
          find.byKey(Key('practice-count-unanswered-$count')),
          findsOneWidget,
        );
      }
      expect(find.text('全部（386問）'), findsOneWidget);

      await tester.tap(find.byKey(const Key('practice-count-unanswered-30')));
      await tester.pumpAndSettle();

      expect(controller.activeSession, isNotNull);
      expect(controller.activeSession!.mode, LearningModeV1.unansweredPractice);
      expect(controller.activeSession!.questionIds.length, 30);
    },
  );

  testWidgets(
    'incorrect picker removes oversized choices as the remaining pool shrinks',
    (tester) async {
      final controller = createProductionController(
        entitlementCache: fullUnlockCache(),
      );
      await controller.initialize();
      addTearDown(controller.dispose);

      expect(await controller.startRandom(), isTrue);
      while (controller.activeSession != null) {
        final card = controller.currentCard!;
        final wrongIndex = (card.answerIndex + 1) % card.choices.length;
        expect(await controller.commitAnswer(wrongIndex), isTrue);
        expect(await controller.advance(), isTrue);
      }
      controller.returnHome();
      await pumpHome(tester, controller);

      final incorrect = find.byKey(const Key('start-incorrect'));
      await tester.scrollUntilVisible(incorrect, 240);
      await tester.tap(incorrect);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('practice-count-sheet-incorrect')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('practice-count-incorrect-5')), findsOneWidget);
      expect(
        find.byKey(const Key('practice-count-incorrect-10')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('practice-count-incorrect-20')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('practice-count-incorrect-30')),
        findsNothing,
      );
      expect(find.text('全部（20問）'), findsOneWidget);

      await tester.tap(find.byKey(const Key('practice-count-incorrect-10')));
      await tester.pumpAndSettle();

      expect(controller.activeSession, isNotNull);
      expect(controller.activeSession!.mode, LearningModeV1.incorrectPractice);
      expect(controller.activeSession!.questionIds.length, 10);
    },
  );
}
