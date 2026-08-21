import '../identity/question_identity_policy.dart';
import '../monetization/monetization_definition.dart';
import 'learning_event.dart';
import 'mock_exam.dart';

final class QualificationUrls {
  const QualificationUrls({
    required this.support,
    required this.privacy,
    this.marketing,
  });

  final String support;
  final String privacy;
  final String? marketing;
}

final class QualificationBranding {
  const QualificationBranding({
    required this.themeKey,
    required this.seedColorHex,
  });

  final String themeKey;
  final String seedColorHex;
}

final class LearningProductProfileV1 {
  const LearningProductProfileV1({
    required this.appVersion,
    required this.homeHeadline,
    required this.sourceLabel,
    required this.enabledModes,
    required this.practiceQuestionCount,
    required this.recentWindowSize,
    required this.progressEnabled,
    required this.historyEnabled,
    required this.weaknessEnabled,
    required this.recommendationEnabled,
  });

  final String appVersion;
  final String homeHeadline;
  final String sourceLabel;
  final Set<LearningModeV1> enabledModes;
  final int practiceQuestionCount;
  final int recentWindowSize;
  final bool progressEnabled;
  final bool historyEnabled;
  final bool weaknessEnabled;
  final bool recommendationEnabled;
}

/// Generated from app.yaml. It contains configuration, never runtime behavior.
final class QualificationAppDefinition {
  const QualificationAppDefinition({
    required this.appKey,
    required this.displayName,
    required this.publisher,
    required this.brandName,
    required this.legalese,
    required this.urls,
    required this.questionBankAsset,
    required this.questionIdentityPolicy,
    required this.monetization,
    required this.examProfile,
    required this.branding,
    required this.learningProduct,
  });

  final String appKey;
  final String displayName;
  final String publisher;
  final String brandName;
  final String legalese;
  final QualificationUrls urls;
  final String questionBankAsset;
  final QuestionIdentityPolicy questionIdentityPolicy;
  final MonetizationDefinition monetization;
  final MockExamProfileV1? examProfile;
  final QualificationBranding branding;
  final LearningProductProfileV1 learningProduct;
}
