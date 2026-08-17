// GENERATED FILE - DO NOT EDIT.
// Generated from app.yaml by tooling/app_manifest.
// ignore_for_file: unnecessary_nullable_for_final_variable_declarations

import 'package:quiz_engine/quiz_engine.dart';

abstract final class GeneratedAppManifest {
  static const int schemaVersion = 1;
  static const String appKey = "health";
  static const String displayName = "高校保健 一問一答";
  static const String devDisplayName = "健康クイズ（DEV）";
  static const String qaDisplayName = "健康クイズ（QA）";

  static const String publisher = "KENTO MORI";
  static const String brandName = "KOMADEKI";
  static const String legalese = "© 2025 もけけapp";

  static const String iosBundleId = "jp.mokeke.healthquiz";
  static const String iosDisplayName = "Health Quiz App";
  static const String androidApplicationId = "jp.mokeke.healthquiz";
  static const String androidDisplayName = "高校保健 一問一答";

  static const String supportUrl = "https://docs.google.com/forms/d/e/1FAIpQLScnTXDqyc_usBF4tsAvJSuU4GolMPn30iWceCGOwdno9g0Z1w/viewform?usp=pp_url";
  static const String privacyUrl = "https://sites.google.com/view/mokeke-healthquiz-privacy/";
  static const String? marketingUrl = null;

  static const String questionBankFormat = "legacy_assets_v1";
  static const String questionBankRuntimePath = "assets/decks";
  static const String questionBankManifestPath = "test/fixtures/health_question_bank_contract.json";
  static const String? questionBankAssetPath = null;

  static const ProductCatalog productCatalog = ProductCatalog(
    deckProducts: [
      DeckProduct(deckId: "deck_m01", productId: "deck_m01_unlock"),
      DeckProduct(deckId: "deck_m02", productId: "deck_m02_unlock"),
      DeckProduct(deckId: "deck_m03", productId: "deck_m03_unlock"),
      DeckProduct(deckId: "deck_m04", productId: "deck_m04_unlock"),
      DeckProduct(deckId: "deck_m05", productId: "deck_m05_unlock"),
      DeckProduct(deckId: "deck_m06", productId: "deck_m06_unlock"),
      DeckProduct(deckId: "deck_m07", productId: "deck_m07_unlock"),
      DeckProduct(deckId: "deck_m08", productId: "deck_m08_unlock"),
    ],
    bundle5ProductId: "bundle_5decks_unlock",
    bundleAllProductId: "bundle_all_unlock",
    proProductId: "pro_upgrade",
    fullUnlockProductId: null,
  );

  static const MonetizationDefinition monetizationDefinition =
      MonetizationDefinition(
        architecture: PurchaseArchitecture.legacyDeckBundles,
        productCatalog: productCatalog,
        entitlementPolicy: LegacyDeckBundleEntitlementPolicy(),
      );

  static const QuestionIdentityPolicy questionIdentityPolicy =
      LegacyHashQuestionIdentityV1();

  static const String? examProfileVersion = null;
  static const int? examQuestionCount = null;
  static const int? examTimeLimitMinutes = null;
  static const int? examOverallPassPercent = null;

  static const String themeKey = "material_green";
  static const String seedColor = "#4CAF50";
}
