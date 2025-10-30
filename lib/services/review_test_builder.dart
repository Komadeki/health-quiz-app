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

  ReviewTestBuilder({
    required this.attempts,
    required this.loader,
    Random? rng,
  }) : rng = rng ?? Random();

  /// スコープに基づいて誤答頻度上位N件を抽出し、QuizCardリストを返す
  Future<List<QuizCard>> buildTopNWithScope({
    required int topN,
    required ScoreScope scope,
  }) async {
    // ① 誤答頻度マップを取得（Map<stableId, count>）
    final Map<String, int> freqMap = await attempts.getWrongFrequencyMapScoped(scope);

    if (freqMap.isEmpty) {
      AppLog.w('[REVIEW] empty frequency map (scope=$scope)');
      return [];
    }

    // ② 頻度降順で並べ替えて上位N件を抽出
    final entries = freqMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final stableIds = entries.take(topN).map((e) => e.key).toList();

    // ③ stableId → QuizCard へ変換（存在しない場合はスキップ）
    final result = <QuizCard>[];
    for (final stableId in stableIds) {
      final card = loader.getByStableId(stableId);
      if (card != null) {
        result.add(card);
      } else {
        AppLog.w('[REVIEW/MAP] missing card for stableId=$stableId');
      }
    }

    // ④ シャッフルして返す
    result.shuffle(rng);
    AppLog.i('[REVIEW] built review_test cards=${result.length} topN=$topN scope=$scope');

    return result;
  }
}
