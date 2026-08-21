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
  static final QualificationAppDefinition definition =
      QualificationAppDefinition(
        appKey: appKey,
        displayName: displayName,
        publisher: publisher,
        brandName: brandName,
        legalese: legalese,
        urls: const QualificationUrls(
          support: supportUrl,
          privacy: privacyUrl,
          marketing: marketingUrl,
        ),
        questionBankAsset: "assets/question_bank/qualification_fixture_bank.json",
        questionIdentityPolicy: questionIdentityPolicy,
        monetization: monetizationDefinition,
        examProfile: MockExamProfileV1(
        profileVersion: "fixture-exam-v1",
        questionCount: 2,
        timeLimitMinutes: null,
        allocations: [ExamUnitAllocationV1(unitId: "fixture_operations", questionCount: 1), ExamUnitAllocationV1(unitId: "fixture_safety", questionCount: 1)],
        overallPassPercent: null,
        sectionPassRules: [],
        shuffleQuestions: true,
      ),
        branding: const QualificationBranding(
          themeKey: themeKey,
          seedColorHex: seedColor,
        ),
        learningProduct: const LearningProductProfileV1(
          appVersion: "0.1.0",
          homeHeadline: "架空資格のFactory検証",
          sourceLabel: "架空資格のための独自作成資料",
          enabledModes: {LearningModeV1.unitPractice, LearningModeV1.randomPractice, LearningModeV1.unansweredPractice, LearningModeV1.incorrectPractice, LearningModeV1.retry, LearningModeV1.mockExam},
          practiceQuestionCount: 2,
          recentWindowSize: 5,
          progressEnabled: true,
          historyEnabled: true,
          weaknessEnabled: true,
          recommendationEnabled: true,
        ),
      );
}
