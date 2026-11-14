// lib/services/attempt_store.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';
import '../models/attempt_entry.dart';
import '../models/score_record.dart'; // ← 298行目以降で利用
import '../models/review_scope.dart';
import '../utils/logger.dart';

class AttemptStore {
  // ---- keys ----
  static const String kAttempts =
      'attempts_v1'; // 既存: 1問ごとの履歴（AttemptEntry）をJSON配列で保存
  static const String kScores =
      'scores_v2'; // 成績サマリ（ScoreRecord）をJSON配列で保存（298行目以降で使用）

  static const int defaultRetention = 5000; // AttemptEntryの保持上限

  AttemptStore._();
  static final AttemptStore _i = AttemptStore._();
  factory AttemptStore() => _i;

  // ===== stableIdベースの新API（見直しモード／復習テスト用） =====

  /// スコープ内（任意）で、誤答となった stableId をユニークに返す
  Future<List<String>> getWrongStableIdsUnique({
    List<String>? onlySessionIds,
  }) async {
    final all = await _loadAll();
    final out = <String>{};

    for (final e in all) {
      // セッション絞り込み
      if (onlySessionIds != null && !onlySessionIds.contains(e.sessionId)) {
        continue;
      }
      // 正誤
      if (e.isCorrect == true) continue;

      // stableId を安全に取得（存在しない型でもコンパイルエラーにならないよう dynamic で握る）
      String? sid;
      try {
        sid = (e as dynamic).stableId as String?;
      } catch (_) {}
      if (sid != null && sid.trim().isNotEmpty) {
        out.add(sid.trim());
      }
    }
    return out.toList();
  }

  /// スコープ内（任意）で、stableId ごとの誤答回数を返す
  Future<Map<String, int>> getWrongFrequencyByStableId({
    List<String>? onlySessionIds,
  }) async {
    final all = await _loadAll();
    final map = <String, int>{};

    for (final e in all) {
      if (onlySessionIds != null && !onlySessionIds.contains(e.sessionId)) {
        continue;
      }
      if (e.isCorrect == true) continue;

      String? sid;
      try {
        sid = (e as dynamic).stableId as String?;
      } catch (_) {}
      if (sid == null || sid.trim().isEmpty) continue;

      final key = sid.trim();
      map.update(key, (v) => v + 1, ifAbsent: () => 1);
    }
    return map;
  }

  /// スコープ内（任意）で、stableId ごとの「最新の誤答時刻」を返す
  Future<Map<String, DateTime>> getLatestWrongAtByStableId({
    List<String>? onlySessionIds,
  }) async {
    final all = await _loadAll();
    final map = <String, DateTime>{};

    DateTime? ts(dynamic x) {
      // answeredAt / createdAt / timestamp / *_ms / *_sec など、緩めに吸収
      DateTime? tryParse(dynamic v) {
        if (v == null) return null;
        if (v is DateTime) return v;
        if (v is String) return DateTime.tryParse(v);
        if (v is num) {
          // 10桁程度なら秒、13桁程度ならミリ秒とみなす簡易ハンドリング
          final n = v.toInt();
          final ms = (n > 2000000000) ? n : n * 1000;
          return DateTime.fromMillisecondsSinceEpoch(ms);
        }
        return null;
      }

      try {
        final e = x as dynamic;
        return tryParse(e.answeredAt) ??
            tryParse(e.answeredAtMs) ??
            tryParse(e.createdAt) ??
            tryParse(e.createdAtMs) ??
            tryParse(e.timestamp) ??
            tryParse(e.time) ??
            tryParse(e.at) ??
            tryParse(e.finishedAt) ??
            tryParse(e.completedAt);
      } catch (_) {
        return null;
      }
    }

    for (final e in all) {
      if (onlySessionIds != null && !onlySessionIds.contains(e.sessionId)) {
        continue;
      }
      if (e.isCorrect == true) continue;

      String? sid;
      try {
        sid = (e as dynamic).stableId as String?;
      } catch (_) {}
      if (sid == null || sid.trim().isEmpty) continue;

      final t = ts(e);
      if (t == null) continue;

      final key = sid.trim();
      final cur = map[key];
      if (cur == null || t.isAfter(cur)) {
        map[key] = t;
      }
    }
    return map;
  }

