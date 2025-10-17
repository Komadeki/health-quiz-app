// lib/services/session_scope.dart
import 'package:flutter/foundation.dart';
import 'score_store.dart'; // ← ScoreStore 直参照でOK
import '../services/score_store.dart';

/// 復習テスト用のスコープ定義

class SessionScope {
  /// 直近N日。nullなら全期間
  final int? days;
  const SessionScope({this.days});

  /// （互換API）旧コードから呼ばれている static collect
  static Future<List<String>> collect({int? days, String? type}) async {
    final ids = await SessionScopeCollector.collectSessionIds(SessionScope(days: days));
    return ids.toList();
  }
}

class SessionScopeCollector {
  static Future<Set<String>> collectSessionIds(SessionScope scope) async {
    final scores = await ScoreStore.instance.loadAll();
    if (scores.isEmpty) return {};

    final now = DateTime.now();
    final cutoff = scope.days == null ? null : now.subtract(Duration(days: scope.days!));

    final out = <String>{};
    for (final s in scores) {
      final sid = (s.sessionId ?? '').trim();
      if (sid.isEmpty) continue;

      // ScoreRecord.timestamp は int(ms)
      final finished = DateTime.fromMillisecondsSinceEpoch(s.timestamp);
      if (cutoff != null && finished.isBefore(cutoff)) continue;

      out.add(sid);
    }
    debugPrint('[REVIEW] session scope days=${scope.days} -> ${out.length} sessions');
    return out;
  }
}
