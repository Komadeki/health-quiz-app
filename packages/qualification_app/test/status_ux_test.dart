import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'test_support.dart';

void main() {
  QualificationProductionController createController(
    QualificationBankLoader bankLoader, {
    LifecyclePurchaseGateway? purchaseGateway,
  }) {
    return QualificationProductionController(
      definition: fixtureDefinition,
      bankLoader: bankLoader,
      sessionStore: MemoryQualificationSessionStore(),
      learningRepository: InMemoryLearningRepository(),
      purchaseGateway: purchaseGateway ?? FakePurchaseGateway(),
      entitlementCache: MemoryEntitlementCache(),
      now: TestClock().call,
      randomizer: const IdentityQuestionRandomizer(),
    );
  }

  Future<void> pumpApp(
    WidgetTester tester,
    QualificationProductionController controller,
  ) async {
    await tester.pumpWidget(
      QualificationProductionApp(
        definition: fixtureDefinition,
        controller: controller,
        urlLauncher: (_) async => true,
      ),
    );
  }

  testWidgets('loading exposes readable semantic status', (tester) async {
    final completer = Completer<QualificationBank>();
    final controller = createController(_PendingBankLoader(completer.future));
    addTearDown(controller.dispose);
    unawaited(controller.initialize());
    final semantics = tester.ensureSemantics();

    await pumpApp(tester, controller);

    expect(find.byKey(const Key('production-loading')), findsOneWidget);
    expect(find.text('問題データを読み込んでいます'), findsOneWidget);
    expect(
      find.bySemanticsLabel('問題データを読み込んでいます'),
      findsWidgets,
    );
    semantics.dispose();

    completer.complete(loadFixtureBank());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('production-loading')), findsNothing);
  });

  testWidgets('fatal load failure hides raw exception and offers support', (
    tester,
  ) async {
    final controller = createController(
      _FailingBankLoader(StateError('SECRET INTERNAL BANK FAILURE')),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    await pumpApp(tester, controller);

    expect(find.byKey(const Key('production-failure')), findsOneWidget);
    expect(find.text('問題データを読み込めませんでした'), findsOneWidget);
    expect(find.textContaining('SECRET INTERNAL BANK FAILURE'), findsNothing);
    expect(find.byKey(const Key('failure-support-link')), findsOneWidget);
  });

  testWidgets('known nonfatal condition uses shared Home status surface', (
    tester,
  ) async {
    final controller = createController(FixedBankLoader(loadFixtureBank()));
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.startMockExam();

    await pumpApp(tester, controller);

    expect(find.byKey(const Key('nonfatal-status')), findsOneWidget);
    expect(
      find.text('模擬試験は全問解放後に利用できます。'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('dismiss-nonfatal-status')));
    await tester.pump();

    expect(find.byKey(const Key('nonfatal-status')), findsNothing);
  });

  testWidgets('unknown internal status is replaced with stable generic copy', (
    tester,
  ) async {
    final controller = createController(FixedBankLoader(loadFixtureBank()));
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.storeMessage = 'SECRET INTERNAL STATUS DETAIL';
    controller.notifyListeners();

    await pumpApp(tester, controller);

    expect(find.byKey(const Key('nonfatal-status')), findsOneWidget);
    expect(find.textContaining('SECRET INTERNAL STATUS DETAIL'), findsNothing);
    expect(
      find.text('操作を完了できませんでした。もう一度お試しください。'),
      findsOneWidget,
    );
  });
}

final class _PendingBankLoader implements QualificationBankLoader {
  const _PendingBankLoader(this.future);

  final Future<QualificationBank> future;

  @override
  Future<QualificationBank> load() => future;
}

final class _FailingBankLoader implements QualificationBankLoader {
  const _FailingBankLoader(this.error);

  final Object error;

  @override
  Future<QualificationBank> load() => Future.error(error);
}
