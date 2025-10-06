// lib/services/deck_loader.dart
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import '../models/deck.dart'; // ★ これが無いと Deck が未定義になる

class DeckLoader {
  /// assets/decks/ 配下の deck_*.json を全て読み込んで Deck 化する
  Future<List<Deck>> loadAll() async {
    // 1) AssetManifest からファイル一覧を取る
    final manifestJson = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifest = jsonDecode(manifestJson);

    // 2) assets/decks/deck_*.json だけを拾う
    final deckFiles = manifest.keys
        .where((p) => p.startsWith('assets/decks/') && p.endsWith('.json'))
        .where((p) => RegExp(r'assets/decks/deck_.*\.json$').hasMatch(p))
        .toList()
      ..sort();

    // 3) 各ファイルを Deck に変換
    final decks = <Deck>[];
    for (final path in deckFiles) {
      try {
        final raw = await rootBundle.loadString(path);
        final map = jsonDecode(raw) as Map<String, dynamic>;
        decks.add(Deck.fromJson(map));
      } catch (e) {
        // 読み込みに失敗したファイルはスキップ（原因はコンソールで確認）
        // ignore: avoid_print
        print('DeckLoader: failed to load $path: $e');
      }
    }
    return decks;
  }
}
