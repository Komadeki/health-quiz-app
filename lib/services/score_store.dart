// lib/services/score_store.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/score_record.dart';

/// 成績（ScoreRecord）を保存・読込するストア（v2）
/// - v2 保存先キー: scores.v2 （ScoreRecord[] を JSON 配列で保存）
/// - v1 互換読み: scores.v1 が残っていれば可能な範囲で ScoreRecord に変換して返す
class ScoreStore {
  static const String _kKeyV2 = 'scores.v2';
  static const String _kKeyV1 = 'scores.v1'; // 旧の互換読み取り用

  ScoreStore._();
  static final ScoreStore instance = ScoreStore._();

  /// 新しい順の一覧を取得（v2 → なければ v1 互換）
  Future<List<ScoreRecord>> loadAll() => listAll();

  /// v2（あれば）→ なければ v1 を後方互換で読み、新しい順で返す
  Future<List<ScoreRecord>> listAll() async {
    final prefs = await SharedPreferences.getInstance();

    // --- v2: 現行保存形式 ---
    final rawV2 = prefs.getString(_kKeyV2);
    if (rawV2 != null && rawV2.isNotEmpty) {
      try {
        final list = ScoreRecord.decodeList(rawV2);
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // 新しい→古い
        return list;
      } catch (e) {
        // 破損時は安全側で空配列
      }
    }

    // --- v1: 旧形式（可能な範囲で復元） ---
    final rawV1 = prefs.getString(_kKeyV1);
    if (rawV1 != null && rawV1.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawV1) as List<dynamic>;
        final result = <ScoreRecord>[];
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final r = _fromV1(item);
            if (r != null) result.add(r);
          } else if (item is Map) {
            final r = _fromV1(Map<String, dynamic>.from(item));
            if (r != null) result.add(r);
          }
        }
        result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return result;
      } catch (_) {
        // v1 が全く別構造だった場合は空で返す
      }
    }

    return <ScoreRecord>[];
  }

  /// 1件追加（先頭に積む＝新しい順）
  Future<void> add(ScoreRecord rec) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadAll();
    final updated = [rec, ...current];
    await prefs.setString(_kKeyV2, ScoreRecord.encodeList(updated));
  }

  /// 全削除（v2/v1 両方）
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKeyV2);
    await prefs.remove(_kKeyV1);
  }

  /// エクスポート（v2 のみを対象）
  Future<String> exportJson() async {
    final list = await loadAll();
    return ScoreRecord.encodeList(list);
  }

  // ========= ここから下は v1→v2 互換用の補助 =========

  /// v1（QuizResult っぽい構造）から ScoreRecord を可能な範囲で復元
  /// 期待フィールド例:
  /// - id (String) なくてもOK
  /// - deckId (String) / deckTitle (String?)
  /// - correct or score (int)
  /// - total (int)
  /// - timestamp: epoch(ms) or ISO文字列 or DateTime.toString()
  /// - durationSec (int?) など
  ScoreRecord? _fromV1(Map<String, dynamic> m) {
    try {
      final id = (m['id']?.toString().isNotEmpty == true)
          ? m['id'].toString()
          : '${m['deckId'] ?? 'unknown'}_${m['timestamp'] ?? ''}';

      final deckId = (m['deckId'] as String?) ?? 'unknown';
      final deckTitle = (m['deckTitle'] as String?) ?? '';

      final score = (m['score'] ??
              m['correct'] ??
              m['right'] ??
              0) as int; // フィールド名の揺れを吸収
      final total = (m['total'] ?? m['questions'] ?? 0) as int;

      // timestamp は epoch(ms) or ISO を想定して吸収
      int tsMs;
      final tsRaw = m['timestamp'];
      if (tsRaw is int) {
        tsMs = tsRaw;
      } else if (tsRaw is String) {
        // 文字列は DateTime.parse に賭ける（失敗時は now）
        tsMs = DateTime.tryParse(tsRaw)?.millisecondsSinceEpoch ??
            DateTime.now().millisecondsSinceEpoch;
      } else if (tsRaw is DateTime) {
        tsMs = tsRaw.millisecondsSinceEpoch;
      } else {
        tsMs = DateTime.now().millisecondsSinceEpoch;
      }

      final durationSec = (m['durationSec'] as num?)?.toInt();

      // v1 には sessionId/tags/selectedUnitIds は無い前提で null
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
      );
    } catch (_) {
      return null;
    }
  }
}
