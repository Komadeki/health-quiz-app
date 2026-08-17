import 'package:quiz_engine/quiz_engine.dart';
export 'package:quiz_engine/quiz_engine.dart' show PurchaseArchitecture;

class QuizAppDefinition {
  const QuizAppDefinition({
    required this.appKey,
    required this.appName,
    required this.devAppName,
    required this.qaAppName,
    required this.publisherName,
    required this.legalese,
    required this.monetization,
    required this.questionIdentityPolicy,
  });

  final String appKey;
  final String appName;
  final String devAppName;
  final String qaAppName;
  final String publisherName;
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

const healthProductCatalog = ProductCatalog(
  deckProducts: [
    DeckProduct(deckId: 'deck_m01', productId: 'deck_m01_unlock'),
    DeckProduct(deckId: 'deck_m02', productId: 'deck_m02_unlock'),
    DeckProduct(deckId: 'deck_m03', productId: 'deck_m03_unlock'),
    DeckProduct(deckId: 'deck_m04', productId: 'deck_m04_unlock'),
    DeckProduct(deckId: 'deck_m05', productId: 'deck_m05_unlock'),
    DeckProduct(deckId: 'deck_m06', productId: 'deck_m06_unlock'),
    DeckProduct(deckId: 'deck_m07', productId: 'deck_m07_unlock'),
    DeckProduct(deckId: 'deck_m08', productId: 'deck_m08_unlock'),
  ],
  bundle5ProductId: 'bundle_5decks_unlock',
  bundleAllProductId: 'bundle_all_unlock',
  proProductId: 'pro_upgrade',
);

const healthMonetizationDefinition = MonetizationDefinition(
  architecture: PurchaseArchitecture.legacyDeckBundles,
  productCatalog: healthProductCatalog,
  entitlementPolicy: LegacyDeckBundleEntitlementPolicy(),
);

/// 現行の高校保健アプリは既存の商品体系・問題ID方式をそのまま維持する。
/// 新しい資格アプリを作るときだけ、この定義を資格固有値へ差し替える。
const currentQuizApp = QuizAppDefinition(
  appKey: 'health',
  appName: '高校保健 一問一答',
  devAppName: '健康クイズ（DEV）',
  qaAppName: '健康クイズ（QA）',
  publisherName: 'KOMADEKI',
  legalese: '© 2026 KOMADEKI',
  monetization: healthMonetizationDefinition,
  questionIdentityPolicy: LegacyHashQuestionIdentityV1(),
);
