import 'dart:convert';

/// タグ別集計（正解/不正解と正答率）
class TagStat {
  final int correct;
  final int wrong;

  const TagStat({required this.correct, required this.wrong});

  factory TagStat.fromJson(Map<String, dynamic> json) => TagStat(
        correct: (json['correct'] ?? 0) as int,
        wrong: (json['wrong'] ?? 0) as int,
      );

  Map<String, dynamic> toJson() => {'correct': correct, 'wrong': wrong};

  double get accuracy =>
      (correct + wrong) == 0 ? 0 : correct / (correct + wrong);
}

/// 成績レコード（一覧で使う1件のスコア）
/// - v1 互換: tags/selectedUnitIds/ durationSec は存在しない可能性あり
/// - v2 拡張: sessionId を追加（AttemptHistory にジャンプ可能）
class ScoreRecord {
  final String id;
  final String deckId;
  final String deckTitle;
  final int score;
  final int total;
  final int? durationSec; // 秒（null: 旧データ互換）
  final int timestamp; // epoch ms
  final Map<String, TagStat>? tags; // null: タグ集計なし
  final List<String>? selectedUnitIds;
  final String? sessionId; // ★追加：この成績のセッションID（AttemptHistoryへジャンプ）

  const ScoreRecord({
    required this.id,
    required this.deckId,
    required this.deckTitle,
    required this.score,
    required this.total,
    required this.timestamp,
    this.durationSec,
    this.tags,
    this.selectedUnitIds,
    this.sessionId,
  });

  /// JSONから生成（旧データ互換）
  factory ScoreRecord.fromJson(Map<String, dynamic> json) {
    final tagsJson = json['tags'];
    Map<String, TagStat>? parsedTags;
    if (tagsJson is Map<String, dynamic>) {
      parsedTags = tagsJson.map((k, v) =>
          MapEntry(k, TagStat.fromJson(Map<String, dynamic>.from(v))));
    }

    return ScoreRecord(
      id: json['id'] as String,
      deckId: json['deckId'] as String? ?? 'unknown',
      deckTitle: json['deckTitle'] as String? ?? '',
      score: (json['score'] ?? 0) as int,
      total: (json['total'] ?? 0) as int,
      durationSec: (json['durationSec'] as num?)?.toInt(),
      timestamp:
          (json['timestamp'] ?? DateTime.now().millisecondsSinceEpoch) as int,
      tags: parsedTags,
      selectedUnitIds: (json['selectedUnitIds'] as List?)
          ?.map((e) => e.toString())
          .toList(),
      sessionId: json['sessionId'] as String?, // ★旧データは null でOK
    );
  }

  /// JSONへ変換（null項目は省略）
  Map<String, dynamic> toJson() => {
        'id': id,
        'deckId': deckId,
        'deckTitle': deckTitle,
        'score': score,
        'total': total,
        'durationSec': durationSec,
        'timestamp': timestamp,
        if (tags != null) 'tags': tags!.map((k, v) => MapEntry(k, v.toJson())),
        if (selectedUnitIds != null) 'selectedUnitIds': selectedUnitIds,
        if (sessionId != null && sessionId!.isNotEmpty) 'sessionId': sessionId,
      };

  /// 便利: 精度（0.0〜1.0）
  double get accuracy => total == 0 ? 0 : score / total;

  /// 一覧のエンコード/デコード
  static List<ScoreRecord> decodeList(String raw) {
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => ScoreRecord.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    }

  static String encodeList(List<ScoreRecord> items) {
    return jsonEncode(items.map((e) => e.toJson()).toList());
  }

  /// 必要に応じて値を差し替えるコピー
  ScoreRecord copyWith({
    String? id,
    String? deckId,
    String? deckTitle,
    int? score,
    int? total,
    int? durationSec,
    int? timestamp,
    Map<String, TagStat>? tags,
    List<String>? selectedUnitIds,
    String? sessionId,
  }) {
    return ScoreRecord(
      id: id ?? this.id,
      deckId: deckId ?? this.deckId,
      deckTitle: deckTitle ?? this.deckTitle,
      score: score ?? this.score,
      total: total ?? this.total,
      durationSec: durationSec ?? this.durationSec,
      timestamp: timestamp ?? this.timestamp,
      tags: tags ?? this.tags,
      selectedUnitIds: selectedUnitIds ?? this.selectedUnitIds,
      sessionId: sessionId ?? this.sessionId,
    );
  }
}
