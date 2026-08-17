import 'entitlement.dart';
import 'product_catalog.dart';

enum PurchaseArchitecture {
  legacyDeckBundles,
  singleFullUnlock,
}

/// App-level monetization configuration without store or persistence plugins.
class MonetizationDefinition {
  const MonetizationDefinition({
    required this.architecture,
    required this.productCatalog,
    required this.entitlementPolicy,
  });

  final PurchaseArchitecture architecture;
  final ProductCatalog productCatalog;
  final EntitlementPolicy entitlementPolicy;
}
