import 'unit.dart';
import 'card.dart';

class Deck {
  final String id;
  final String title;
  final bool isPurchased;   // 単元ごとの購入フラグ
  final List<Unit> units;   // 章（Unit）を保持

  Deck({
    required this.id,
    required this.title,
    required this.isPurchased,
    required this.units,
  });

  factory Deck.fromJson(Map<String, dynamic> json) {
    return Deck(
      id: json['id'] as String,
      title: json['title'] as String,
      isPurchased: (json['isPurchased'] as bool?) ?? false,
      units: (json['units'] as List)
          .map((u) => Unit.fromJson(u as Map<String, dynamic>))
          .toList(),
    );
  }

  /// 既存画面の互換用：全Unitのカードをまとめて返す
  List<QuizCard> get cards =>
      units.expand((u) => u.cards).toList(growable: false);

  /// 将来：選択されたUnitだけを対象にカードをまとめる
  List<QuizCard> cardsFromUnits(Iterable<String> selectedUnitIds) {
    final set = selectedUnitIds.toSet();
    return units
        .where((u) => set.contains(u.id))
        .expand((u) => u.cards)
        .toList(growable: false);
  }

  // 👇 ここを追加
  Deck copyWith({
    String? id,
    String? title,
    bool? isPurchased,
    List<Unit>? units,
  }) {
    return Deck(
      id: id ?? this.id,
      title: title ?? this.title,
      isPurchased: isPurchased ?? this.isPurchased,
      units: units ?? this.units,
    );
  }
}
