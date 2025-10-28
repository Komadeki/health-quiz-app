// lib/services/gate.dart
import 'purchase_store.dart';

/// アプリ内のアクセス権限を一元管理するゲートヘルパー
class Gate {
  /// 単元アクセス判定（deckIdは小文字正規化）
  static Future<bool> canAccessDeck(String deckId) async {
    final id = deckId.toLowerCase();
    // Pro購入者はすべてのデッキを開ける
    if (await PurchaseStore.isPro()) return true;
    // 個別購入デッキのみ開ける
    return await PurchaseStore.isDeckOwned(id);
  }

  /// 複数デッキから「アクセス可能なものだけ」を返す（ミックス用）
  static Future<List<String>> filterAccessibleDecks(Iterable<String> deckIds) async {
    final isPro = await PurchaseStore.isPro();
    if (isPro) return deckIds.map((e) => e.toLowerCase()).toList();
    final owned = (await PurchaseStore.ownedDeckIds()).map((e) => e.toLowerCase()).toSet();
    return deckIds.map((e) => e.toLowerCase()).where(owned.contains).toList();
  }

  /// すべてのデッキが解放済みか（Pro または全所有）
  static Future<bool> isAllUnlocked(Iterable<String> allDeckIds) async {
    final isPro = await PurchaseStore.isPro();
    if (isPro) return true;
    final owned = (await PurchaseStore.ownedDeckIds()).map((e) => e.toLowerCase()).toSet();
    final need = allDeckIds.map((e) => e.toLowerCase());
    return need.every(owned.contains);
  }

  /// 機能アクセス判定（必要に応じて拡張）
  static Future<bool> canUseFeature(String featureKey) async {
    final pro = await PurchaseStore.isPro();
    if (!pro) return false;
    const proFeatures = {'review_test', 'review_cards', 'reminder'};
    return proFeatures.contains(featureKey);
  }
}
