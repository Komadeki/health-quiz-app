import 'dart:convert';

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

class ScoreRecord {
  final String id;
  final String deckId;
  final String deckTitle;
  final int score;
  final int total;
  final int? durationSec;
  final int timestamp; // epoch ms
  final Map<String, TagStat>? tags; // null: タグ集計なし（旧データ互換）
  final List<String>? selectedUnitIds;

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
  });

  factory ScoreRecord.fromJson(Map<String, dynamic> json) {
    final tagsJson = json['tags'];
    Map<String, TagStat>? parsedTags;
    if (tagsJson is Map<String, dynamic>) {
      parsedTags = tagsJson.map((k, v) => MapEntry(k, TagStat.fromJson(v)));
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
    );
  }

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
  };

  double get accuracy => total == 0 ? 0 : score / total;

  static List<ScoreRecord> decodeList(String raw) {
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => ScoreRecord.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static String encodeList(List<ScoreRecord> items) {
    return jsonEncode(items.map((e) => e.toJson()).toList());
  }
}
