// lib/models/quiz_session.dart
import 'dart:convert';

class QuizSession {
  // === 必須（従来） ===
  final String sessionId;         // セッション一意ID
  final String deckId;            // 'mixed' or 通常デッキID
  final List<String> itemIds;     // 出題順に対応する安定ID列（唯一の復元根拠）
  final int currentIndex;         // 次に解く位置（0-based）
  final bool isFinished;          // 終了フラグ

  // === ★追加 ===
  /// 'normal' | 'mix' | 'review_test' など
  final String type;

  // === 追加（後方互換のため null許容） ===
  final String? unitId;                   // 単一ユニット用に残すなら
  final List<String>? selectedUnitIds;    // ミックスの母集団特定用
  final int? limit;                       // ミックスでの出題数
  final Map<String, List<int>>? choiceOrders; // 安定ID -> 選択肢並び順（0-based）

  // === 既存オプション：null耐性を強化 ===
  final Map<String, dynamic>? answers;    // 任意（未使用なら null/空でもOK）
  final DateTime? updatedAt;              // null可（欠損時も落ちない）

  const QuizSession({
    required this.sessionId,
    required this.deckId,
    required this.itemIds,
    required this.currentIndex,
    required this.isFinished,
    this.type = 'normal', // ★後方互換の既定値
    this.unitId,
    this.selectedUnitIds,
    this.limit,
    this.choiceOrders,
    this.answers,
    this.updatedAt,
  });

  QuizSession copyWith({
    String? sessionId,
    String? deckId,
    List<String>? itemIds,
    int? currentIndex,
    bool? isFinished,
    String? type, // ★追加
    String? unitId,
    List<String>? selectedUnitIds,
    int? limit,
    Map<String, List<int>>? choiceOrders,
    Map<String, dynamic>? answers,
    DateTime? updatedAt,
  }) {
    return QuizSession(
      sessionId: sessionId ?? this.sessionId,
      deckId: deckId ?? this.deckId,
      itemIds: itemIds ?? this.itemIds,
      currentIndex: currentIndex ?? this.currentIndex,
      isFinished: isFinished ?? this.isFinished,
      type: type ?? this.type, // ★追加
      unitId: unitId ?? this.unitId,
      selectedUnitIds: selectedUnitIds ?? this.selectedUnitIds,
      limit: limit ?? this.limit,
      choiceOrders: choiceOrders ?? this.choiceOrders,
      answers: answers ?? this.answers,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory QuizSession.fromJson(Map<String, dynamic> json) {
    // helper
    List<String>? asStringList(dynamic v) {
      if (v is List) {
        return v.where((e) => e != null).map((e) => e.toString()).toList();
      }
      return null;
    }

    Map<String, List<int>>? asChoiceOrders(dynamic v) {
      if (v is Map) {
        final out = <String, List<int>>{};
        v.forEach((key, value) {
          if (value is List) {
            out[key.toString()] =
                value.where((e) => e != null).map((e) => (e as num).toInt()).toList();
          }
        });
        return out;
      }
      return null;
    }

    DateTime? asDate(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }

    final itemIds = asStringList(json['itemIds']) ?? const <String>[];

    return QuizSession(
      sessionId: (json['sessionId'] ?? '').toString(),
      deckId: (json['deckId'] ?? '').toString(),
      itemIds: itemIds,
      currentIndex: (json['currentIndex'] is num) ? (json['currentIndex'] as num).toInt() : 0,
      isFinished: (json['isFinished'] is bool) ? json['isFinished'] as bool : false,
      type: (json['type'] ?? 'normal').toString(), // ★追加：未保存データは 'normal'
      unitId: (json['unitId'] as String?)?.toString(),
      selectedUnitIds: asStringList(json['selectedUnitIds']),
      limit: (json['limit'] is num) ? (json['limit'] as num).toInt() : null,
      choiceOrders: asChoiceOrders(json['choiceOrders']),
      answers: (json['answers'] is Map<String, dynamic>) ? (json['answers'] as Map<String, dynamic>) : null,
      updatedAt: asDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'sessionId': sessionId,
      'deckId': deckId,
      'itemIds': itemIds,
      'currentIndex': currentIndex,
      'isFinished': isFinished,
      'type': type, // ★追加
      if (unitId != null) 'unitId': unitId,
      if (selectedUnitIds != null) 'selectedUnitIds': selectedUnitIds,
      if (limit != null) 'limit': limit,
      if (choiceOrders != null) 'choiceOrders': choiceOrders,
      if (answers != null) 'answers': answers,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  // ストレージ用のシリアライズ/デシリアライズ
  String encode() => jsonEncode(toJson());
  static QuizSession? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return QuizSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
