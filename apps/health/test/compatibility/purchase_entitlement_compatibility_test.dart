import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/services/gate.dart';
import 'package:health_quiz_app/services/iap_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void seedEntitlements({
  List<String> ownedDeckIds = const [],
  List<String> fivePackDecks = const [],
  bool fivePackOwned = false,
  bool pro = false,
}) {
  SharedPreferences.setMockInitialValues({
    'ownedDeckIds': ownedDeckIds,
    'fivePack.selectedDecks': fivePackDecks,
    'fivePack.owned': fivePackOwned,
    'proUpgrade': pro,
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an unpurchased user has no premium deck or Pro access', () async {
    seedEntitlements();

    expect(await Gate.canAccessDeck('deck_m01'), isFalse);
    expect(await Gate.canUseFeature('review_test'), isFalse);
  });

  test('an individual purchase unlocks only its deck', () async {
    seedEntitlements(ownedDeckIds: const ['DECK_M02']);

    expect(await Gate.canAccessDeck('deck_m02'), isTrue);
    expect(await Gate.canAccessDeck('deck_m01'), isFalse);
  });

  test('a five-pack unlocks selected decks but not outside decks', () async {
    seedEntitlements(
      fivePackOwned: true,
      fivePackDecks: const [
        'deck_m01',
        'deck_m02',
        'deck_m03',
        'deck_m04',
        'deck_m05',
      ],
    );

    expect(await Gate.canAccessDeck('deck_m03'), isTrue);
    expect(await Gate.canAccessDeck('deck_m06'), isFalse);
  });

  test('bundle-all persisted ownership unlocks every published deck', () async {
    seedEntitlements(ownedDeckIds: ProductCatalog.deckIds);

    expect(
      await Gate.isAllUnlocked(ProductCatalog.deckIds),
      isTrue,
    );
    for (final deckId in ProductCatalog.deckIds) {
      expect(await Gate.canAccessDeck(deckId), isTrue);
    }
  });

  test('Pro unlocks Pro features but does not imply deck ownership', () async {
    seedEntitlements(pro: true);

    expect(await Gate.canUseFeature('review_test'), isTrue);
    expect(await Gate.canUseFeature('review_cards'), isTrue);
    expect(await Gate.canUseFeature('reminder'), isTrue);
    expect(await Gate.canUseFeature('unknown'), isFalse);
    expect(await Gate.canAccessDeck('deck_m01'), isFalse);
  });

  test('coexisting rights are combined without broadening deck access',
      () async {
    seedEntitlements(
      ownedDeckIds: const ['deck_m01'],
      fivePackOwned: true,
      fivePackDecks: const ['deck_m02'],
      pro: true,
    );

    expect(await Gate.canAccessDeck('deck_m01'), isTrue);
    expect(await Gate.canAccessDeck('deck_m02'), isTrue);
    expect(await Gate.canAccessDeck('deck_m03'), isFalse);
    expect(await Gate.canUseFeature('review_test'), isTrue);
  });
}
