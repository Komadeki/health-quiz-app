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
  static const int? examQuestionCount = 50;
  static const int? examTimeLimitMinutes = 30;
  static const int? examOverallPassPercent = null;

  static const String themeKey = "drone_blue";
  static const String seedColor = "#165D8F";
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
        questionBankAsset: "assets/question_bank/drone_second_class_bank.json",
        questionIdentityPolicy: questionIdentityPolicy,
        monetization: monetizationDefinition,
        examProfile: MockExamProfileV1(
        profileVersion: "drone-second-class-v1",
        questionCount: 50,
        timeLimitMinutes: 30,
        allocations: [],
        overallPassPercent: null,
        sectionPassRules: [],
        shuffleQuestions: true,
      ),
        branding: const QualificationBranding(
          themeKey: themeKey,
          seedColorHex: seedColor,
        ),
        learningProduct: const LearningProductProfileV1(
          appVersion: "1.0.0+1",
          homeHeadline: "教則第5版を基にした全100問",
          sourceLabel: "無人航空機の飛行の安全に関する教則 第5版に基づく学習",
          enabledModes: {LearningModeV1.unitPractice, LearningModeV1.randomPractice, LearningModeV1.unansweredPractice, LearningModeV1.incorrectPractice, LearningModeV1.retry, LearningModeV1.mockExam},
          practiceQuestionCount: 20,
          recentWindowSize: 20,
          progressEnabled: true,
          historyEnabled: true,
          weaknessEnabled: true,
          recommendationEnabled: true,
        ),
      );
}
