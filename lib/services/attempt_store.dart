// lib/services/attempt_store.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart'; // ← 未導入なら追加
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

  /// これまでの誤答の「質問文」を時系列・重複ありで返す（見直しモード用／全期間）
  /// ※ “ID” という名前だが実体は質問文。呼び出し側でカードに写像する。
  Future<List<String>> getAllWrongCardIds() async {
    final all = await _loadAll();
    final out = <String>[];
    for (final e in all) {
      if (!e.isCorrect) {
        final q = (e.question ?? '').trim();
        if (q.isNotEmpty) out.add(q);
      }
    }
    return out;
  }

  /// （★新規）指定セッション群に限定して誤答の「質問文」リストを返す（重複あり・見直しモード用）
  Future<List<String>> getAllWrongCardIdsFiltered({
    List<String>? onlySessionIds,
  }) async {
    final all = await _loadAll();
    final out = <String>[];
    int kept = 0;

    for (final e in all) {
      if (onlySessionIds != null && !onlySessionIds.contains(e.sessionId)) {
        continue;
      }
      if (!e.isCorrect) {
        kept++;
        final q = (e.question ?? '').trim();
        if (q.isNotEmpty) out.add(q);
      }
    }

    if (onlySessionIds != null) {
      debugPrint('[REVIEW] wrong-card set filtered by sessions '
          '(${out.length} items from ${all.length} attempts, kept=$kept)');
    }
    return out;
  }

  // AttemptStore に追記
  Future<Map<String, DateTime>> getWrongLatestAtMap({
    List<String>? onlySessionIds,
  }) async {
    DateTime? _ts(dynamic e) {
      // DateTime 直／ISO文字列／epoch int に緩く対応
      try { final v = (e as dynamic).answeredAt; if (v is DateTime) return v; if (v is String) return DateTime.tryParse(v); if (v is int) return DateTime.fromMillisecondsSinceEpoch(v > 2000000000 ? v : v * 1000); } catch (_) {}
      try { final v = (e as dynamic).timestamp;  if (v is DateTime) return v; if (v is String) return DateTime.tryParse(v); if (v is int) return DateTime.fromMillisecondsSinceEpoch(v > 2000000000 ? v : v * 1000); } catch (_) {}
      try { final v = (e as dynamic).createdAt;  if (v is DateTime) return v; if (v is String) return DateTime.tryParse(v); if (v is int) return DateTime.fromMillisecondsSinceEpoch(v > 2000000000 ? v : v * 1000); } catch (_) {}
      return null;
    }

    final all = await _loadAll();
    final map = <String, DateTime>{};

    for (final e in all) {
      if (onlySessionIds != null && !onlySessionIds.contains(e.sessionId)) continue;
      if (!e.isCorrect) {
        final key = _keyFromAttempt(e);
        if (key.isEmpty) continue;
        final t = _ts(e);
        if (t == null) continue;
        final cur = map[key];
        if (cur == null || t.isAfter(cur)) {
          map[key] = t;
        }
      }
    }
    debugPrint('[REVIEW] latestWrongAt filtered=${onlySessionIds?.length ?? 0} -> ${map.length}');
    return map;
  }

    /// （新規）誤答頻度マップを返す: { key: wrongCount }
  /// key は stableId 優先、無ければ質問文（正規化）で代用
  /// onlySessionIds を指定すると、そのセッションに属する Attempt のみ集計
  Future<Map<String, int>> getWrongFrequencyMap({
    List<String>? onlySessionIds,
  }) async {
    final all = await _loadAll();
    if (all.isEmpty) return <String, int>{};

    final map = <String, int>{};
    int total = 0, kept = 0;

    for (final e in all) {
      total++;
      if (onlySessionIds != null && !onlySessionIds.contains(e.sessionId)) {
        continue;
      }
      if (!e.isCorrect) {
        kept++;
        final key = _keyFromAttempt(e);
        if (key.isEmpty) continue;
        map.update(key, (v) => v + 1, ifAbsent: () => 1);
      }
    }

    // デバッグ出力（スコープが指定されたときだけ）
    if (onlySessionIds != null) {
      try {
        debugPrint('[REVIEW] attempts filtered by sessions: $kept/$total');
      } catch (_) {}
    }
    return map;
  }

  /// key生成ヘルパ（stableId優先・なければ質問文）
  String _keyFromAttempt(AttemptEntry e) {
    // stableId, cardStableId, cardId などプロジェクトの実装に応じて取得
    try {
      final v1 = (e as dynamic).stableId as String?;
      if (v1 != null && v1.trim().isNotEmpty) return v1.trim();
    } catch (_) {}
    try {
      final v2 = (e as dynamic).cardStableId as String?;
      if (v2 != null && v2.trim().isNotEmpty) return v2.trim();
    } catch (_) {}
    try {
      final v3 = (e as dynamic).cardId as String?;
      if (v3 != null && v3.trim().isNotEmpty) return v3.trim();
    } catch (_) {}

    // フォールバック: 質問文を正規化
    final q = (e.question ?? '').trim();
    if (q.isEmpty) return '';
    final normalized = q.replaceAll(RegExp(r'\s+'), ' ');
    return 'Q::$normalized';
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

  /// 成績サマリを追加/更新（sessionId で upsert）
  Future<void> addScore(ScoreRecord record, {int? retention}) async {
    final all = await loadScores();

    // ★ 同じ sessionId があれば置き換え（なければ追加）
    final idx = all.indexWhere((e) => e.sessionId == record.sessionId);
    if (idx >= 0) {
      all[idx] = record;
    } else {
      all.add(record);
    }

    // 任意の保持上限
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

  /// 特定セッションIDにおける誤答の質問文リストを返す（重複あり）
  Future<List<String>> getWrongQuestionsBySession(String sessionId) async {
    final all = await _loadAll();
    final wrong = all.where((e) => e.sessionId == sessionId && !e.isCorrect);
    return wrong
        .map((e) => (e.question ?? '').trim())
        .where((q) => q.isNotEmpty)
        .toList();
  }
}
