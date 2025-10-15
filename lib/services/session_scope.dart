// lib/services/session_scope.dart
import 'package:flutter/foundation.dart';
import '../services/attempt_store.dart';
import '../models/score_record.dart';
import '../models/attempt_entry.dart';

/// 成績（Score）をスコープの定義元として sessionId を収集するユーティリティ。
/// - days: 直近N日。nullなら期間制限なし
/// - type: 'normal' | 'mixed' | 'review_test' 等。nullなら全タイプ
///
/// 実装メモ
/// - ScoreRecord のスキーマ差異に対応するため、finishedAt/type は動的に推定。
/// - finishedAt が取れない場合、同 session の Attempt の最終回答時刻をフォールバックに使用。
/// - type が取れない場合、同 session の Attempt の type/mode/quizType/sourceType を参照。
class SessionScope {
  static Future<List<String>> collect({
    int? days,
    String? type,
  }) async {
    final attemptStore = AttemptStore();

    // 1) 成績一覧（Score）を AttemptStore 経由で取得
    final scores = await attemptStore.loadScores();

    // 期間閾値
    final since = (days == null)
        ? null
        : DateTime.now().subtract(Duration(days: days));

    // セッションごとの派生情報をキャッシュ（フォールバック時の多重I/O防止）
    final latestAttemptTimeCache = <String, DateTime?>{};
    final inferredTypeCache = <String, String?>{};

    // ScoreRecord から安全に日時を得る
    DateTime? _extractScoreFinishedAt(ScoreRecord s) {
      // DateTime 直接
      try {
        final v = (s as dynamic).finishedAt as DateTime?;
        if (v != null) return v;
      } catch (_) {}

      // ミリ秒/秒（int）
      DateTime? fromEpochInt(int? epoch, {bool millis = true}) {
        if (epoch == null) return null;
        try {
          return millis
              ? DateTime.fromMillisecondsSinceEpoch(epoch)
              : DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
        } catch (_) {
          return null;
        }
      }

      try {
        final v = (s as dynamic).finishedAtMillis as int?;
        final t = fromEpochInt(v, millis: true);
        if (t != null) return t;
      } catch (_) {}
      try {
        final v = (s as dynamic).finishedAtMs as int?;
        final t = fromEpochInt(v, millis: true);
        if (t != null) return t;
      } catch (_) {}
      try {
        final v = (s as dynamic).finishedAtSeconds as int?;
        final t = fromEpochInt(v, millis: false);
        if (t != null) return t;
      } catch (_) {}

      // 文字列ISO8601
      DateTime? fromIso(String? iso) {
        if (iso == null || iso.isEmpty) return null;
        return DateTime.tryParse(iso);
      }

      try {
        final v = (s as dynamic).finishedAtIso as String?;
        final t = fromIso(v);
        if (t != null) return t;
      } catch (_) {}
      try {
        final v = (s as dynamic).finishedAtString as String?;
        final t = fromIso(v);
        if (t != null) return t;
      } catch (_) {}

      // 代替候補フィールド（よくある名前）
      final altKeys = [
        'endedAt',
        'endAt',
        'completedAt',
        'completedAtIso',
        'timestamp',
        'createdAt',
        'updatedAt',
      ];
      for (final key in altKeys) {
        try {
          final dynamic v = (s as dynamic).toJson()[key];
          if (v is String) {
            final t = fromIso(v);
            if (t != null) return t;
          } else if (v is int) {
            final t = fromEpochInt(v, millis: v > 2000000000); // ざっくり判定
            if (t != null) return t;
          }
        } catch (_) {
          // toJsonが無い場合やキーが無い場合は無視
        }
        try {
          final dynamic v = (s as dynamic).__getattribute__(key); // 万一のダイナミック呼び出し
          if (v is DateTime) return v;
          if (v is String) {
            final t = fromIso(v);
            if (t != null) return t;
          }
          if (v is int) {
            final t = fromEpochInt(v, millis: v > 2000000000);
            if (t != null) return t;
          }
        } catch (_) {}
      }
      return null;
    }

    // ScoreRecord から安全に type を得る
    String? _extractScoreType(ScoreRecord s) {
      String? pick(dynamic v) =>
          (v is String && v.trim().isNotEmpty) ? v.trim() : null;
      try {
        final v = pick((s as dynamic).type);
        if (v != null) return v;
      } catch (_) {}
      try {
        final v = pick((s as dynamic).mode);
        if (v != null) return v;
      } catch (_) {}
      try {
        final v = pick((s as dynamic).quizType);
        if (v != null) return v;
      } catch (_) {}
      try {
        final v = pick((s as dynamic).sourceType);
        if (v != null) return v;
      } catch (_) {}
      // toJson 経由の候補
      try {
        final m = (s as dynamic).toJson() as Map<String, dynamic>;
        final cands = ['type', 'mode', 'quizType', 'sourceType'];
        for (final k in cands) {
          final v = pick(m[k]);
          if (v != null) return v;
        }
      } catch (_) {}
      return null;
    }

    // AttemptEntry 側の時刻/type 取得（フォールバック用）
    DateTime? _attemptTime(AttemptEntry e) {
      try {
        final v = (e as dynamic).answeredAt as DateTime?;
        if (v != null) return v;
      } catch (_) {}
      try {
        final v = (e as dynamic).timestamp as DateTime?;
        if (v != null) return v;
      } catch (_) {}
      try {
        final v = (e as dynamic).createdAt as DateTime?;
        if (v != null) return v;
      } catch (_) {}

      // 文字列ISO
      try {
        final s = (e as dynamic).answeredAt as String?;
        if (s != null && s.isNotEmpty) return DateTime.tryParse(s);
      } catch (_) {}
      try {
        final s = (e as dynamic).timestamp as String?;
        if (s != null && s.isNotEmpty) return DateTime.tryParse(s);
      } catch (_) {}
      try {
        final s = (e as dynamic).createdAt as String?;
        if (s != null && s.isNotEmpty) return DateTime.tryParse(s);
      } catch (_) {}
      return null;
    }

    String? _attemptType(AttemptEntry e) {
      String? pick(dynamic v) =>
          (v is String && v.trim().isNotEmpty) ? v.trim() : null;
      try {
        final v = pick((e as dynamic).type);
        if (v != null) return v;
      } catch (_) {}
      try {
        final v = pick((e as dynamic).mode);
        if (v != null) return v;
      } catch (_) {}
      try {
        final v = pick((e as dynamic).quizType);
        if (v != null) return v;
      } catch (_) {}
      try {
        final v = pick((e as dynamic).sourceType);
        if (v != null) return v;
      } catch (_) {}
      return null;
    }

    Future<DateTime?> _latestAttemptTimeOf(String sessionId) async {
      if (latestAttemptTimeCache.containsKey(sessionId)) {
        return latestAttemptTimeCache[sessionId];
      }
      final list = await attemptStore.bySession(sessionId);
      DateTime? latest;
      for (final a in list) {
        final t = _attemptTime(a);
        if (t == null) continue;
        if (latest == null || t.isAfter(latest)) latest = t;
      }
      latestAttemptTimeCache[sessionId] = latest;
      return latest;
    }

    Future<String?> _inferTypeFromAttempts(String sessionId) async {
      if (inferredTypeCache.containsKey(sessionId)) {
        return inferredTypeCache[sessionId];
      }
      final list = await attemptStore.bySession(sessionId);
      for (final a in list) {
        final ty = _attemptType(a);
        if (ty != null) {
          inferredTypeCache[sessionId] = ty;
          return ty;
        }
      }
      inferredTypeCache[sessionId] = null;
      return null;
    }

    final out = <String>{};

    // 2) Score をもとに session を選別（必要に応じて Attempt にフォールバック）
    for (final s in scores) {
      final sid = (s.sessionId ?? '').trim();
      if (sid.isEmpty) continue;

      // finishedAt を取得（無ければ Attempt 側から最終回答時刻）
      DateTime? finished = _extractScoreFinishedAt(s);
      finished ??= await _latestAttemptTimeOf(sid);
      if (since != null && (finished == null || finished.isBefore(since))) {
        continue; // 期間外
      }

      // type を取得（無ければ Attempt 側から推定）
      String? t = _extractScoreType(s);
      t ??= await _inferTypeFromAttempts(sid);
      if (type != null && t != type) {
        continue; // 指定タイプと不一致
      }

      out.add(sid);
    }

    debugPrint('[REVIEW] session scope days=$days type=$type -> '
        '${out.length} sessions (scores=${scores.length})');
    return out.toList();
  }
}
