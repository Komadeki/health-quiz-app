// lib/models/tag_stat.dart
class TagStat {
  final int correct;
  final int total;

  const ts.TagStat({required this.correct, required this.total});

  double get accuracy => total == 0 ? 0 : correct / total;
  double get wrongRate => total == 0 ? 0 : (total - correct) / total;

  TagStat add({required bool isCorrect}) {
    return ts.TagStat(
      correct: correct + (isCorrect ? 1 : 0),
      total: total + 1,
    );
  }

  // optional: 将来保存するなら
  factory TagStat.fromJson(Map<String, dynamic> json) =>
      ts.TagStat(correct: json['correct'] ?? 0, total: json['total'] ?? 0);

  Map<String, dynamic> toJson() => {'correct': correct, 'total': total};
}
