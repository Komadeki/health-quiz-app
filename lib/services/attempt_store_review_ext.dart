// lib/services/attempt_store_review_ext.dart
import 'dart:async';
import '../models/review_scope.dart';
import '../utils/logger.dart';
import '../services/attempt_store.dart';
import '../services/session_scope.dart'; // ★ 追加：days/type → sessionIds 収集

extension ReviewScoped on AttemptStore {
  /// ScoreScope をセッションID集合にマッピングし、
  /// 既存 getWrongFrequencyMap(onlySessionIds: ...) を流用して freq を返す方式。
  /// AttemptEntry の生フィールドを参照しないので型差異に強い。
  Future<WrongFrequencyPayload> getWrongFrequencyMapScoped(
    ScoreScope scope,
  ) async {
    final sw = Stopwatch()..start();

    // 1) ScoreScope → SessionScope（days, type）
    final int? days = _daysFromScope(scope);
    final String? type = _typeFromScope(scope);

    // 2) セッションID収集
    final sessionIds = await SessionScope.collect(days: days, type: type);

    // 3) 既存APIで誤答頻度を取得（内部はAttemptEntryに依存済み）
    final freq = await getWrongFrequencyMap(onlySessionIds: sessionIds);

    // 4) メタ生成（attempt件数は未知なので freq ベースで最低限作る）
    final payload = WrongFrequencyPayload(
      freq: freq,
      meta: WrongFreqMeta(
        totalAttempts: 0,                  // 不明：必要なら SessionScope 側で拡張
        totalWrongAttempts: freq.values.fold(0, (a, b) => a + b),
        uniqueCards: freq.length,
        oldest: null,
        newest: null,
      ),
    );

    AppLog.i('[REVIEW/BUILD] scope=$scope '
        'sessions=${sessionIds.length} uniqStable=${payload.meta.uniqueCards} '
        'wrong=${payload.meta.totalWrongAttempts} timeMs=${sw.elapsedMilliseconds}');
    return payload;
  }

  // ===== ヘルパ =====

  int? _daysFromScope(ScoreScope s) {
    if (s.from == null) return null;
    final to = s.to ?? DateTime.now();
    final diff = to.difference(s.from!);
    return diff.inDays <= 0 ? 1 : diff.inDays;
  }

  String? _typeFromScope(ScoreScope s) {
    // 単純化：sessionTypes が単一ならその値を type として扱う
    if (s.sessionTypes == null || s.sessionTypes!.isEmpty) return null;
    if (s.sessionTypes!.length == 1) return s.sessionTypes!.first;
    // 複数タイプを同時に扱いたい場合は SessionScope.collect の拡張が必要
    return null;
  }
}
