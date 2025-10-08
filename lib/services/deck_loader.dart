// lib/services/deck_loader.dart
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import '../models/deck.dart';

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

    // 3) 各ファイルを Deck に変換（units内のcardsへ unitId を注入）
    final decks = <Deck>[];
    for (final path in deckFiles) {
      try {
        final raw = await rootBundle.loadString(path);
        final map = jsonDecode(raw) as Map<String, dynamic>;

        // ★ ここがポイント：ユニットIDを各カードJSONへ差し込み
        final units = map['units'];
        if (units is List) {
          for (final u in units) {
            if (u is Map<String, dynamic>) {
              final uid = (u['id'] ?? u['unitId'] ?? u['unit_id'])?.toString();
              final cards = u['cards'];
              if (uid != null && uid.isNotEmpty && cards is List) {
                for (final c in cards) {
                  if (c is Map<String, dynamic>) {
                    // 既に unitId/unit_id があれば尊重。無ければ注入。
                    c.putIfAbsent('unitId', () => uid);
                  }
                }
              }
            }
          }
        }

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
