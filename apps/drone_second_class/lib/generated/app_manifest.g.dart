// GENERATED FILE - DO NOT EDIT.
// Generated from app.yaml by tooling/app_manifest.
// ignore_for_file: unnecessary_nullable_for_final_variable_declarations

import 'package:quiz_engine/quiz_engine.dart';

abstract final class GeneratedAppManifest {
  static const int schemaVersion = 1;
  static const String appKey = "drone_second_class";
  static const String displayName = "二等無人航空機 V0 Panel";
  static const String devDisplayName = "二等無人航空機 V0 Panel DEV";
  static const String qaDisplayName = "二等無人航空機 V0 Panel QA";

  static const String publisher = "KOMADEKI Validation";
  static const String brandName = "KOMADEKI V0 Panel";
  static const String legalese = "VALIDATION ONLY - MUST NOT BE USED FOR APP STORE RELEASE";

  static const String iosBundleId = "com.komadeki.dronesecondclass.v0panel";
  static const String iosDisplayName = "二等無人航空機 V0 Panel";
  static const String androidApplicationId = "com.komadeki.dronesecondclass.v0panel";
  static const String androidDisplayName = "二等無人航空機 V0 Panel";

  static const String supportUrl = "https://example.invalid/drone-second-class-v0-panel/support";
  static const String privacyUrl = "https://example.invalid/drone-second-class-v0-panel/privacy";
  static const String? marketingUrl = null;

  static const String questionBankFormat = "qualification_runtime_v2";
  static const String questionBankRuntimePath = "question_banks/drone_second_class/generated/drone_second_class_bank.json";
  static const String questionBankManifestPath = "question_banks/drone_second_class/generated/bank_manifest.json";
  static const String? questionBankAssetPath = "assets/question_bank/drone_second_class_bank.json";

  static const ProductCatalog productCatalog = ProductCatalog(
    deckProducts: <DeckProduct>[],
    bundle5ProductId: null,
    bundleAllProductId: null,
    proProductId: null,
    fullUnlockProductId: "validation_only_not_for_sale",
  );

  static const MonetizationDefinition monetizationDefinition =
      MonetizationDefinition(
        architecture: PurchaseArchitecture.singleFullUnlock,
        productCatalog: productCatalog,
        entitlementPolicy: SingleFullUnlockEntitlementPolicy(),
      );

  static const QuestionIdentityPolicy questionIdentityPolicy =
      ExplicitQuestionIdentityV1();

  static const String? examProfileVersion = "drone-second-class-unreleased";
  static const int? examQuestionCount = null;
  static const int? examTimeLimitMinutes = null;
  static const int? examOverallPassPercent = null;

  static const String themeKey = "validation_amber";
  static const String seedColor = "#8A4B00";
}
