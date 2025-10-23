// lib/services/review_test_builder.dart
import 'dart:math';
import '../models/card.dart';
import '../models/review_scope.dart';
import 'attempt_store.dart';
import 'deck_loader.dart';
import '../utils/logger.dart';

/// 復習テスト: 誤答頻度の高い順に上位 N 件を出題（score-scoped × stableId）
class ReviewTestBuilder {
  final AttemptStore attempts;
  final DeckLoader loader;
  final Random rng;

  ReviewTestBuilder({required this.attempts, required this.loader, Random? rng})
    : rng = rng ?? Random();

  /// 安定IDベースで上位N件のカードを返す（正式版）
  Future<List<QuizCard>> buildTopNWithScope({
    required int topN,
    required ScoreScope scope,
  }) async {
    // ★ シグネチャ統一：scope をそのまま渡す
    final freq = await attempts.getWrongFrequencyMapScoped(scope);
    if (freq.isEmpty) {
      AppLog.w('[REVIEW] empty freq (scope=$scope)');
      return [];
    }

    // 頻度降順で上位N件の stableId を抽出
    final ordered = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final ids = ordered.take(topN).map((e) => e.key).toList();

    // stableId → QuizCard へ写像（欠落はスキップしログ）
    final result = <QuizCard>[];
    for (final id in ids) {
      final c = loader.getByStableId(id);
      if (c != null) {
        result.add(c);
      } else {
        AppLog.w('[REVIEW/MAP] missing card for stableId=$id');
      }
    }

    result.shuffle(rng);
    AppLog.i(
      '[REVIEW] review_test built=${result.length} topN=$topN scope=$scope',
    );
    return result;
  }
}
