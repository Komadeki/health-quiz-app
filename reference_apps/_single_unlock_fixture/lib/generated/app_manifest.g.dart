// GENERATED FILE - DO NOT EDIT.
// Generated from app.yaml by tooling/app_manifest.
// ignore_for_file: unnecessary_nullable_for_final_variable_declarations

import 'package:quiz_engine/quiz_engine.dart';

abstract final class GeneratedAppManifest {
  static const int schemaVersion = 1;
  static const String appKey = "qualification_fixture";
  static const String displayName = "資格アプリ Fixture";
  static const String devDisplayName = "資格アプリ Fixture DEV";
  static const String qaDisplayName = "資格アプリ Fixture QA";

  static const String publisher = "KOMADEKI Fixture";
  static const String brandName = "KOMADEKI Fixture";
  static const String legalese = "Fixture only - not for distribution";

  static const String iosBundleId = "com.komadeki.qualificationfixture";
  static const String iosDisplayName = "資格アプリ Fixture";
  static const String androidApplicationId = "com.komadeki.qualificationfixture";
  static const String androidDisplayName = "資格アプリ Fixture";

  static const String supportUrl = "https://example.invalid/qualification-fixture/support";
  static const String privacyUrl = "https://example.invalid/qualification-fixture/privacy";
  static const String? marketingUrl = null;

  static const String questionBankFormat = "qualification_runtime_v2";
  static const String questionBankRuntimePath = "question_banks/qualification_fixture/generated/qualification_fixture_bank.json";
  static const String questionBankManifestPath = "question_banks/qualification_fixture/generated/bank_manifest.json";
  static const String? questionBankAssetPath = "assets/question_bank/qualification_fixture_bank.json";

  static const ProductCatalog productCatalog = ProductCatalog(
    deckProducts: <DeckProduct>[],
    bundle5ProductId: null,
    bundleAllProductId: null,
    proProductId: null,
    fullUnlockProductId: "fixture_full_unlock",
  );

  static const MonetizationDefinition monetizationDefinition =
      MonetizationDefinition(
        architecture: PurchaseArchitecture.singleFullUnlock,
        productCatalog: productCatalog,
        entitlementPolicy: SingleFullUnlockEntitlementPolicy(),
      );

  static const QuestionIdentityPolicy questionIdentityPolicy =
      ExplicitQuestionIdentityV1();

  static const String? examProfileVersion = "fixture-exam-v1";
  static const int? examQuestionCount = 2;
  static const int? examTimeLimitMinutes = null;
  static const int? examOverallPassPercent = null;

  static const String themeKey = "fixture_teal";
  static const String seedColor = "#00695C";
}
