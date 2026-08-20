// GENERATED FILE - DO NOT EDIT.
// Generated from app.yaml by tooling/app_manifest.
// ignore_for_file: unnecessary_nullable_for_final_variable_declarations

import 'package:quiz_engine/quiz_engine.dart';

abstract final class GeneratedAppManifest {
  static const int schemaVersion = 1;
  static const String appKey = "drone_second_class";
  static const String displayName = "二等無人航空機 学科対策";
  static const String devDisplayName = "二等無人航空機 学科対策 DEV";
  static const String qaDisplayName = "二等無人航空機 学科対策 QA";

  static const String publisher = "KOMADEKI";
  static const String brandName = "KOMADEKI";
  static const String legalese = "© 2026 KOMADEKI";

  static const String iosBundleId = "com.komadeki.dronesecondclass";
  static const String iosDisplayName = "二等無人航空機 学科対策";
  static const String androidApplicationId = "com.komadeki.dronesecondclass";
  static const String androidDisplayName = "二等無人航空機 学科対策";

  static const String supportUrl = "https://komadeki.com/drone-second-class/support/";
  static const String privacyUrl = "https://komadeki.com/drone-second-class/privacy/";
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
    fullUnlockProductId: "drone_second_class_full_unlock",
  );

  static const MonetizationDefinition monetizationDefinition =
      MonetizationDefinition(
        architecture: PurchaseArchitecture.singleFullUnlock,
        productCatalog: productCatalog,
        entitlementPolicy: SingleFullUnlockEntitlementPolicy(),
      );

  static const QuestionIdentityPolicy questionIdentityPolicy =
      ExplicitQuestionIdentityV1();

  static const String? examProfileVersion = "drone-second-class-v1";
  static const int? examQuestionCount = 100;
  static const int? examTimeLimitMinutes = null;
  static const int? examOverallPassPercent = null;

  static const String themeKey = "drone_blue";
  static const String seedColor = "#165D8F";
}
