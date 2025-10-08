// lib/services/score_store.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/score_record.dart';
import 'attempt_store.dart';

/// 成績（ScoreRecord）のストア（互換 + アダプタ）
/// - 読み込み: AttemptStore(scores_v2) + 旧キー(scores.v2 / scores.v1)をマージして返す
/// - 書き込み/削除: AttemptStore に委譲（旧キーは読み取り専用）
/// - エクスポート: マージ結果を配列JSON（従来形式）で返す（互換維持）
/// - インポート: 配列JSONを個別に AttemptStore へ追加（失敗時のみ AttemptStore のimportへ）
class ScoreStore {
  static const String _kKeyV2 = 'scores.v2'; // 旧v2キー（ドット）
  static const String _kKeyV1 = 'scores.v1'; // 旧v1キー（ドット）

  ScoreStore._();
  static final ScoreStore instance = ScoreStore._();

  /// 新しい順の一覧（AttemptStore + 旧キーをマージ）
  Future<List<sr.ScoreRecord>> loadAll() => listAll();

  Future<List<sr.ScoreRecord>> listAll() async {
    // 1) AttemptStore（現行実体）
    final attemptScores = await AttemptStore().loadScores();

    // 2) 旧キー（v2/v1）を読み取り（存在すれば）
    final prefs = await SharedPreferences.getInstance();

    final merged = <String, ScoreRecord>{};
    // 先に AttemptStore を入れて「新実装のレコードを優先」
    for (final r in attemptScores) {
      merged[r.id] = r;
    }

    // --- 旧v2: scores.v2（配列JSON: ScoreRecord[]） ---
    final rawV2 = prefs.getString(_kKeyV2);
    if (rawV2 != null && rawV2.isNotEmpty) {
      try {
        final list = ScoreRecord.decodeList(rawV2);
        for (final r in list) {
          // AttemptStore 側に同じidがあればそれを優先
          merged.putIfAbsent(r.id, () => r);
        }
      } catch (_) {
        // 壊れていても無視（安全側）
      }
    }

    // --- 旧v1: scores.v1（配列JSON: QuizResult風） ---
    final rawV1 = prefs.getString(_kKeyV1);
    if (rawV1 != null && rawV1.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawV1) as List<dynamic>;
        for (final item in decoded) {
          final r = (item is Map<String, dynamic>)
              ? _fromV1(item)
              : (item is Map)
                  ? _fromV1(Map<String, dynamic>.from(item))
                  : null;
          if (r != null) {
            merged.putIfAbsent(r.id, () => r);
          }
        }
      } catch (_) {
        // 旧v1が全く別構造でも無視
      }
    }

    // 3) 新→古で返却
    final out = merged.values.toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return out;
  }

  /// 1件追加（AttemptStore へ委譲）
  Future<void> add(sr.ScoreRecord rec) async {
    await AttemptStore().addScore(rec);
  }

  /// 全削除（AttemptStore も旧キーもクリア）
  Future<void> clearAll() async {
    await AttemptStore().clearScores();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKeyV2);
    await prefs.remove(_kKeyV1);
  }

  /// エクスポート（従来通り: 配列JSON）
  Future<String> exportJson() async {
    final list = await loadAll();
    return ScoreRecord.encodeList(list);
  }

  /// インポート（配列JSON想定）→ AttemptStore に追加
  /// - 失敗した場合のみ AttemptStore の import 形式にフォールバック
  Future<int> importJson(String json) async {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        int added = 0;
        for (final e in decoded) {
          try {
            final m = Map<String, dynamic>.from(e as Map);
            final r = ScoreRecord.fromJson(m);
            await AttemptStore().addScore(r);
            added++;
          } catch (_) {
            // 個別に無視
          }
        }
        return added;
      }
    } catch (_) {
      // noop -> フォールバックへ
    }
    // フォールバック: AttemptStore の import 形式（versioned JSON 等）に対応
    return AttemptStore().importScoresJson(json);
  }

  // ========= ここから下は v1→v2 互換用の補助 =========

  /// v1（QuizResult っぽい構造）から sr.ScoreRecord を可能な範囲で復元
  ScoreRecord? _fromV1(Map<String, dynamic> m) {
    try {
      final id = (m['id']?.toString().isNotEmpty == true)
          ? m['id'].toString()
          : '${m['deckId'] ?? 'unknown'}_${m['timestamp'] ?? ''}';

      final deckId = (m['deckId'] as String?) ?? 'unknown';
      final deckTitle = (m['deckTitle'] as String?) ?? '';

      final score = (m['score'] ?? m['correct'] ?? m['right'] ?? 0) as int;
      final total = (m['total'] ?? m['questions'] ?? 0) as int;

      // timestamp は epoch(ms) or ISO を想定して吸収
      int tsMs;
      final tsRaw = m['timestamp'];
      if (tsRaw is int) {
        tsMs = tsRaw;
      } else if (tsRaw is String) {
        tsMs = DateTime.tryParse(tsRaw)?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch;
      } else if (tsRaw is DateTime) {
        tsMs = tsRaw.millisecondsSinceEpoch;
      } else {
        tsMs = DateTime.now().millisecondsSinceEpoch;
      }

      final durationSec = (m['durationSec'] as num?)?.toInt();

      // v1 には sessionId/tags/selectedUnitIds/unitBreakdown は無し
      return ScoreRecord(
        id: id,
        deckId: deckId,
        deckTitle: deckTitle,
        score: score,
        total: total,
        timestamp: tsMs,
        durationSec: durationSec,
        tags: null,
        selectedUnitIds: null,
        sessionId: null,
        unitBreakdown: null,
      );
    } catch (_) {
      return null;
    }
  }
  /// 1件削除（id指定）
  Future<void> delete(String id) async {
    final all = await loadAll();
    final before = all.length;
    all.removeWhere((e) => e.id == id);
    if (all.length != before) {
      // AttemptStore に反映（AttemptStore でも削除）
      await AttemptStore().clearScores();
      for (final r in all) {
        await AttemptStore().addScore(r);
      }

      // SharedPreferences 旧キーも再保存（互換性のため）
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kKeyV2, ScoreRecord.encodeList(all));
    }
  }
}
