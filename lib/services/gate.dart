// lib/services/gate.dart
import '../quiz_app_definition.dart';
import 'deck_loader.dart';
import 'shared_preferences_entitlement_cache.dart';

/// アプリ内のアクセス権限を一元管理するゲートヘルパー
class Gate {
  static final _definition = currentQuizApp.monetization;
  static final _cache = SharedPreferencesEntitlementCache(
    catalog: _definition.productCatalog,
  );

  // ============ デッキ（deck_xxx）レベル ============

  /// 単元（=デッキ）アクセス判定（deckIdは小文字正規化）
  /// - 個別/全体購入: OwnedDecks に含まれていれば解放
  /// - 5単元パック: 選択済みの deck が解放
  static Future<bool> canAccessDeck(String deckId) async {
    final snapshot = await _cache.load();
    return _definition.entitlementPolicy.canAccessContent(
      deckId: deckId,
      isPremium: true,
      snapshot: snapshot,
      catalog: _definition.productCatalog,
    );
  }

  /// 複数デッキから「アクセス可能なものだけ」を返す（ミックス用）
  static Future<List<String>> filterAccessibleDecks(
      Iterable<String> deckIds) async {
    final ids = deckIds.map((e) => e.toLowerCase()).toList();
    final snapshot = await _cache.load();
    return ids
        .where(
          (deckId) => _definition.entitlementPolicy.canAccessContent(
            deckId: deckId,
            isPremium: true,
            snapshot: snapshot,
            catalog: _definition.productCatalog,
          ),
        )
        .toList();
  }

  /// すべてのデッキが解放済みか（全所有 or 5パックで全網羅）
  static Future<bool> isAllUnlocked(Iterable<String> allDeckIds) async {
    final need = allDeckIds.map((e) => e.toLowerCase()).toList();
    final snapshot = await _cache.load();
    return need.every(
      (deckId) => _definition.entitlementPolicy.canAccessContent(
        deckId: deckId,
        isPremium: true,
        snapshot: snapshot,
        catalog: _definition.productCatalog,
      ),
    );
  }

  // ============ 小単元（unitId）レベル ============

  /// 小単元アクセス判定（deckId を渡せるなら高速）
  /// - デッキ購入/全解放: その配下の小単元は全解放
  /// - 5単元パック: 選択済み「デッキ」に属する小単元は全解放
  static Future<bool> canAccessUnit(String unitId, {String? deckId}) async {
    // deckId が未指定なら DeckLoader から逆引き
    var did = deckId?.toLowerCase();
    if (did == null || did.isEmpty) {
      // インデックスが無ければ初期化（初回のみ）
      await DeckLoader.instance();
      did = DeckLoader.deckIdOfUnit(unitId).toLowerCase();
    }
    if (did.isEmpty) return false;

    return canAccessDeck(did);
  }

  /// 小単元のフィルタ（アクセス可能なものだけ）
  /// unitId→deckId の対応が分かる場合は map を渡すと高速。
  static Future<List<String>> filterAccessibleUnits(
    Iterable<String> unitIds, {
    Map<String, String>? unitToDeckId, // unitId -> deckId
  }) async {
    final snapshot = await _cache.load();

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
      if (did != null &&
          _definition.entitlementPolicy.canAccessContent(
            deckId: did,
            isPremium: true,
            snapshot: snapshot,
            catalog: _definition.productCatalog,
          )) {
        out.add(uid);
      }
    }
    return out;
  }

  // ============ 機能フラグ ============

  /// 機能アクセス判定（必要に応じて拡張）
  static Future<bool> canUseFeature(String featureKey) async {
    final snapshot = await _cache.load();
    return _definition.entitlementPolicy.canAccessFeature(
      featureKey: featureKey,
      snapshot: snapshot,
      catalog: _definition.productCatalog,
    );
  }
}
