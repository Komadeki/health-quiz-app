import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/attempt_entry.dart';
import '../models/score_record.dart'; // ★追加
import '../utils/logger.dart';

class AttemptStore {
  // ---- keys ----
  static const String kAttempts = 'attempts_v1'; // 既存: 1問ごとの履歴（AttemptEntry）をJSON配列で保存
  static const String kScores   = 'scores_v2';   // ★追加: 成績サマリ（ScoreRecord）をJSON配列で保存

  static const int defaultRetention = 5000; // AttemptEntryの保持上限

  AttemptStore._();
  static final AttemptStore _i = AttemptStore._();
  factory AttemptStore() => _i;

  // ===========================================================================
  // AttemptEntry（既存機能） — 1問ごとの履歴
  // ===========================================================================

  Future<List<AttemptEntry>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kAttempts);
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final items = <AttemptEntry>[];
      for (final e in list) {
        try {
          final map = (e as Map).cast<String, dynamic>();
          var a = AttemptEntry.fromMap(map);

          // attemptId が無い古いデータに対しては補完
          if ((a.attemptId == null) || (a.attemptId!.isEmpty)) {
            a = a.copyWith(attemptId: const Uuid().v4());
          }
          items.add(a);
        } catch (err) {
          AppLog.w('[AttemptStore] skip broken item: $err');
        }
      }
      return items;
    } catch (e) {
      AppLog.w('[AttemptStore] decode failed: $e');
      return [];
    }
  }

  Future<void> _saveAll(List<AttemptEntry> items) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      // 念のため attemptId が空のものがあれば付与
      final normalized = items
          .map((a) => (a.attemptId == null || a.attemptId!.isEmpty)
              ? a.copyWith(attemptId: const Uuid().v4())
              : a)
          .toList();

      final ok = await prefs.setString(
        kAttempts,
        jsonEncode(normalized.map((e) => e.toMap()).toList()),
      );
      if (!ok) {
        AppLog.w('[AttemptStore] persist failed');
      }
    } catch (e) {
      AppLog.w('[AttemptStore] saveAll failed: $e');
    }
  }

  /// 1問分を追加（既存）
  Future<void> add(AttemptEntry entry, {int? retention}) async {
    final all = await _loadAll();

    // attemptId の自動付与（モデル側で未設定の場合）
    final withId = (entry.attemptId == null || entry.attemptId!.isEmpty)
        ? entry.copyWith(attemptId: const Uuid().v4())
        : entry;

    all.add(withId);

    final cap = retention ?? defaultRetention;
    if (all.length > cap) {
      all.removeRange(0, all.length - cap); // 古い方から間引く
    }
    await _saveAll(all);
  }

  /// 新しいものから最大 limit 件（既存）
  Future<List<AttemptEntry>> recent({int limit = 100}) async {
    final all = await _loadAll();
    return all.reversed.take(limit).toList();
  }

  /// 指定セッションの履歴（新→古）（既存）
  Future<List<AttemptEntry>> bySession(String sessionId) async {
    final all = await _loadAll();
    return all.where((e) => e.sessionId == sessionId).toList().reversed.toList();
  }

  /// 既存のAttemptEntry全削除（既存）
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kAttempts);
  }

  /// AttemptEntry のバックアップ（既存）
  Future<String> exportJson() async {
    final all = await _loadAll();
    return jsonEncode({
      'version': 1,
      'items': all.map((e) => e.toMap()).toList(),
      'count': all.length,
      'exportedAt': DateTime.now().toIso8601String(),
    });
  }

  /// AttemptEntry のインポート（既存）
  Future<int> importJson(String json) async {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final rawItems = (data['items'] as List<dynamic>? ?? const <dynamic>[]);

      final items = <AttemptEntry>[];
      for (final e in rawItems) {
        try {
          final map = (e as Map).cast<String, dynamic>();
          var a = AttemptEntry.fromMap(map);
          if ((a.attemptId == null) || a.attemptId!.isEmpty) {
            a = a.copyWith(attemptId: const Uuid().v4());
          }
          items.add(a);
        } catch (err) {
          AppLog.w('[AttemptStore] import skip broken item: $err');
        }
      }

      final existing = await _loadAll();
      final ids = existing
          .map((e) => e.attemptId ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();

      final toAdd = items.where((e) {
        final id = e.attemptId ?? '';
        return id.isNotEmpty && !ids.contains(id);
      }).toList();

      existing.addAll(toAdd);
      await _saveAll(existing);
      return toAdd.length;
    } catch (e) {
      AppLog.w('[AttemptStore] import failed: $e');
      return 0;
    }
  }

  /// 総件数（デバッグ用）（既存）
  Future<int> count() async {
    final all = await _loadAll();
    return all.length;
  }

  // ===========================================================================
  // ScoreRecord（★新機能） — 1回の結果サマリ（unitBreakdown 含む）
  // ===========================================================================

  Future<List<ScoreRecord>> loadScores() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kScores);
    if (raw == null || raw.isEmpty) return [];
    try {
      return ScoreRecord.decodeList(raw);
    } catch (e) {
      AppLog.w('[AttemptStore] loadScores decode failed: $e');
      return [];
    }
  }

  Future<void> _saveScores(List<ScoreRecord> items) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final ok = await prefs.setString(kScores, ScoreRecord.encodeList(items));
      if (!ok) AppLog.w('[AttemptStore] persist scores failed');
    } catch (e) {
      AppLog.w('[AttemptStore] saveScores failed: $e');
    }
  }

  /// 成績サマリを追加（ResultScreen から呼ぶ想定）
  Future<void> addScore(ScoreRecord record, {int? retention}) async {
    final all = await loadScores();
    all.add(record);

    // retention はサマリ用は必要に応じて（指定なければ無制限）
    final cap = retention ?? 0;
    if (cap > 0 && all.length > cap) {
      all.removeRange(0, all.length - cap);
    }

    await _saveScores(all);
  }

  /// 新しいものから最大 limit 件
  Future<List<ScoreRecord>> recentScores({int limit = 100}) async {
    final all = await loadScores();
    return all.reversed.take(limit).toList();
  }

  /// デッキ別に取得
  Future<List<ScoreRecord>> scoresByDeck(String deckId) async {
    final all = await loadScores();
    return all.where((e) => e.deckId == deckId).toList().reversed.toList();
  }

  /// ScoreRecord 全削除
  Future<void> clearScores() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kScores);
  }

  /// ScoreRecord のバックアップ
  Future<String> exportScoresJson() async {
    final all = await loadScores();
    return jsonEncode({
      'version': 2, // ScoreRecord v2+（sessionId / unitBreakdown など）
      'items': all.map((e) => e.toJson()).toList(),
      'count': all.length,
      'exportedAt': DateTime.now().toIso8601String(),
    });
  }

  /// ScoreRecord のインポート（attempts_v1 とは別系統）
  Future<int> importScoresJson(String json) async {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final rawItems = (data['items'] as List<dynamic>? ?? const <dynamic>[]);

      final items = <ScoreRecord>[];
      for (final e in rawItems) {
        try {
          final m = Map<String, dynamic>.from(e as Map);
          final r = ScoreRecord.fromJson(m);
          items.add(r);
        } catch (err) {
          AppLog.w('[AttemptStore] importScores skip broken item: $err');
        }
      }

      final existing = await loadScores();

      // 重複判定: id をキーに簡易去重（id が空の可能性は基本なし）
      final ids = existing.map((e) => e.id).toSet();
      final toAdd = items.where((e) => !ids.contains(e.id)).toList();

      existing.addAll(toAdd);
      await _saveScores(existing);
      return toAdd.length;
    } catch (e) {
      AppLog.w('[AttemptStore] importScores failed: $e');
      return 0;
    }
  }
}
