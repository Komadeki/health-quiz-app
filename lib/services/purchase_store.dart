// lib/services/purchase_store.dart

import 'package:shared_preferences/shared_preferences.dart';

class PurchaseStore {
  static const _kPro = 'proUpgrade';
  static const _kDecks = 'ownedDeckIds'; // List<String>

  // ---- Pro ----
  static Future<bool> isPro() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getBool(_kPro) ?? false;
  }

  static Future<void> setPro(bool v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kPro, v);
  }

  // ---- Decks ----
  static Future<List<String>> ownedDeckIds() async {
    final sp = await SharedPreferences.getInstance();
    return sp.getStringList(_kDecks) ?? <String>[];
  }

  static Future<void> addOwnedDecks(Iterable<String> deckIds) async {
    final sp = await SharedPreferences.getInstance();
    final cur = {...(sp.getStringList(_kDecks) ?? <String>[])};
    cur.addAll(deckIds);
    await sp.setStringList(_kDecks, cur.toList());
  }

  static Future<bool> isDeckOwned(String deckId) async {
    final ids = await ownedDeckIds();
    return ids.contains(deckId);
  }
}
