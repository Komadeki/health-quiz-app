// lib/services/gate.dart

import 'purchase_store.dart';

/// アプリ内のアクセス権限を一元管理するゲートヘルパー
class Gate {
  /// 単元アクセス判定
  static Future<bool> canAccessDeck(String deckId) async {
    // Pro購入者はすべてのデッキを開ける
    if (await PurchaseStore.isPro()) return true;
    // 個別購入デッキのみ開ける
    return await PurchaseStore.isDeckOwned(deckId);
  }

  /// 機能アクセス判定
  static Future<bool> canUseFeature(String featureKey) async {
    final pro = await PurchaseStore.isPro();
    if (!pro) return false;

    // Proで使える機能一覧（必要に応じて追加）
    const proFeatures = {'review_test', 'review_cards', 'reminder'};
    return proFeatures.contains(featureKey);
  }
}
