// lib/services/deck_loader.dart
import 'dart:convert';
import 'package:flutter/foundation.dart'; // compute 用（JSON decode のみ）
import 'package:flutter/services.dart' show rootBundle;

import '../models/deck.dart';
import '../models/card.dart';
import '../utils/stable_id.dart';

/// Deck/QuizCard のローダ兼インデクサ
/// - 初回ロード時に assets/decks/deck_*.json を全読込
/// - QuizCard を「内容から計算した stableId」で引けるインデックスを構築
/// - JSON デコードは compute で別 Isolate、インデックス構築はメインで安全に
/// - 既存 API(loadAll, loadAllCardsFlatten) は互換維持
class DeckLoader {
  DeckLoader._internal();

  static DeckLoader? _instance;
  static Future<DeckLoader>? _pending; // 同時呼び出し防止

  /// シングルトン取得。forceReload=true で再構築
  static Future<DeckLoader> instance({bool forceReload = false}) {
    if (!forceReload && _instance != null && _instance!._loaded) {
      return Future.value(_instance);
    }
    if (!forceReload && _pending != null) return _pending!;

    final loader = DeckLoader._internal();
    final fut = loader._reload().then((_) {
      _instance = loader;
      _pending = null;
      return loader;
    });
    _pending = fut;
    return fut;
  }

  // ========= 内部状態（キャッシュ） =========
  bool _loaded = false;
  List<Deck> _decks = [];
  final Map<String, QuizCard> _byStableId = {}; // 内容ベース stableId -> card
  final Map<String, QuizCard> _byAnyId = {};    // 既存の id 等 -> card（フォールバック）

  // ========= 公開API：互換維持 =========

  /// assets/decks/ 配下の deck_*.json を全て読み込んで Deck 化する
  /// ※キャッシュ済みならそれを返す
  Future<List<Deck>> loadAll() async {
    if (!_loaded) {
      await _reload();
    }
    return _decks;
  }

  /// 全カードフラット版（互換維持／内部キャッシュ利用）
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

  // ========= 追加API：stableId ド直結 =========

  /// 内容から計算された stableId（question + original choices）で取得
  QuizCard? getByStableId(String stableId) => _byStableId[stableId];

  /// stableId 群をカードへ変換（見つかった分だけ返す）
  List<QuizCard> mapStableIdsToCards(List<String> ids) {
    final out = <QuizCard>[];
    for (final id in ids) {
      final c = _byStableId[id];
      if (c != null) out.add(c);
    }
    return out;
  }

  /// インデックス全体（読み取り専用目的）
  Map<String, QuizCard> get allCardsByStableId => _byStableId;

  // ========= フォールバック用（既存 id 群でも可） =========
  QuizCard? getByAnyId(String anyId) => _byStableId[anyId] ?? _byAnyId[anyId];

  // ========= 内部処理 =========

  Future<void> _reload() async {
    // 軽い譲歩でフレームを空ける（UI密集時のスパイク回避）
    await Future.delayed(const Duration(milliseconds: 30));

    _decks = await _loadDecksFromAssets();

    // ▼ インデックス構築（メインアイソレートで安全に）
    _byStableId.clear();
    _byAnyId.clear();

    for (final d in _decks) {
      final cards = <QuizCard>[];
      try {
        if ((d as dynamic).cards != null) {
          cards.addAll((d as dynamic).cards as List<QuizCard>);
        } else if ((d as dynamic).units != null) {
          final units = (d as dynamic).units as List<dynamic>;
          for (final u in units) {
            final list = (u as dynamic).cards as List<QuizCard>?;
            if (list != null) cards.addAll(list);
          }
        }
      } catch (_) {}

      for (final c in cards) {
        // 1) 内容から安定IDを必ず計算（データ側に stableId が無くても一致）
        final sid = stableIdForOriginal(c);
        _byStableId.putIfAbsent(sid, () => c);

        // 2) 既存IDたちでも逆引きできるようにフォールバック索引を作る
        void _addAny(String? v) {
          if (v == null) return;
          final t = v.trim();
          if (t.isEmpty) return;
          _byAnyId.putIfAbsent(t, () => c);
        }

        try { _addAny((c as dynamic).stableId as String?); } catch (_) {}
        try { _addAny((c as dynamic).cardStableId as String?); } catch (_) {}
        try { _addAny((c as dynamic).id as String?); } catch (_) {}
        try { _addAny((c as dynamic).uuid as String?); } catch (_) {}
        try { _addAny((c as dynamic).key as String?); } catch (_) {}
      }
    }

    _loaded = true;
  }

  /// AssetManifest から deck_*.json を列挙し、各 JSON を decode → Deck 化
  Future<List<Deck>> _loadDecksFromAssets() async {
    final manifestJson = await rootBundle.loadString('AssetManifest.json');
    final Map<String, dynamic> manifest = jsonDecode(manifestJson);

    final deckFiles = manifest.keys
        .where((p) => p.startsWith('assets/decks/') && p.endsWith('.json'))
        .where((p) => RegExp(r'assets/decks/deck_.*\.json$').hasMatch(p))
        .toList()
      ..sort();

    // 各ファイルを compute 経由で並列デコード
    final futures = deckFiles.map(_decodeDeckAsync).toList();
    final decks = await Future.wait(futures, eagerError: false);
    return decks.whereType<Deck>().toList();
  }

  /// 個別デッキを別 isolate で decode → Deck 化
  Future<Deck?> _decodeDeckAsync(String path) async {
    try {
      final raw = await rootBundle.loadString(path);
      final map = await compute<String, Map<String, dynamic>>(_parseJsonToMap, raw);

      // unitTitle を各カードに冗長コピー（既存挙動を踏襲）
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

      return Deck.fromJson(map);
    } catch (e) {
      // 失敗は握りつぶして継続（他のファイルを読み込む）
      // ignore: avoid_print
      print('DeckLoader: failed to load $path: $e');
      return null;
    }
  }

  /// isolate 側で JSON decode
  static Map<String, dynamic> _parseJsonToMap(String s) =>
      jsonDecode(s) as Map<String, dynamic>;
}
