import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/data/quiz_session_local_repository.dart';
import 'package:health_quiz_app/quiz_app_definition.dart';
import 'package:health_quiz_app/services/attempt_store.dart';
import 'package:health_quiz_app/services/purchase_store.dart';
import 'package:health_quiz_app/services/score_store.dart';
import 'package:health_quiz_app/services/shared_preferences_entitlement_cache.dart';
import 'package:quiz_engine/quiz_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'score_save_regression_test.dart' show record;

class _FailingDisk extends InMemorySharedPreferencesStore {
  _FailingDisk() : super.withData({});
  String? failKey;
  @override
  Future<bool> setValue(String valueType, String key, Object value) {
    if (failKey != null && key.contains(failKey!)) return Future.value(false);
    return super.setValue(valueType, key, value);
  }
}

class _Gateway implements PurchaseGateway {
  final completed = <String>[];
  @override
  Stream<PurchaseResult> get purchaseResults => const Stream.empty();
  @override
  Future<void> complete(PurchaseResult result) async =>
      completed.add(result.eventId);
  @override
  Future<void> purchase(String productId) async {}
  @override
  Future<void> restore() async {}
  @override
  Future<ProductQueryResult> queryProducts(Set<String> productIds) async =>
      ProductQueryResult(storeAvailable: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FailingDisk disk;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    disk = _FailingDisk();
    SharedPreferencesStorePlatform.instance = disk;
  });

  for (final product in [
    'deck_m02_unlock',
    'bundle_5decks_unlock',
    'pro_upgrade'
  ]) {
    test('$product is not completed before a durable entitlement save',
        () async {
      await PurchaseStore.addOwnedDecks(['deck_m01']);
      final gateway = _Gateway();
      const cache =
          SharedPreferencesEntitlementCache(catalog: healthProductCatalog);
      final coordinator = PurchaseEntitlementCoordinator(
        gateway: gateway,
        definition: currentQuizApp.monetization,
        cache: cache,
      );
      await coordinator.loadCachedEntitlements();
      disk.failKey = switch (product) {
        'bundle_5decks_unlock' => 'fivePack.owned',
        'pro_upgrade' => 'proUpgrade',
        _ => 'ownedDeckIds',
      };
      final result = PurchaseResult(
          eventId: product,
          productId: product,
          status: PurchaseResultStatus.restored,
          pendingCompletePurchase: true);
      await expectLater(
          coordinator.handlePurchaseResult(result), throwsStateError);
      expect(gateway.completed, isEmpty);
      expect((await cache.load()).ownedProductIds, {'deck_m01_unlock'});
      disk.failKey = null;
      await coordinator.handlePurchaseResult(result);
      expect(gateway.completed, [product]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      expect((await cache.load()).ownedProductIds, contains(product));
      expect((await cache.load()).ownedProductIds, contains('deck_m01_unlock'));
    });
  }

  test('concurrent score saves retain both sessions on disk', () async {
    await Future.wait([
      AttemptStore().addScore(record(id: 'a', sessionId: 'a')),
      AttemptStore().addScore(record(id: 'b', sessionId: 'b')),
    ]);
    await (await SharedPreferences.getInstance()).reload();
    expect((await ScoreStore.instance.loadAll()).map((e) => e.id).toSet(),
        {'a', 'b'});
  });

  test('failed single-result deletion leaves every score on disk', () async {
    await AttemptStore().addScore(record(id: 'a'));
    await AttemptStore().addScore(record(id: 'b'));
    disk.failKey = 'scores_v2';
    await expectLater(ScoreStore.instance.delete('a'), throwsStateError);
    await (await SharedPreferences.getInstance()).reload();
    expect((await ScoreStore.instance.loadAll()).map((e) => e.id).toSet(),
        {'a', 'b'});
    disk.failKey = null;
    await ScoreStore.instance.delete('a');
    expect((await ScoreStore.instance.loadAll()).map((e) => e.id), ['b']);
  });

  test('deletion covers both legacy keys without reviving a v1 score',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'scores.v1',
        jsonEncode([
          {'id': 'a', 'deckId': 'old', 'score': 1, 'total': 2, 'timestamp': 1},
          {
            'id': 'old-b',
            'deckId': 'old',
            'score': 2,
            'total': 2,
            'timestamp': 2
          },
        ]));
    await prefs.setString('scores.v2', jsonEncode([record(id: 'a').toJson()]));
    await AttemptStore().addScore(record(id: 'new-c'));
    await ScoreStore.instance.delete('a');
    await prefs.reload();
    expect((await ScoreStore.instance.loadAll()).map((e) => e.id).toSet(),
        {'old-b', 'new-c'});
  });

  test('adding a result never overwrites an unreadable score collection',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AttemptStore.kScores, '{unreadable');
    await expectLater(
        AttemptStore().addScore(record(id: 'a')), throwsStateError);
    await prefs.reload();
    expect(prefs.getString(AttemptStore.kScores), '{unreadable');
  });

  test('an unreadable active quiz is preserved before reset', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_quiz_session_v1', '{unreadable');
    expect(await QuizSessionLocalRepository(prefs).loadActive(), isNull);
    await prefs.reload();
    final recoveryKey = prefs
        .getKeys()
        .singleWhere((k) => k.startsWith('health_quiz_recovery_v1__'));
    expect(prefs.getString(recoveryKey), '{unreadable');
    expect(prefs.getString('active_quiz_session_v1'), isNull);
  });

  test('failed recovery backup leaves the original active quiz intact',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_quiz_session_v1', '{unreadable');
    disk.failKey = 'health_quiz_recovery_v1__';
    await expectLater(
        QuizSessionLocalRepository(prefs).loadActive(), throwsStateError);
    await prefs.reload();
    expect(prefs.getString('active_quiz_session_v1'), '{unreadable');
  });
}
