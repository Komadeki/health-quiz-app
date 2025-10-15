// lib/services/review_test_builder.dart
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/card.dart';
import 'attempt_store.dart';
import 'deck_loader.dart';

/// 復習テスト: 誤答頻度の高い順に上位 N 件のカードを返す（不足は補充しない）
class ReviewTestBuilder {
  final AttemptStore attempts;
  final DeckLoader loader;
  final Random rng;

  /// ★追加：ScoreStoreから集めた sessionId のフィルタ
  /// これに含まれるセッションの Attempt だけを集計対象にする
  final List<String>? sessionFilter;

  ReviewTestBuilder({
    required this.attempts,
    required this.loader,
    this.sessionFilter,        // ★追加
    Random? rng,
  }) : rng = rng ?? Random();

  Future<List<QuizCard>> buildTopN({required int topN}) async {
    // 1) 誤答頻度マップ（★セッション絞り込みを適用）
    final freq = await attempts.getWrongFrequencyMap(
      onlySessionIds: sessionFilter, // ★ここが変更点
    );
    if (freq.isEmpty) {
      debugPrint('[ReviewTestBuilder] freqMap is empty (scoped=${sessionFilter?.length ?? 0})');
      return [];
    }

    // 2) 降順キー（全部回す：上位で未一致でも下位で拾うため）
    final allKeys = freq.keys.toList()
      ..sort((a, b) => (freq[b] ?? 0).compareTo(freq[a] ?? 0));

    // デバッグ: キーのタイプ内訳
    final qKeys = allKeys.where((k) => k.startsWith('Q::')).length;
    debugPrint('[ReviewTestBuilder] keys=${allKeys.length}, qKeys=$qKeys, idKeys=${allKeys.length - qKeys}');

    // 3) 全カード
    final allCards = await loader.loadAllCardsFlatten();
    if (allCards.isEmpty) {
      debugPrint('[ReviewTestBuilder] allCards is EMPTY');
      return [];
    }

    // 4) 正規化関数群（攻め）
    String normBasic(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');
    String toHalfWidth(String s) {
      final cu = s.codeUnits.map((c) {
        if (c >= 0xFF10 && c <= 0xFF19) return c - 0xFEE0; // ０-９
        if (c >= 0xFF21 && c <= 0xFF3A) return c - 0xFEE0; // Ａ-Ｚ
        if (c >= 0xFF41 && c <= 0xFF5A) return c - 0xFEE0; // ａ-ｚ
        return c;
      }).toList();
      return String.fromCharCodes(cu);
    }
    String removePunct(String s) =>
        s.replaceAll(RegExp(r'[^\p{Letter}\p{Number}\s]', unicode: true), ' ');
    String normAgg(String s) => normBasic(removePunct(toHalfWidth(s))).toLowerCase();

    // 5) 照合マップ（ID/質問文の両方）
    List<String> idsOf(QuizCard c) {
      final ids = <String>{};
      void add(dynamic v) { if (v is String && v.trim().isNotEmpty) ids.add(v.trim()); }
      try { add((c as dynamic).stableId); } catch (_) {}
      try { add((c as dynamic).cardStableId); } catch (_) {}
      try { add((c as dynamic).cardId); } catch (_) {}
      try { add((c as dynamic).id); } catch (_) {}
      try { add((c as dynamic).uuid); } catch (_) {}
      try { add((c as dynamic).key); } catch (_) {}
      return ids.toList();
    }

    final byId = <String, QuizCard>{};
    final byQBasic = <String, QuizCard>{};
    final byQAgg   = <String, QuizCard>{};

    for (final c in allCards) {
      for (final id in idsOf(c)) {
        byId[id] = c;
      }
      final q = (c.question ?? '');
      if (q.trim().isNotEmpty) {
        byQBasic[normBasic(q)] = c;
        byQAgg[normAgg(q)] = c;
      }
    }

    QuizCard? findByAny(String rawKey) {
      // 1) ID ヒット
      final idHit = byId[rawKey];
      if (idHit != null) return idHit;

      // 2) Q:: or 生質問キー → 正規化
      final q = rawKey.startsWith('Q::') ? rawKey.substring(3) : rawKey;

      // 基本正規化
      final b = byQBasic[normBasic(q)];
      if (b != null) return b;

      // 攻め正規化
      final aKey = normAgg(q);
      final a = byQAgg[aKey];
      if (a != null) return a;

      // 3) 最終保険：部分一致（攻め正規化で）
      //  探索コスト抑制のため最大600件まで走査
      for (var i = 0; i < allCards.length && i < 600; i++) {
        final c = allCards[i];
        final cq = normAgg(c.question ?? '');
        if (cq.isEmpty) continue;
        if (cq.contains(aKey) || aKey.contains(cq)) return c;
      }

      return null;
    }

    // 6) 上位から拾う（重複排除・補充なし）
    final seen = <String>{};  // 質問文の攻め正規化キーで重複排除
    final result = <QuizCard>[];
    var tried = 0, matched = 0, skipped = 0;

    for (final k in allKeys) {
      if (result.length >= topN) break;

      tried++;
      final hit = findByAny(k);
      if (hit == null) { skipped++; continue; }

      final qKey = normAgg(hit.question ?? '');
      if (qKey.isEmpty || !seen.add(qKey)) { skipped++; continue; }

      matched++;
      result.add(hit);
    }

    result.shuffle(rng);

    debugPrint('[ReviewTestBuilder] tried=$tried, matched=$matched, skipped=$skipped, '
        'returned=${result.length} / requested=$topN (scoped=${sessionFilter?.length ?? 0})');

    // ★補充なし：見つかった分だけ返す
    return result;
  }
}