  // ===========================================================================
  // AttemptEntry（既存機能） — 1問ごとの履歴
  // ===========================================================================

  /// 質問テキストを AttemptStore 互換キーへ（空白のみ畳む）
  static String _questionKey(String raw) =>
      'Q::${raw.replaceAll(RegExp(r'\\s+'), ' ').trim()}';

  Future<List<AttemptEntry>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    // 新キー（attempts_v1）を優先し、データが無ければ旧キー（attempts.v1）を試す
    String? raw = prefs.getString(kAttempts);
    if (raw == null || raw.isEmpty) {
      raw = prefs.getString('attempts.v1');
    }
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final items = <AttemptEntry>[];
      for (final e in list) {
        try {
          final map = (e as Map).cast<String, dynamic>();
          var a = AttemptEntry.fromMap(map);

          // attemptId の補完（後方互換）
          if ((a.attemptId == null) || a.attemptId!.isEmpty) {
            a = a.copyWith(attemptId: const Uuid().v4());
          }

          // ★ stableId の補完（既存データ救済）
          //   - すでに stableId があれば何もしない
          //   - なければ 質問テキストから Q::キーを埋める
          if ((a.stableId == null || a.stableId!.isEmpty) &&
              (a.question.trim().isNotEmpty)) {
            a = a.copyWith(stableId: _questionKey(a.question));
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
      // 念のため attemptId / stableId を正規化してから保存
      final normalized = items.map((a0) {
        var a = a0;
        if (a.attemptId == null || a.attemptId!.isEmpty) {
          a = a.copyWith(attemptId: const Uuid().v4());
        }
        if ((a.stableId == null || a.stableId!.isEmpty) &&
            (a.question.trim().isNotEmpty)) {
          a = a.copyWith(stableId: _questionKey(a.question));
        }
        return a;
      }).toList();

      final ok = await prefs.setString(
        kAttempts,
        jsonEncode(normalized.map((e) => e.toMap()).toList()),
      );
      if (!ok) {
        throw StateError('Failed to persist answers');
      }
    } catch (e) {
      AppLog.w('[AttemptStore] saveAll failed: $e');
      rethrow;
    }
  }

  /// 1問分を追加（既存＋stableId補完）
  Future<void> add(AttemptEntry entry, {int? retention}) async {
    final all = await _loadAll();

    // attemptId の自動付与
    var withId = (entry.attemptId == null || entry.attemptId!.isEmpty)
        ? entry.copyWith(attemptId: const Uuid().v4())
        : entry;

    // ★ stableId の自動補完
    if ((withId.stableId == null || withId.stableId!.isEmpty) &&
        (withId.question.trim().isNotEmpty)) {
      withId = withId.copyWith(stableId: _questionKey(withId.question));
    }

    // A save retry uses the same attempt ID and replaces its checkpoint.
    final existing = all.indexWhere((a) => a.attemptId == withId.attemptId);
    if (existing < 0) {
      all.add(withId);
    } else {
      all[existing] = withId;
    }

    final cap = retention ?? defaultRetention;
    if (all.length > cap) {
      all.removeRange(0, all.length - cap); // 古い方から間引く
    }
    await _saveAll(all);
    debugPrint(
      '[ATTEMPT/STORE] add sid=${withId.sessionId} total=${all.length}',
    );
  }

  /// 新しいものから最大 limit 件（既存）
  Future<List<AttemptEntry>> recent({int limit = 100}) async {
    final all = await _loadAll();
    return all.reversed.take(limit).toList();
  }

  /// 指定セッションの履歴（新→古）（既存）
  Future<List<AttemptEntry>> bySession(String sessionId) async {
    final all = await _loadAll();
    final out =
        all.where((e) => e.sessionId == sessionId).toList().reversed.toList();
    debugPrint('[ATTEMPT/STORE] bySession sid=$sessionId -> ${out.length}');
    return out;
  }

  /// これまでの誤答の「質問文」を時系列・重複ありで返す（見直しモード用／全期間）
  /// ※ 互換性のため “ID” という名前だが実体は質問文。呼び出し側でカードに写像する。
  Future<List<String>> getAllWrongCardIds() async {
    final all = await _loadAll();
    final out = <String>[];
    for (final e in all) {
      if (!e.isCorrect) {
        final q = e.question.trim();
        if (q.isNotEmpty) out.add(q);
      }
    }
    return out;
  }

  /// 指定セッション群に限定して誤答の「質問文」リストを返す（重複あり・見直しモード用）
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
        final q = e.question.trim();
        if (q.isNotEmpty) out.add(q);
      }
    }

    if (onlySessionIds != null) {
      debugPrint(
        '[REVIEW] wrong-card set filtered by sessions '
        '(${out.length} items from ${all.length} attempts, kept=$kept)',
      );
    }
    return out;
  }

  /// 直近の誤答タイムスタンプ（key=stableId or Q::キー）
  Future<Map<String, DateTime>> getWrongLatestAtMap({
    List<String>? onlySessionIds,
  }) async {
    DateTime? ts(dynamic e) {
      // DateTime 直／ISO文字列／epoch int に緩く対応
      try {
        final v = (e as dynamic).answeredAt;
        if (v is DateTime) return v;
        if (v is String) return DateTime.tryParse(v);
        if (v is int) {
          return DateTime.fromMillisecondsSinceEpoch(
            v > 2000000000 ? v : v * 1000,
          );
        }
      } catch (_) {}
      try {
        final v = (e as dynamic).timestamp;
        if (v is DateTime) return v;
        if (v is String) return DateTime.tryParse(v);
        if (v is int) {
          return DateTime.fromMillisecondsSinceEpoch(
            v > 2000000000 ? v : v * 1000,
          );
        }
      } catch (_) {}
      try {
        final v = (e as dynamic).createdAt;
        if (v is DateTime) return v;
        if (v is String) return DateTime.tryParse(v);
        if (v is int) {
          return DateTime.fromMillisecondsSinceEpoch(
            v > 2000000000 ? v : v * 1000,
          );
        }
      } catch (_) {}
      return null;
    }

    final all = await _loadAll();
    final map = <String, DateTime>{};

    for (final e in all) {
      if (onlySessionIds != null && !onlySessionIds.contains(e.sessionId)) {
        continue;
      }
      if (!e.isCorrect) {
        final key = _keyFromAttempt(e);
        if (key.isEmpty) continue;
        final t = ts(e);
        if (t == null) continue;
        final cur = map[key];
        if (cur == null || t.isAfter(cur)) {
          map[key] = t;
        }
      }
    }
    debugPrint(
      '[REVIEW] latestWrongAt filtered=${onlySessionIds?.length ?? 0} -> ${map.length}',
    );
    return map;
  }

  /// 誤答頻度マップを返す: { key: wrongCount }（key は stableId 優先）
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

    if (onlySessionIds != null) {
      try {
        debugPrint('[REVIEW] attempts filtered by sessions: $kept/$total');
      } catch (_) {}
    }
    return map;
  }

  /// key生成ヘルパ（stableId優先・無ければ質問文を Q:: でフォールバック）
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
    final q = e.question.trim();
    if (q.isEmpty) return '';
    return _questionKey(q);
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
          // ★ インポート時も stableId を補完
          if ((a.stableId == null || a.stableId!.isEmpty) &&
              (a.question.trim().isNotEmpty)) {
            a = a.copyWith(stableId: _questionKey(a.question));
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
      if (!ok) throw StateError('Failed to persist scores');
    } catch (e) {
      AppLog.w('[AttemptStore] saveScores failed: $e');
      rethrow;
    }
  }

  /// 成績サマリを追加/更新（sessionId で upsert）
  Future<void> addScore(ScoreRecord record, {int? retention}) async {
    final all = await loadScores();

    // ★ 同じ sessionId があれば置き換え（なければ追加）
    // Old records may lack sessionId. Never overwrite an unrelated history
    // record just because both session IDs are null.
    final idx = (record.sessionId?.isNotEmpty ?? false)
        ? all.indexWhere((e) => e.sessionId == record.sessionId)
        : all.indexWhere((e) => e.id == record.id);
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
        .map((e) => e.question.trim())
        .where((q) => q.isNotEmpty)
        .toList();
  }

  //===========================================================================
  // 🔽 復習モード対応API（見直し／復習テスト 共通）
  // ===========================================================================

  /// 【見直しモード用】
  /// 重複を除いた「誤答カードの stableId 一覧」を返す。
  /// ※ type='review_test' など指定でスコープ絞り込みも可能。
  Future<List<String>> getWrongStableIdsUniqueScoped({
    List<String>? onlySessionIds,
    String? type, // 'unit' | 'mixed' | 'review_test' | null
  }) async {
    final all = await _loadAll();
    final out = <String>{};
    for (final e in all) {
      // typeで絞り込み（指定がなければ全体）
      if (type != null && e.sessionType != type) continue;
      if (onlySessionIds != null && !onlySessionIds.contains(e.sessionId)) {
        continue;
      }

      if (!e.isCorrect) {
        final key = _keyFromAttempt(e);
        if (key.isNotEmpty) out.add(key);
      }
    }
    AppLog.d(
      '[REVIEW] getWrongStableIdsUnique -> ${out.length} items',
    ); // ★追加ログ
    return out.toList();
  }

  /// 【復習テスト用】誤答の出現頻度 (stableId → 回数) を ScoreScope で算出
  Future<Map<String, int>> getWrongFrequencyMapScoped(ScoreScope scope) async {
    final attempts = await _loadAll();
    final out = <String, int>{};

    final DateTime? from = scope.from;
    final DateTime? to = scope.to;
    final Set<String>? types =
        scope.sessionTypes; // 例: {'unit','mixed'} or null

    // ---- ScoreRecord 用：型ゆれを吸収して開始時刻をとる（startedAt/createdAt/timestamp など）
    DateTime? scoreTime(dynamic s) {
      DateTime? p(v) {
        if (v == null) return null;
        if (v is DateTime) return v;
        if (v is String) return DateTime.tryParse(v); // ← ここが => ではなく return
        if (v is num) {
          final n = v.toInt();
          final ms = n > 2000000000 ? n : n * 1000; // 秒/ミリ秒両対応
          return DateTime.fromMillisecondsSinceEpoch(ms);
        }
        return null;
      }

      try {
        final t = p((s as dynamic).startedAt);
        if (t != null) return t;
      } catch (_) {}
      try {
        final t = p((s as dynamic).startedAtMs);
        if (t != null) return t;
      } catch (_) {}
      try {
        final t = p((s as dynamic).createdAt);
        if (t != null) return t;
      } catch (_) {}
      try {
        final t = p((s as dynamic).timestamp);
        if (t != null) return t;
      } catch (_) {}
      return null;
    }

    // ---- ScoreRecord 用：type を緩く取得（type/sessionType/mode のいずれか）
    String? scoreType(dynamic s) {
      try {
        final v = (s as dynamic).type as String?;
        if (v != null && v.isNotEmpty) return v;
      } catch (_) {}
      try {
        final v = (s as dynamic).sessionType as String?;
        if (v != null && v.isNotEmpty) return v;
      } catch (_) {}
      try {
        final v = (s as dynamic).mode as String?;
        if (v != null && v.isNotEmpty) return v;
      } catch (_) {}
      return null;
    }

    // ① ScoreRecord を同条件でフィルタし、対象 sessionId 集合を作る
    final scores = await loadScores();
    final scopedSessionIds = scores
        .where((s) {
          final st = scoreTime(s);
          final ty = scoreType(s);
          // 取れない情報は「通す」（除外しない）→ sessions=0 を回避
          final okType = (types == null || types.isEmpty) ||
              (ty == null) ||
              types.contains(ty);
          final okFrom = (from == null) || (st == null) || st.isAfter(from);
          final okTo = (to == null) || (st == null) || st.isBefore(to);
          return okType && okFrom && okTo;
        })
        .map((s) {
          try {
            return (s as dynamic).sessionId as String;
          } catch (_) {
            return '';
          }
        })
        .where((id) => id.isNotEmpty)
        .toSet();

    // ★追加：スコープ（セッション集合）が空なら、見直しモードと同様に 0 件を返す
    if (scopedSessionIds.isEmpty) {
      debugPrint('[REVIEW] getWrongFrequencyMapScoped -> 0 items (sessions=0)');
      return <String, int>{};
    }

    // ---- Attempt 用：回答時刻を緩く取得（answeredAt/createdAt/timestamp など）
    DateTime? attemptTime(dynamic e) {
      DateTime? p(v) {
        if (v == null) return null;
        if (v is DateTime) return v;
        if (v is String) return DateTime.tryParse(v);
        if (v is num) {
          final n = v.toInt();
          final ms = n > 2000000000 ? n : n * 1000;
          return DateTime.fromMillisecondsSinceEpoch(ms);
        }
        return null;
      }

      try {
        final t = p((e as dynamic).answeredAt);
        if (t != null) return t;
      } catch (_) {}
      try {
        final t = p((e as dynamic).answeredAtMs);
        if (t != null) return t;
      } catch (_) {}
      try {
        final t = p((e as dynamic).createdAt);
        if (t != null) return t;
      } catch (_) {}
      try {
        final t = p((e as dynamic).timestamp);
        if (t != null) return t;
      } catch (_) {}
      return null;
    }

    // ② セッション限定 + 期間チェック + 誤答のみ集計
    for (final e in attempts) {
      // 見直しと同じ “sessionIds 限定” に揃える（集合が作れた場合のみ適用）
      if (scopedSessionIds.isNotEmpty &&
          !scopedSessionIds.contains(e.sessionId)) {
        continue;
      }

      // Attempt 側 sessionType は null を許容（null で除外しない）
      if (types != null && types.isNotEmpty) {
        final st = e.sessionType;
        if (st != null && !types.contains(st)) continue;
      }

      final t = attemptTime(e);
      if (from != null && t != null && t.isBefore(from)) continue;
      if (to != null && t != null && t.isAfter(to)) continue;

      if (!e.isCorrect) {
        final key = _keyFromAttempt(e);
        if (key.isEmpty) continue;
        out.update(key, (v) => v + 1, ifAbsent: () => 1);
      }
    }

    debugPrint(
      '[REVIEW] getWrongFrequencyMapScoped -> ${out.length} items (sessions=${scopedSessionIds.length})',
    );
    return out;
  }

  /// 【メタ情報】誤答回数＋最新誤答時刻＋最新正誤を返す
  /// → 見直しモードで「並び替え／フィルタ」に利用予定
  Future<
      Map<
          String,
          ({
            int wrongCount,
            DateTime? latestWrongAt,
            bool? latestWasCorrect
          })>> buildReviewMeta(
      {List<String>? onlySessionIds, String? type}) async {
    final all = await _loadAll();
    final map = <String,
        ({int wrongCount, DateTime? latestWrongAt, bool? latestWasCorrect})>{};

    for (final e in all) {
      if (type != null && e.sessionType != type) continue;
      if (onlySessionIds != null && !onlySessionIds.contains(e.sessionId)) {
        continue;
      }

      final sid = _keyFromAttempt(e);
      if (sid.isEmpty) continue;

      final cur = map[sid];
      var wrong = cur?.wrongCount ?? 0;
      DateTime? latest = cur?.latestWrongAt;
      bool? lastCorrect = cur?.latestWasCorrect;

      if (!e.isCorrect) {
        wrong += 1;
        final t = e.createdAt ?? e.answeredAt ?? e.timestamp;
        if ((latest == null || t.isAfter(latest))) latest = t;
      }
      // 最新正誤
      final t = e.createdAt ?? e.answeredAt ?? e.timestamp;
      if ((latest == null || t.isAfter(latest))) {
        lastCorrect = e.isCorrect;
      }

      map[sid] = (
        wrongCount: wrong,
        latestWrongAt: latest,
        latestWasCorrect: lastCorrect,
      );
    }

    return map;
  }
}
