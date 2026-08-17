/// Store metadata needed by app purchase UIs without exposing a store plugin.
class PurchaseProduct {
  const PurchaseProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
  });

  final String id;
  final String title;
  final String description;
  final String price;
}

class ProductQueryResult {
  ProductQueryResult({
    required this.storeAvailable,
    Iterable<PurchaseProduct> products = const [],
    Iterable<String> notFoundProductIds = const [],
    this.errorMessage,
  })  : products = List.unmodifiable(products),
        notFoundProductIds = Set.unmodifiable(notFoundProductIds);

  final bool storeAvailable;
  final List<PurchaseProduct> products;
  final Set<String> notFoundProductIds;
  final String? errorMessage;
}

enum PurchaseResultStatus {
  pending,
  purchased,
  restored,
  canceled,
  error,
}

class PurchaseResult {
  const PurchaseResult({
    required this.eventId,
    required this.productId,
    required this.status,
    this.errorMessage,
    this.pendingCompletePurchase = false,
  });

  final String eventId;
  final String productId;
  final PurchaseResultStatus status;
  final String? errorMessage;
  final bool pendingCompletePurchase;
}

/// App-shell boundary for StoreKit, Google Play or a deterministic fake.
abstract interface class PurchaseGateway {
  Stream<PurchaseResult> get purchaseResults;

  Future<ProductQueryResult> queryProducts(Set<String> productIds);

  Future<void> purchase(String productId);

  /// Restored products are delivered through [purchaseResults].
  Future<void> restore();

  Future<void> complete(PurchaseResult result);
}
