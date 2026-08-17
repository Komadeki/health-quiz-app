/// A non-consumable product that unlocks one legacy deck.
class DeckProduct {
  const DeckProduct({required this.deckId, required this.productId});

  final String deckId;
  final String productId;

  @override
  bool operator ==(Object other) =>
      other is DeckProduct &&
      other.deckId == deckId &&
      other.productId == productId;

  @override
  int get hashCode => Object.hash(deckId, productId);
}

/// The immutable product values used by one app.
///
/// This is deliberately a value object rather than a store-facing service.
class ProductCatalog {
  const ProductCatalog({
    this.deckProducts = const [],
    this.bundle5ProductId,
    this.bundleAllProductId,
    this.proProductId,
    this.fullUnlockProductId,
  });

  final List<DeckProduct> deckProducts;
  final String? bundle5ProductId;
  final String? bundleAllProductId;
  final String? proProductId;
  final String? fullUnlockProductId;

  List<String> get deckIds =>
      List.unmodifiable(deckProducts.map((product) => product.deckId));

  Set<String> get productIds {
    final ids = <String>{
      ...deckProducts.map((product) => product.productId),
    };
    for (final id in [
      bundle5ProductId,
      bundleAllProductId,
      proProductId,
      fullUnlockProductId,
    ]) {
      if (id != null && id.isNotEmpty) ids.add(id);
    }
    return Set.unmodifiable(ids);
  }

  bool recognizes(String productId) => productIds.contains(productId);

  String? productIdForDeck(String deckId) {
    final normalized = deckId.toLowerCase();
    for (final product in deckProducts) {
      if (product.deckId.toLowerCase() == normalized) {
        return product.productId;
      }
    }
    return null;
  }

  String? deckIdForProduct(String productId) {
    for (final product in deckProducts) {
      if (product.productId == productId) return product.deckId;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is ProductCatalog &&
      _listEquals(other.deckProducts, deckProducts) &&
      other.bundle5ProductId == bundle5ProductId &&
      other.bundleAllProductId == bundleAllProductId &&
      other.proProductId == proProductId &&
      other.fullUnlockProductId == fullUnlockProductId;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(deckProducts),
        bundle5ProductId,
        bundleAllProductId,
        proProductId,
        fullUnlockProductId,
      );
}

bool _listEquals<T>(List<T> left, List<T> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
