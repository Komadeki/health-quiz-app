import 'package:drone_second_class/generated/app_manifest.g.dart';
import 'package:drone_second_class/production/production_controller.dart';
import 'package:drone_second_class/production/production_persistence.dart';
import 'package:drone_second_class/production/production_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_engine/quiz_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'production_test_support.dart';

void main() {
  late MemoryDroneSessionStore sessionStore;
  late MemoryDroneEntitlementCache entitlementCache;
  late FakeDronePurchaseGateway gateway;

  DroneProductionController createController({
    MemoryDroneSessionStore? store,
    MemoryDroneEntitlementCache? cache,
    FakeDronePurchaseGateway? purchaseGateway,
  }) {
    sessionStore = store ?? MemoryDroneSessionStore();
    entitlementCache = cache ?? MemoryDroneEntitlementCache();
    gateway = purchaseGateway ?? FakeDronePurchaseGateway();
    return DroneProductionController(
      bankLoader: FixedDroneBankLoader(loadProductionBank()),
      sessionStore: sessionStore,
      purchaseGateway: gateway,
      entitlementCache: entitlementCache,
    );
  }

  test('production runtime has the exact 100Q/20Q/four-unit contract', () {
    final bank = loadProductionBank();
    expect(bank.bankRevision, 'drone-second-class-v1-release-2026-08-20');
    expect(bank.examProfileVersion, 'drone-second-class-v1');
    expect(bank.cards, hasLength(100));
    expect(bank.cardsById, hasLength(100));
    expect(bank.units, hasLength(4));
    expect(bank.cards.where((card) => !card.isPremium), hasLength(20));
    for (final unit in bank.units) {
      expect(unit.cards.where((card) => !card.isPremium), hasLength(5));
    }
  });

  test('free entitlement exposes 20 and full entitlement exposes 100',
      () async {
    final freeController = createController();
    await freeController.initialize();
    expect(freeController.accessibleQuestionCount, 20);
    for (final unit in freeController.bank!.units) {
      expect(freeController.accessibleCardsFor(unit), hasLength(5));
    }
    freeController.dispose();

    final fullController = createController(
      cache: MemoryDroneEntitlementCache({
        GeneratedAppManifest.productCatalog.fullUnlockProductId!,
      }),
    );
    await fullController.initialize();
    expect(fullController.accessibleQuestionCount, 100);
    fullController.dispose();
  });

  test('answer commit is immutable and restart resumes exact position',
      () async {
    final store = MemoryDroneSessionStore();
    final first = createController(store: store);
    await first.initialize();
    await first.startUnit('drone_rules');
    final initialId = first.activeSession!.currentQuestionId;
    final correctIndex = first.currentCard!.answerIndex;

    expect(await first.commitAnswer(correctIndex), isTrue);
    expect(await first.commitAnswer((correctIndex + 1) % 3), isFalse);
    expect(first.activeSession!.responses[initialId], correctIndex);
    expect(store.session!.currentIndex, 0);
    first.dispose();

    final resumed = createController(store: store);
    await resumed.initialize();
    expect(resumed.activeSession!.currentQuestionId, initialId);
    expect(resumed.currentResponse, correctIndex);
    resumed.resume();
    expect(resumed.view, DroneProductionView.quiz);

    final advances = await Future.wait([resumed.advance(), resumed.advance()]);
    expect(advances.where((advanced) => advanced), hasLength(1));
    expect(resumed.activeSession!.currentIndex, 1);
    resumed.dispose();
  });

  test('finished session clears resume and produces a simple score', () async {
    final controller = createController();
    await controller.initialize();
    await controller.startUnit('drone_systems');
    final total = controller.activeSession!.questionIds.length;
    for (var index = 0; index < total; index += 1) {
      expect(await controller.commitAnswer(controller.currentCard!.answerIndex),
          isTrue);
      expect(await controller.advance(), isTrue);
    }

    expect(controller.activeSession, isNull);
    expect(sessionStore.session, isNull);
    expect(sessionStore.clearCount, 1);
    expect(controller.result!.correct, total);
    expect(controller.result!.total, total);
    expect(controller.view, DroneProductionView.result);
    controller.dispose();
  });

  test('incompatible local session is discarded without blocking Home',
      () async {
    final store = MemoryDroneSessionStore()
      ..session = DroneQuizSession(
        sessionId: 'old',
        bankRevision: 'old-bank',
        unitId: 'drone_rules',
        questionIds: const ['DRONE-Q-000002'],
        currentIndex: 0,
        responses: const {},
        updatedAt: DateTime.utc(2026, 8, 20),
      );
    final controller = createController(store: store);
    await controller.initialize();

    expect(controller.fatalError, isNull);
    expect(controller.activeSession, isNull);
    expect(store.clearCount, 1);
    controller.dispose();
  });

  test('purchase and restore success grant and cache full unlock', () async {
    final purchaseController = createController(
      purchaseGateway: FakeDronePurchaseGateway(
        purchaseStatus: PurchaseResultStatus.purchased,
      ),
    );
    await purchaseController.initialize();
    await purchaseController.purchaseFullUnlock();
    await settleAsyncEvents();
    expect(purchaseController.hasFullUnlock, isTrue);
    expect(purchaseController.accessibleQuestionCount, 100);
    expect(entitlementCache.snapshot.ownedProductIds,
        contains('drone_second_class_full_unlock'));
    purchaseController.dispose();

    final restoreController = createController(
      purchaseGateway: FakeDronePurchaseGateway(
        restoreStatus: PurchaseResultStatus.restored,
      ),
    );
    await restoreController.initialize();
    await restoreController.restorePurchases();
    await settleAsyncEvents();
    expect(restoreController.hasFullUnlock, isTrue);
    restoreController.dispose();
  });

  test('unknown, canceled, and error results never unlock', () async {
    for (final status in [
      PurchaseResultStatus.purchased,
      PurchaseResultStatus.canceled,
      PurchaseResultStatus.error,
    ]) {
      final controller = createController();
      await controller.initialize();
      gateway.emit(
        productId: status == PurchaseResultStatus.purchased
            ? 'unknown_product'
            : 'drone_second_class_full_unlock',
        status: status,
      );
      await settleAsyncEvents();
      expect(controller.hasFullUnlock, isFalse);
      expect(controller.accessibleQuestionCount, 20);
      controller.dispose();
    }
  });

  test('pending purchase stays locked while reporting progress', () async {
    final controller = createController();
    await controller.initialize();
    gateway.emit(
      productId: 'drone_second_class_full_unlock',
      status: PurchaseResultStatus.pending,
    );
    await settleAsyncEvents();

    expect(controller.hasFullUnlock, isFalse);
    expect(controller.purchasePending, isTrue);
    expect(controller.storeMessage, '購入処理を確認しています。');
    controller.dispose();
  });

  test('cached entitlement works offline and unavailable store leaves free use',
      () async {
    final offlineFull = createController(
      cache: MemoryDroneEntitlementCache({
        'drone_second_class_full_unlock',
      }),
      purchaseGateway: FakeDronePurchaseGateway(storeAvailable: false),
    );
    await offlineFull.initialize();
    expect(offlineFull.hasFullUnlock, isTrue);
    expect(offlineFull.accessibleQuestionCount, 100);
    offlineFull.dispose();

    final unavailableFree = createController(
      purchaseGateway: FakeDronePurchaseGateway(storeAvailable: false),
    );
    await unavailableFree.initialize();
    expect(unavailableFree.fatalError, isNull);
    expect(unavailableFree.accessibleQuestionCount, 20);
    expect(unavailableFree.storeMessage, contains('無料20問'));
    unavailableFree.dispose();

    final missingProduct = createController(
      purchaseGateway: FakeDronePurchaseGateway(includeProduct: false),
    );
    await missingProduct.initialize();
    expect(missingProduct.storeAvailable, isTrue);
    expect(missingProduct.fullUnlockProduct, isNull);
    expect(missingProduct.accessibleQuestionCount, 20);
    expect(missingProduct.storeMessage, contains('無料20問'));
    missingProduct.dispose();
  });

  test('corrupt persisted session is removed and ignored safely', () async {
    SharedPreferences.setMockInitialValues({
      'drone_second_class.active_session.v1': '{not-json',
    });
    const store = SharedPreferencesDroneSessionStore();

    expect(await store.load(), isNull);
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.containsKey('drone_second_class.active_session.v1'),
      isFalse,
    );
  });
}
