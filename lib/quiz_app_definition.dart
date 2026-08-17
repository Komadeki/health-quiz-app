import 'package:quiz_engine/quiz_engine.dart';

import 'generated/app_manifest.g.dart';

export 'package:quiz_engine/quiz_engine.dart' show PurchaseArchitecture;

class QuizAppDefinition {
  const QuizAppDefinition({
    required this.appKey,
    required this.appName,
    required this.devAppName,
    required this.qaAppName,
    required this.publisherName,
    required this.brandName,
    required this.legalese,
    required this.monetization,
    required this.questionIdentityPolicy,
  });

  final String appKey;
  final String appName;
  final String devAppName;
  final String qaAppName;
  final String publisherName;
  final String brandName;
  final String legalese;
  final MonetizationDefinition monetization;
  final QuestionIdentityPolicy questionIdentityPolicy;

  // Compatibility views for pre-Phase 2D callers.
  PurchaseArchitecture get purchaseArchitecture => monetization.architecture;
  List<String> get deckIds => monetization.productCatalog.deckIds;
  String get bundle5ProductId =>
      monetization.productCatalog.bundle5ProductId ?? '';
  String get bundleAllProductId =>
      monetization.productCatalog.bundleAllProductId ?? '';
  String get proProductId => monetization.productCatalog.proProductId ?? '';
  String get fullUnlockProductId =>
      monetization.productCatalog.fullUnlockProductId ?? '';

  /// Compatibility view for pre-Phase 2C callers. Identity selection is made
  /// by [questionIdentityPolicy], not by this boolean.
  bool get preferExplicitStableIds =>
      questionIdentityPolicy is ExplicitQuestionIdentityV1;

  bool get usesLegacyDeckBundles =>
      purchaseArchitecture == PurchaseArchitecture.legacyDeckBundles;

  bool get usesSingleFullUnlock =>
      purchaseArchitecture == PurchaseArchitecture.singleFullUnlock;

  Set<String> get productIds => monetization.productCatalog.productIds;
}

const healthProductCatalog = GeneratedAppManifest.productCatalog;

const healthMonetizationDefinition =
    GeneratedAppManifest.monetizationDefinition;

/// 現行の高校保健アプリは既存の商品体系・問題ID方式をそのまま維持する。
/// 新しい資格アプリを作るときだけ、この定義を資格固有値へ差し替える。
const currentQuizApp = QuizAppDefinition(
  appKey: GeneratedAppManifest.appKey,
  appName: GeneratedAppManifest.displayName,
  devAppName: GeneratedAppManifest.devDisplayName,
  qaAppName: GeneratedAppManifest.qaDisplayName,
  publisherName: GeneratedAppManifest.publisher,
  brandName: GeneratedAppManifest.brandName,
  legalese: GeneratedAppManifest.legalese,
  monetization: healthMonetizationDefinition,
  questionIdentityPolicy: GeneratedAppManifest.questionIdentityPolicy,
);
