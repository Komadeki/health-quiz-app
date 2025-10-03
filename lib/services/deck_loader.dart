import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/deck.dart';

class DeckLoader {
  static const deckFiles = [
    'assets/decks/deck_life.json',
    'assets/decks/deck_disease.json',
    'assets/decks/deck_nutrition.json',
    // ここに増やしていく: 'assets/decks/deck_disease.json', ...
  ];

  Future<List<Deck>> loadAll() async {
    final List<Deck> decks = [];
    for (final path in deckFiles) {
      final raw = await rootBundle.loadString(path);
      decks.add(Deck.fromJson(jsonDecode(raw)));
    }
    return decks;
  }
}
