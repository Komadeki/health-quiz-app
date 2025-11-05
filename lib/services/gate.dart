// lib/services/gate.dart
import 'purchase_store.dart';
import 'deck_loader.dart';

/// アプリ内のアクセス権限を一元管理するゲートヘルパー
class Gate {
  // ============ デッキ（deck_xxx）レベル ============

  /// 単元（=デッキ）アクセス判定（deckIdは小文字正規化）
  /// - Pro: 全解放
  /// - 個別/全体購入: OwnedDecks に含まれていれば解放
  /// - 5単元パック: 選択済みの deck が解放
  static Future<bool> canAccessDeck(String deckId) async {
    final id = deckId.toLowerCase();
    if (await PurchaseStore.isPro()) return true;

    // 個別購入/全体解放
    if (await PurchaseStore.isDeckOwned(id)) return true;

    // 5単元パック（選択デッキ）
    final five = await PurchaseStore.getFivePackDecks();
    if (five.contains(id)) return true;

    return false;
  }

  /// 複数デッキから「アクセス可能なものだけ」を返す（ミックス用）
  static Future<List<String>> filterAccessibleDecks(Iterable<String> deckIds) async {
    final ids = deckIds.map((e) => e.toLowerCase()).toList();
    if (await PurchaseStore.isPro()) return ids;

    final owned = (await PurchaseStore.ownedDeckIds()).map((e) => e.toLowerCase()).toSet();
    final five = await PurchaseStore.getFivePackDecks(); // 既に小文字&正規化済み想定
    final allowed = owned.union(five);

    return ids.where(allowed.contains).toList();
  }

  /// すべてのデッキが解放済みか（Pro または全所有 or 5パックで全網羅）
  static Future<bool> isAllUnlocked(Iterable<String> allDeckIds) async {
    final need = allDeckIds.map((e) => e.toLowerCase()).toList();
    if (await PurchaseStore.isPro()) return true;

    final owned = (await PurchaseStore.ownedDeckIds()).map((e) => e.toLowerCase()).toSet();
    final five = await PurchaseStore.getFivePackDecks();
    final allowed = owned.union(five);

    return need.every(allowed.contains);
  }

  // ============ 小単元（unitId）レベル ============

  /// 小単元アクセス判定（deckId を渡せるなら高速）
  /// - Pro: 全解放
  /// - デッキ購入/全解放: その配下の小単元は全解放
  /// - 5単元パック: 選択済み「デッキ」に属する小単元は全解放
  static Future<bool> canAccessUnit(String unitId, {String? deckId}) async {
    if (await PurchaseStore.isPro()) return true;

    // deckId が未指定なら DeckLoader から逆引き
    var did = deckId?.toLowerCase();
    if (did == null || did.isEmpty) {
      // インデックスが無ければ初期化（初回のみ）
      await DeckLoader.instance();
      did = DeckLoader.deckIdOfUnit(unitId).toLowerCase();
    }
    if (did.isEmpty) return false;

    // デッキ所有 or 5パック選択デッキ
    if (await PurchaseStore.isDeckOwned(did)) return true;
    final five = await PurchaseStore.getFivePackDecks();
    if (five.contains(did)) return true;

    return false;
  }

  /// 小単元のフィルタ（アクセス可能なものだけ）
  /// unitId→deckId の対応が分かる場合は map を渡すと高速。
  static Future<List<String>> filterAccessibleUnits(
    Iterable<String> unitIds, {
    Map<String, String>? unitToDeckId, // unitId -> deckId
  }) async {
    if (await PurchaseStore.isPro()) return unitIds.toList();

    // 事前取得（I/O回数削減）
    final owned = (await PurchaseStore.ownedDeckIds()).map((e) => e.toLowerCase()).toSet();
    final five = await PurchaseStore.getFivePackDecks();
    final allowedDecks = owned.union(five);

    // 逆引きが無い場合は DeckLoader で補う
    Map<String, String> map = unitToDeckId ?? {};
    if (map.isEmpty) {
      await DeckLoader.instance();
      // DeckLoader から deck を逆引きして作る
      final tmp = <String, String>{};
      for (final uid in unitIds) {
        final did = DeckLoader.deckIdOfUnit(uid);
        if (did.isNotEmpty) tmp[uid] = did;
      }
      map = tmp;
    }

    final out = <String>[];
    for (final uid in unitIds) {
      final did = map[uid]?.toLowerCase();
      if (did != null && allowedDecks.contains(did)) {
        out.add(uid);
      }
    }
    return out;
  }

  // ============ 機能フラグ ============

  /// 機能アクセス判定（必要に応じて拡張）
  static Future<bool> canUseFeature(String featureKey) async {
    final pro = await PurchaseStore.isPro();
    if (!pro) return false;
    const proFeatures = {'review_test', 'review_cards', 'reminder'};
    return proFeatures.contains(featureKey);
  }
}
