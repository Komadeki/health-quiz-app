// lib/services/scores_store.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class QuizResult {
  final String deckId; // 'mixed' のときはミックス練習
  final int total; // 出題数
  final int correct; // 正解数
  final DateTime timestamp; // 保存時刻
  final String mode; // 'single' or 'mixed'

  QuizResult({
    required this.deckId,
    required this.total,
    required this.correct,
    required this.timestamp,
    required this.mode,
  });

  Map<String, dynamic> toJson() => {
    'deckId': deckId,
    'total': total,
    'correct': correct,
    'timestamp': timestamp.toIso8601String(),
    'mode': mode,
  };

  factory QuizResult.fromJson(Map<String, dynamic> json) => QuizResult(
    deckId: json['deckId'] as String,
    total: json['total'] as int,
    correct: json['correct'] as int,
    timestamp: DateTime.parse(json['timestamp'] as String),
    mode: (json['mode'] as String?) ?? 'single',
  );
}

class ScoresStore {
  static const _key = 'scores.v1';

  Future<List<QuizResult>> loadAll() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = (jsonDecode(raw) as List)
        .cast<Map<String, dynamic>>()
        .map(QuizResult.fromJson)
        .toList();
    return list;
  }

  Future<void> add(QuizResult result) async {
    final sp = await SharedPreferences.getInstance();
    final list = await loadAll();
    // 先頭に追加（新しい順）
    list.insert(0, result);
    // 必要なら上限を設ける（例：最新200件だけ保持）
    if (list.length > 200) {
      list.removeRange(200, list.length);
    }
    final jsonList = list.map((e) => e.toJson()).toList();
    await sp.setString(_key, jsonEncode(jsonList));
  }

  Future<void> clearAll() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }
}
