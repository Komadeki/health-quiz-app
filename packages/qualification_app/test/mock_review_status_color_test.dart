import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'test_support.dart';

void main() {
  testWidgets('mock review uses blue correct and light red incorrect status text', (
    tester,
  ) async {
    final cache = MemoryEntitlementCache()
      ..value = EntitlementSnapshot(
        ownedProductIds: const {'fixture_full_unlock'},
      );
    final controller = QualificationProductionController(
      definition: fixtureDefinition,
      bankLoader: FixedBankLoader(loadFixtureBank()),
      sessionStore: MemoryQualificationSessionStore(),
      learningRepository: InMemoryLearningRepository(),
      purchaseGateway: FakePurchaseGateway(),
      entitlementCache: cache,
      now: TestClock().call,
      randomizer: const IdentityQuestionRandomizer(),
    );
    await controller.initialize();
    addTearDown(controller.dispose);

    expect(await controller.startMockExam(), isTrue);
    await controller.commitAnswer(controller.currentCard!.answerIndex);
    await controller.advance();
    final secondCard = controller.currentCard!;
    final wrongIndex = (secondCard.answerIndex + 1) % secondCard.choices.length;
    await controller.commitAnswer(wrongIndex);
    await controller.advance();

    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
      ),
    );

    final toggle = find.byKey(const Key('mock-review-toggle'));
    await tester.scrollUntilVisible(toggle, 200);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    Color? statusColor(int index) {
      final text = tester.widget<Text>(
        find.byKey(Key('mock-review-status-$index')),
      );
      final span = text.textSpan! as TextSpan;
      final statusSpan = span.children![1] as TextSpan;
      return statusSpan.style?.color;
    }

    expect(statusColor(0), Colors.blue.shade700);
    expect(statusColor(1), Colors.red.shade300);
  });
}
