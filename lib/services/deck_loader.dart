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

    // 3) 各ファイルを Deck に変換
    final decks = <Deck>[];
    for (final path in deckFiles) {
      try {
        final raw = await rootBundle.loadString(path);
        final map = jsonDecode(raw) as Map<String, dynamic>;

        // ── 1) unitTitleMap を生成
        final unitTitleMap = <String, String>{};

        final units = map['units'];
        if (units is List) {
          for (final u in units) {
            if (u is Map<String, dynamic>) {
              // あなたのJSON構造では "id" がユニットID、"title" がユニット名
              final uid = (u['id'] ?? u['unitId'] ?? u['unit_id'])?.toString();
              final ut = (u['title'] ??
                      u['unit_title'] ??
                      u['name'] ??
                      u['unitTitle'])
                  ?.toString();

              if (uid != null && uid.isNotEmpty && ut != null && ut.isNotEmpty) {
                unitTitleMap[uid] = ut.trim();
              }

              // ── 2) 各カードに unitId と unitTitle を注入
              final cards = u['cards'];
              if (cards is List) {
                for (final c in cards) {
                  if (c is Map<String, dynamic>) {
                    // unitId がなければ注入
                    c.putIfAbsent('unitId', () => uid);
                    // unitTitle がなければ注入
                    if (ut != null && ut.isNotEmpty) {
                      c.putIfAbsent('unitTitle', () => ut.trim());
                    }
                  }
                }
              }
            }
          }
        }

        // ── 3) Deck にも unitTitleMap を渡す（任意）
        map['unitTitleMap'] = unitTitleMap;

        decks.add(Deck.fromJson(map));
      } catch (e) {
        print('DeckLoader: failed to load $path: $e');
      }
    }
    return decks;
  }
}
