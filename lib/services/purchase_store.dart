// lib/services/purchase_store.dart
import 'package:shared_preferences/shared_preferences.dart';
import 'deck_loader.dart'; // unit→deck 逆引き用

/// 購入状態の永続ストア（SharedPreferences）
/// 既存API: isPro / setPro / ownedDeckIds / addOwnedDecks / isDeckOwned
/// 追加API(5パック・deck基準):
///   - isFivePackOwned / setFivePackOwned
///   - getFivePackDecks / setFivePackDecks / clearFivePackDecks
/// 互換: 旧 fivePack.selectedUnits（unit基準）が見つかったら deck に自動移行
class PurchaseStore {
  // ---- 既存キー（変更しない）----
  static const _kPro = 'proUpgrade';
  static const _kDecks = 'ownedDeckIds'; // List<String>

  // ---- 5単元パック（deck基準）----
  static const _kFivePackOwned = 'fivePack.owned'; // bool
  static const _kFivePackDecks = 'fivePack.selectedDecks'; // List<String>

  // ---- レガシー（unit基準）キー：読み取りのみ（自動移行のため）----
  static const _kFivePackUnitsLegacy = 'fivePack.selectedUnits'; // List<String>
  static const int fivePackLimit = 5;

  // ========== Pro ==========
  static Future<bool> isPro() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kPro) ?? false;
  }

  static Future<bool> getPro() => isPro();
  static Future<void> setPro(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPro, v);
  }

  // ========== Decks（単体デッキの所有）==========
  static Future<List<String>> ownedDeckIds() async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_kDecks) ?? <String>[];
    final norm = _normalizeDeckIds(list);
    if (!_listEquals(list, norm)) {
      await sp.setStringList(_kDecks, norm);
    }
    return norm;
  }

  static Future<Set<String>> getOwnedDeckIds() async {
    final list = await ownedDeckIds();
    return list.toSet();
  }

  static Future<void> addOwnedDecks(Iterable<String> deckIds) async {
    final sp = await SharedPreferences.getInstance();
    final cur = sp.getStringList(_kDecks) ?? <String>[];
    final merged = _normalizeDeckIds([...cur, ...deckIds]);
    await sp.setStringList(_kDecks, merged);
  }

  static Future<bool> isDeckOwned(String deckId) async {
    final ids = await ownedDeckIds();
    return ids.contains(deckId.toLowerCase());
  }

  // ========== Five Pack（選べる5単元パック：deck基準）==========
  static Future<bool> isFivePackOwned() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kFivePackOwned) ?? false;
  }

  static Future<void> setFivePackOwned(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kFivePackOwned, v);
  }

  /// 現在選択されている deckId セット（初回は旧unit保存から自動移行）
  static Future<Set<String>> getFivePackDecks() async {
    final sp = await SharedPreferences.getInstance();

    // まず deck版キー
    final decks = sp.getStringList(_kFivePackDecks) ?? const <String>[];
    if (decks.isNotEmpty) {
      return _normalizeDeckIds(decks).toSet();
    }

    // 無ければレガシー（unit版）から移行
    final legacyUnits = sp.getStringList(_kFivePackUnitsLegacy) ?? const <String>[];
    if (legacyUnits.isEmpty) return <String>{};

    // DeckLoader が未初期化の可能性があるので念のためロード
    await DeckLoader.instance();

    final migrated = <String>{};
    for (final u in legacyUnits) {
      if (u.trim().isEmpty) continue;
      final deckId = DeckLoader.deckIdOfUnit(u);
      if (deckId.isEmpty) continue;
      migrated.add(deckId.toLowerCase());
      if (migrated.length >= fivePackLimit) break;
    }

    final normalized = _normalizeDeckIds(migrated);
    await sp.setStringList(_kFivePackDecks, normalized);
    await sp.remove(_kFivePackUnitsLegacy);
    return normalized.toSet();
  }

  /// deckId を最大 fivePackLimit 保存
  static Future<void> setFivePackDecks(Set<String> deckIds) async {
    final sp = await SharedPreferences.getInstance();
    final trimmed = deckIds
        .where((e) => e.trim().isNotEmpty)
        .map((e) => e.toLowerCase())
        .toSet()
        .take(fivePackLimit)
        .toList()
      ..sort();
    await sp.setStringList(_kFivePackDecks, trimmed);
  }

  static Future<void> clearFivePackDecks() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kFivePackDecks);
  }

  // ========== レガシーAPI（互換）==========
  @Deprecated('Use getFivePackDecks() instead.')
  static Future<Set<String>> getFivePackUnits() async {
    // 旧呼び出しが残っても落ちないよう、deck集合を返す
    return getFivePackDecks();
  }

  @Deprecated('Use setFivePackDecks() instead.')
  static Future<void> setFivePackUnits(Set<String> unitIds) async {
    await DeckLoader.instance();
    final deckIds = unitIds
        .where((u) => u.trim().isNotEmpty)
        .map((u) => DeckLoader.deckIdOfUnit(u))
        .where((d) => d.trim().isNotEmpty)
        .map((d) => d.toLowerCase())
        .toSet();
    await setFivePackDecks(deckIds);
  }

  @Deprecated('Use clearFivePackDecks() instead.')
  static Future<void> clearFivePackUnits() async {
    await clearFivePackDecks();
  }

  // ========== デバッグ用：全消去 ==========
  static Future<void> clearAll() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kPro);
    await sp.remove(_kDecks);
    await sp.remove(_kFivePackOwned);
    await sp.remove(_kFivePackDecks);
    await sp.remove(_kFivePackUnitsLegacy);
  }

  // ========== 内部ユーティリティ ==========
  static List<String> _normalizeDeckIds(Iterable<String> deckIds) {
    final set = <String>{};
    for (final id in deckIds) {
      final t = id.trim();
      if (t.isEmpty) continue;
      set.add(t.toLowerCase());
    }
    final list = set.toList()..sort();
    return list; // 重複排除 & 小文字化 & ソート
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
