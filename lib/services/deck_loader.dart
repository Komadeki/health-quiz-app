// lib/services/deck_loader.dart
import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/deck.dart';
import '../models/card.dart';

class DeckLoader {
  /// assets/decks/ 配下の deck_*.json を全て読み込んで Deck 化する
  Future<List<Deck>> loadAll() async {
    final manifestJson = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifest = jsonDecode(manifestJson);

    final deckFiles = manifest.keys
        .where((p) => p.startsWith('assets/decks/') && p.endsWith('.json'))
        .where((p) => RegExp(r'assets/decks/deck_.*\.json$').hasMatch(p))
        .toList()
      ..sort();

    final decks = <Deck>[];
    for (final path in deckFiles) {
      try {
        final raw = await rootBundle.loadString(path);
        final map = jsonDecode(raw) as Map<String, dynamic>;

        final unitTitleMap = <String, String>{};
        final units = map['units'];
        if (units is List) {
          for (final u in units) {
            if (u is Map<String, dynamic>) {
              final uid = (u['id'] ?? u['unitId'] ?? u['unit_id'])?.toString();
              final ut = (u['title'] ?? u['unit_title'] ?? u['name'] ?? u['unitTitle'])?.toString();
              if (uid != null && uid.isNotEmpty && ut != null && ut.isNotEmpty) {
                unitTitleMap[uid] = ut.trim();
              }
              final cards = u['cards'];
              if (cards is List) {
                for (final c in cards) {
                  if (c is Map<String, dynamic>) {
                    c.putIfAbsent('unitId', () => uid);
                    if (ut != null && ut.isNotEmpty) {
                      c.putIfAbsent('unitTitle', () => ut.trim());
                    }
                  }
                }
              }
            }
          }
        }
        map['unitTitleMap'] = unitTitleMap;
        decks.add(Deck.fromJson(map));
      } catch (e) {
        print('DeckLoader: failed to load $path: $e');
      }
    }
    return decks;
  }

  /// ★ 全カードフラット版（extensionではなく同クラス内にする）
  Future<List<QuizCard>> loadAllCardsFlatten() async {
    final decks = await loadAll();
    final out = <QuizCard>[];

    for (final d in decks) {
      try {
        if ((d as dynamic).cards != null) {
          out.addAll((d as dynamic).cards as List<QuizCard>);
        } else if ((d as dynamic).units != null) {
          final units = (d as dynamic).units as List<dynamic>;
          for (final u in units) {
            final cards = (u as dynamic).cards as List<QuizCard>?;
            if (cards != null) out.addAll(cards);
          }
        } else if ((d as dynamic).allCards != null) {
          out.addAll((d as dynamic).allCards() as List<QuizCard>);
        }
      } catch (_) {}
    }
    return out;
  }
}
