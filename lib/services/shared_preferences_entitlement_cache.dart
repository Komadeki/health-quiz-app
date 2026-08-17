import 'package:quiz_engine/quiz_engine.dart';

import 'purchase_store.dart';

/// Adapts the published health purchase keys to the quiz engine snapshot.
///
/// It never deletes or replaces cached ownership. Store-confirmed grants are
/// translated back to the existing keys so current offline users keep access.
class SharedPreferencesEntitlementCache implements EntitlementCache {
  const SharedPreferencesEntitlementCache({required this.catalog});

  final ProductCatalog catalog;

  @override
  Future<EntitlementSnapshot> load() async {
    final ownedDeckIds = await PurchaseStore.getOwnedDeckIds();
    final selectedBundleDeckIds = await PurchaseStore.getFivePackDecks();
    final ownedProductIds = <String>{};

    for (final deckId in ownedDeckIds) {
      final productId = catalog.productIdForDeck(deckId);
      if (productId != null) ownedProductIds.add(productId);
    }

    final proProductId = catalog.proProductId;
    if (proProductId != null && await PurchaseStore.getPro()) {
      ownedProductIds.add(proProductId);
    }

    final bundle5ProductId = catalog.bundle5ProductId;
    if (bundle5ProductId != null && await PurchaseStore.isFivePackOwned()) {
      ownedProductIds.add(bundle5ProductId);
    }

    return EntitlementSnapshot(
      ownedProductIds: ownedProductIds,
      selectedBundleDeckIds: selectedBundleDeckIds,
    );
  }

  @override
  Future<EntitlementSnapshot> merge(EntitlementSnapshot additions) async {
    final current = await load();
    final verifiedProductIds = additions.ownedProductIds.where(
      catalog.recognizes,
    );

    final decksToAdd = <String>{};
    for (final productId in verifiedProductIds) {
      final deckId = catalog.deckIdForProduct(productId);
      if (deckId != null) decksToAdd.add(deckId);

      if (productId == catalog.bundleAllProductId) {
        decksToAdd.addAll(catalog.deckIds);
      }
      if (productId == catalog.bundle5ProductId) {
        await PurchaseStore.setFivePackOwned(true);
      }
      if (productId == catalog.proProductId) {
        await PurchaseStore.setPro(true);
      }
    }

    if (decksToAdd.isNotEmpty) {
      await PurchaseStore.addOwnedDecks(decksToAdd);
    }

    if (additions.selectedBundleDeckIds.isNotEmpty) {
      await PurchaseStore.setFivePackDecks({
        ...current.selectedBundleDeckIds,
        ...additions.selectedBundleDeckIds,
      });
    }

    return load();
  }
}
