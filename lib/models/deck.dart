import 'card.dart';

class Deck {
  final String id;
  final String title;
  final List<QuizCard> cards;

  Deck({
    required this.id,
    required this.title,
    required this.cards,
  });

  factory Deck.fromJson(Map<String, dynamic> json) {
    return Deck(
      id: json['id'] as String,
      title: json['title'] as String,
      cards: (json['cards'] as List)
          .map((c) => QuizCard.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}