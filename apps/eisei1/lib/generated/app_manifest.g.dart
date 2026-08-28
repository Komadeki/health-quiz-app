// GENERATED FILE - DO NOT EDIT.
// Generated from app.yaml by tooling/app_manifest.
// ignore_for_file: unnecessary_nullable_for_final_variable_declarations

import 'package:quiz_engine/quiz_engine.dart';

abstract final class GeneratedAppManifest {
  static const int schemaVersion = 1;
  static const String appKey = "eisei1";
  static const String displayName = "第一種衛生管理者";
  static const String devDisplayName = "第一種衛生管理者 DEV";
  static const String qaDisplayName = "第一種衛生管理者 QA";

  static const String publisher = "KOMADEKI";
  static const String brandName = "KOMADEKI";
  static const String legalese = "© 2026 KOMADEKI";

  static const String iosBundleId = "com.komadeki.eisei1";
  static const String iosDisplayName = "第一種衛生管理者";
  static const String androidApplicationId = "com.komadeki.eisei1";
  static const String androidDisplayName = "第一種衛生管理者";

  static const String supportUrl = "https://komadeki.com/apps/";
  static const String privacyUrl = "https://komadeki.com/privacy/";
  static const String? marketingUrl = null;

  static const String questionBankFormat = "qualification_runtime_v2";
  static const String questionBankRuntimePath = "question_banks/eisei1/generated/eisei1_bank.json";
  static const String questionBankManifestPath = "question_banks/eisei1/generated/bank_manifest.json";
  static const String? questionBankAssetPath = "assets/question_bank/eisei1_bank.json";

  static const ProductCatalog productCatalog = ProductCatalog(
    deckProducts: <DeckProduct>[],
    bundle5ProductId: null,
    bundleAllProductId: null,
    proProductId: null,
    fullUnlockProductId: "eisei1_full_unlock",
  );

  static const MonetizationDefinition monetizationDefinition =
      MonetizationDefinition(
        architecture: PurchaseArchitecture.singleFullUnlock,
        productCatalog: productCatalog,
        entitlementPolicy: SingleFullUnlockEntitlementPolicy(),
      );

  static const QuestionIdentityPolicy questionIdentityPolicy =
      ExplicitQuestionIdentityV1();

  static const String? examProfileVersion = "eisei1-exam-v1";
  static const int? examQuestionCount = 44;
  static const int? examTimeLimitMinutes = 180;
  static const int? examOverallPassPercent = 60;

  static const String themeKey = "eisei_green";
  static const String seedColor = "#176B5B";
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
        questionBankAsset: "assets/question_bank/eisei1_bank.json",
        questionIdentityPolicy: questionIdentityPolicy,
        monetization: monetizationDefinition,
        examProfile: MockExamProfileV1(
        profileVersion: "eisei1-exam-v1",
        questionCount: 44,
        timeLimitMinutes: 180,
        allocations: [ExamUnitAllocationV1(unitId: "eisei1_law_hazardous", questionCount: 10), ExamUnitAllocationV1(unitId: "eisei1_hygiene_hazardous", questionCount: 10), ExamUnitAllocationV1(unitId: "eisei1_law_general", questionCount: 7), ExamUnitAllocationV1(unitId: "eisei1_hygiene_general", questionCount: 7), ExamUnitAllocationV1(unitId: "eisei1_physiology", questionCount: 10)],
        overallPassPercent: 60,
        sectionPassRules: [ExamSectionPassRuleV1(unitId: "eisei1_law_hazardous", minimumPercent: 40), ExamSectionPassRuleV1(unitId: "eisei1_hygiene_hazardous", minimumPercent: 40), ExamSectionPassRuleV1(unitId: "eisei1_law_general", minimumPercent: 40), ExamSectionPassRuleV1(unitId: "eisei1_hygiene_general", minimumPercent: 40), ExamSectionPassRuleV1(unitId: "eisei1_physiology", minimumPercent: 40)],
        shuffleQuestions: true,
      ),
        branding: const QualificationBranding(
          themeKey: themeKey,
          seedColorHex: seedColor,
        ),
        learningProduct: const LearningProductProfileV1(
          appVersion: "1.0.0+1",
          homeHeadline: "一次資料で確認する400問",
          sourceLabel: "法令・厚生労働省・安全衛生技術試験協会等の一次資料に基づく学習",
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
