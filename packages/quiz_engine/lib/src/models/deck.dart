// lib/models/deck.dart
import 'unit.dart';
import 'card.dart';

class Deck {
  final String id;
  final String title;
  final bool isPurchased; // 単元ごとの購入フラグ
  final List<Unit> units; // 章（Unit）を保持

  /// ★追加: unit_id → unit_title の辞書（ReviewCardsScreen で使用）
  final Map<String, String>? unitTitleMap;

  Deck({
    required this.id,
    required this.title,
    required this.isPurchased,
    required this.units,
    this.unitTitleMap,
  });

  factory Deck.fromJson(Map<String, dynamic> json) {
    // Unit を先に構築（Unit は id と title を持っている想定）
    final unitList = (json['units'] as List)
        .map((u) => Unit.fromJson(u as Map<String, dynamic>))
        .toList(growable: false);

    // ユニット辞書（unit_id → unit_title）
    final map = <String, String>{};
    for (final u in unitList) {
      if (u.id.isNotEmpty && u.title.isNotEmpty) {
        map[u.id] = u.title;
      }
    }

    return Deck(
      id: json['id'] as String,
      title: json['title'] as String,
      isPurchased: (json['isPurchased'] as bool?) ?? false,
      units: unitList,
      unitTitleMap: map.isEmpty ? null : map,
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

  Deck copyWith({
    String? id,
    String? title,
    bool? isPurchased,
    List<Unit>? units,
    Map<String, String>? unitTitleMap,
  }) {
    return Deck(
      id: id ?? this.id,
      title: title ?? this.title,
      isPurchased: isPurchased ?? this.isPurchased,
      units: units ?? this.units,
      unitTitleMap: unitTitleMap ?? this.unitTitleMap,
    );
  }
}
