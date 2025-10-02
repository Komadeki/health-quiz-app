import 'card.dart';

class Unit {
  final String id;
  final String title;
  final List<QuizCard> cards;

  Unit({
    required this.id,
    required this.title,
    required this.cards,
  });

  factory Unit.fromJson(Map<String, dynamic> json) {
    return Unit(
      id: json['id'] as String,
      title: json['title'] as String,
      cards: (json['cards'] as List)
          .map((c) => QuizCard.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}
