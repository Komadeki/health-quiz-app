enum PurchaseArchitecture {
  legacyDeckBundles,
  singleFullUnlock,
}

class QuizAppDefinition {
  const QuizAppDefinition({
    required this.appKey,
    required this.appName,
    required this.devAppName,
    required this.qaAppName,
    required this.publisherName,
    required this.legalese,
    required this.purchaseArchitecture,
    required this.deckIds,
    required this.bundle5ProductId,
    required this.bundleAllProductId,
    required this.proProductId,
    required this.fullUnlockProductId,
    required this.preferExplicitStableIds,
  });

  final String appKey;
  final String appName;
  final String devAppName;
  final String qaAppName;
  final String publisherName;
  final String legalese;
  final PurchaseArchitecture purchaseArchitecture;
  final List<String> deckIds;
  final String bundle5ProductId;
  final String bundleAllProductId;
  final String proProductId;
  final String fullUnlockProductId;
  final bool preferExplicitStableIds;

  bool get usesLegacyDeckBundles =>
      purchaseArchitecture == PurchaseArchitecture.legacyDeckBundles;

  bool get usesSingleFullUnlock =>
      purchaseArchitecture == PurchaseArchitecture.singleFullUnlock;

  Set<String> get productIds {
    final ids = <String>{};

    if (usesLegacyDeckBundles) {
      ids.addAll(deckIds.map((id) => '${id.toLowerCase()}_unlock'));
      for (final id in [bundle5ProductId, bundleAllProductId, proProductId]) {
        if (id.trim().isNotEmpty) ids.add(id);
      }
    }

    if (usesSingleFullUnlock && fullUnlockProductId.trim().isNotEmpty) {
      ids.add(fullUnlockProductId);
    }

    return ids;
  }
}

/// 現行の高校保健アプリは既存の商品体系・問題ID方式をそのまま維持する。
/// 新しい資格アプリを作るときだけ、この定義を資格固有値へ差し替える。
const currentQuizApp = QuizAppDefinition(
  appKey: 'health',
  appName: '高校保健 一問一答',
  devAppName: '健康クイズ（DEV）',
  qaAppName: '健康クイズ（QA）',
  publisherName: 'KOMADEKI',
  legalese: '© 2026 KOMADEKI',
  purchaseArchitecture: PurchaseArchitecture.legacyDeckBundles,
  deckIds: [
    'deck_m01',
    'deck_m02',
    'deck_m03',
    'deck_m04',
    'deck_m05',
    'deck_m06',
    'deck_m07',
    'deck_m08',
  ],
  bundle5ProductId: 'bundle_5decks_unlock',
  bundleAllProductId: 'bundle_all_unlock',
  proProductId: 'pro_upgrade',
  fullUnlockProductId: '',
  preferExplicitStableIds: false,
);
