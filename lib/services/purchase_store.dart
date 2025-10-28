// lib/services/purchase_store.dart
import 'package:shared_preferences/shared_preferences.dart';

/// 購入状態の永続ストア（SharedPreferences）
/// - 既存API: isPro / setPro / ownedDeckIds / addOwnedDecks / isDeckOwned
/// - 追加API: getPro / getOwnedDeckIds / clearAll
///   → IapService(完全版) とのインターフェース整合のため
class PurchaseStore {
  // 既存キー名を尊重（変更しない）
  static const _kPro = 'proUpgrade';
  static const _kDecks = 'ownedDeckIds'; // List<String>

  // ---- Pro ----
  /// 既存：Pro判定
  static Future<bool> isPro() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kPro) ?? false;
  }

  /// 追加：IapService(完全版) 互換
  static Future<bool> getPro() => isPro();

  /// 既存：Proフラグ設定
  static Future<void> setPro(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPro, v);
  }

  // ---- Decks ----
  /// 既存：所有デッキID一覧（List<String>）を小文字で返す
  static Future<List<String>> ownedDeckIds() async {
    final sp = await SharedPreferences.getInstance();
    final list = sp.getStringList(_kDecks) ?? <String>[];
    // 旧データ移行：大文字混在を小文字化 + 重複排除 + ソート
    final norm = _normalizeDeckIds(list);
    if (!_listEquals(list, norm)) {
      await sp.setStringList(_kDecks, norm);
    }
    return norm;
  }

  /// 追加：IapService(完全版) 互換（Set<String> で返す）
  static Future<Set<String>> getOwnedDeckIds() async {
    final list = await ownedDeckIds();
    return list.toSet();
  }

  /// 既存：所有デッキ追加（小文字化・重複排除・ソート）
  static Future<void> addOwnedDecks(Iterable<String> deckIds) async {
    final sp = await SharedPreferences.getInstance();
    final cur = sp.getStringList(_kDecks) ?? <String>[];
    final merged = _normalizeDeckIds([...cur, ...deckIds]);
    await sp.setStringList(_kDecks, merged);
  }

  /// 既存：個別デッキの所有判定
  static Future<bool> isDeckOwned(String deckId) async {
    final ids = await ownedDeckIds();
    return ids.contains(deckId.toLowerCase()); // 小文字比較
  }

  /// 追加：データ全消し（テスト/デバッグ用）
  static Future<void> clearAll() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kPro);
    await sp.remove(_kDecks);
  }

  // ---- 内部ユーティリティ ----
  static List<String> _normalizeDeckIds(Iterable<String> deckIds) {
    // 小文字化 → 重複排除 → ソート（安定化のため）
    final set = <String>{};
    for (final id in deckIds) {
      if (id.trim().isEmpty) continue;
      set.add(id.toLowerCase());
    }
    final list = set.toList()..sort();
    return list;
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
