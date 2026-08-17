import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/quiz_app_definition.dart';
import 'package:health_quiz_app/services/shared_preferences_entitlement_cache.dart';
import 'package:quiz_engine/quiz_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferencesEntitlementCache cache;

  setUp(() {
    cache = const SharedPreferencesEntitlementCache(
      catalog: healthProductCatalog,
    );
  });

  test('published health keys load as an offline entitlement snapshot',
      () async {
    SharedPreferences.setMockInitialValues({
      'ownedDeckIds': ['DECK_M01'],
      'fivePack.owned': true,
      'fivePack.selectedDecks': ['deck_m02'],
      'proUpgrade': true,
    });

    final snapshot = await cache.load();

    expect(
      snapshot.ownedProductIds,
      {'deck_m01_unlock', 'bundle_5decks_unlock', 'pro_upgrade'},
    );
    expect(snapshot.selectedBundleDeckIds, {'deck_m02'});
  });

  test('verified individual grant merges without replacing existing cache',
      () async {
    SharedPreferences.setMockInitialValues({
      'ownedDeckIds': ['deck_m01'],
      'fivePack.owned': true,
      'fivePack.selectedDecks': ['deck_m03'],
      'proUpgrade': true,
    });

    final snapshot = await cache.merge(
      EntitlementSnapshot(ownedProductIds: {'deck_m02_unlock'}),
    );

    expect(
      snapshot.ownedProductIds,
      containsAll({
        'deck_m01_unlock',
        'deck_m02_unlock',
        'bundle_5decks_unlock',
        'pro_upgrade',
      }),
    );
    expect(snapshot.selectedBundleDeckIds, {'deck_m03'});
  });

  test('bundle-all grant keeps the published all-decks representation',
      () async {
    SharedPreferences.setMockInitialValues({
      'ownedDeckIds': ['deck_m01'],
    });

    final snapshot = await cache.merge(
      EntitlementSnapshot(ownedProductIds: {'bundle_all_unlock'}),
    );

    expect(
      healthProductCatalog.deckIds.every(
        (deckId) => snapshot.ownedProductIds.contains('${deckId}_unlock'),
      ),
      isTrue,
    );
  });

  test('five-pack restore grants only its flag and preserves selection',
      () async {
    SharedPreferences.setMockInitialValues({
      'fivePack.selectedDecks': ['deck_m04'],
    });

    final snapshot = await cache.merge(
      EntitlementSnapshot(ownedProductIds: {'bundle_5decks_unlock'}),
    );

    expect(snapshot.ownedProductIds, contains('bundle_5decks_unlock'));
    expect(snapshot.selectedBundleDeckIds, {'deck_m04'});
  });

  test('five-pack restore does not invent a missing deck selection', () async {
    SharedPreferences.setMockInitialValues({});

    final snapshot = await cache.merge(
      EntitlementSnapshot(ownedProductIds: {'bundle_5decks_unlock'}),
    );

    expect(snapshot.ownedProductIds, contains('bundle_5decks_unlock'));
    expect(snapshot.selectedBundleDeckIds, isEmpty);
  });

  test('unknown product is ignored without deleting offline cache', () async {
    SharedPreferences.setMockInitialValues({
      'ownedDeckIds': ['deck_m05'],
    });

    final snapshot = await cache.merge(
      EntitlementSnapshot(ownedProductIds: {'unknown_product'}),
    );

    expect(snapshot.ownedProductIds, {'deck_m05_unlock'});
  });
}
