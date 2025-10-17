// lib/services/review_test_builder.dart
import 'dart:math';
import '../models/card.dart';
import '../models/review_scope.dart'; // ScoreScope
import 'attempt_store.dart';
import 'deck_loader.dart';
import '../utils/logger.dart';

/// 復習テスト: 誤答頻度の高い順に上位 N 件を出題（ScoreScope × stableId）
class ReviewTestBuilder {
  final AttemptStore attempts;
  final DeckLoader loader;
  final Random rng;

  ReviewTestBuilder({
    required this.attempts,
    required this.loader,
    Random? rng,
  }) : rng = rng ?? Random();

  /// 安定IDベースで上位N件のカードを返す（正式版）
  Future<List<QuizCard>> buildTopNWithScope({
    required int topN,
    required ScoreScope scope,
  }) async {
    // 1) スコープ内の誤答頻度マップ（stableId → 回数）
    final freq = await attempts.getWrongFrequencyMapScoped(scope);
    if (freq.isEmpty) {
      AppLog.w('[REVIEW] empty freq (scope=$scope)');
      return [];
    }

    // 2) タイブレーク用：最新誤答時刻（stableId → DateTime）
    final latest = await attempts.getLatestWrongAtScoped(scope);

    // 3) 頻度降順 → 同率は最新誤答が新しい順で安定ソート
    final ordered = freq.entries.toList()
      ..sort((a, b) {
        // 回数（多い順）
        final cmp = b.value.compareTo(a.value);
        if (cmp != 0) return cmp;
        // 最新誤答（新しい順）
        final ta = latest[a.key];
        final tb = latest[b.key];
        if (ta == null && tb == null) return 0;
        if (ta == null) return 1;
        if (tb == null) return -1;
        return tb.compareTo(ta);
      });

    final ids = ordered.take(topN).map((e) => e.key).toList();

    // 4) stableId → QuizCard へ写像（欠落はスキップしログ）
    final result = <QuizCard>[];
    for (final id in ids) {
      final c = loader.getByStableId(id);
      if (c != null) {
        result.add(c);
      } else {
        AppLog.w('[REVIEW/MAP] missing card for stableId=$id');
      }
    }

    // 5) 出題順は毎回ランダム（選定ロジックは維持）
    result.shuffle(rng);

    AppLog.i('[REVIEW] review_test built=${result.length}/$topN '
        '(candidates=${freq.length}, scope=$scope)');
    return result;
  }
}
