import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/models/deck.dart';
import 'package:health_quiz_app/quiz_app_definition.dart';

void main() {
  final fixture = jsonDecode(
    File(
      'test/fixtures/health_question_bank_contract.json',
    ).readAsStringSync(),
  ) as Map<String, dynamic>;

  test('health question bank satisfies its frozen structural contract', () {
    final deckSpecs = (fixture['decks'] as List<dynamic>)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final loadedDeckIds = <String>[];
    var totalQuestions = 0;

    for (final spec in deckSpecs) {
      final path = spec['asset'] as String;
      final raw = jsonDecode(File(path).readAsStringSync());
      final deck = Deck.fromJson(Map<String, dynamic>.from(raw as Map));
      final baseline = spec['baselineQuestionCount'] as int;
      final minimum = spec['minimumQuestionCount'] as int;

      expect(deck.id, spec['id'], reason: path);
      expect(deck.title.trim(), isNotEmpty, reason: path);
      expect(deck.units, isNotEmpty, reason: path);
      expect(minimum, baseline * 9 ~/ 10, reason: path);
      expect(
        deck.cards.length,
        greaterThanOrEqualTo(minimum),
        reason: '$path fell below its 90% frozen baseline',
      );

      loadedDeckIds.add(deck.id.toLowerCase());
      totalQuestions += deck.cards.length;

      for (final unit in deck.units) {
        expect(unit.id.trim(), isNotEmpty, reason: path);
        expect(unit.title.trim(), isNotEmpty, reason: '${deck.id}/${unit.id}');
        expect(unit.cards, isNotEmpty, reason: '${deck.id}/${unit.id}');

        for (final card in unit.cards) {
          expect(
            card.question.trim(),
            isNotEmpty,
            reason: '${deck.id}/${unit.id}',
          );
          expect(
            card.choices.length,
            greaterThanOrEqualTo(2),
            reason: card.question,
          );
          expect(
              card.answerIndex, inInclusiveRange(0, card.choices.length - 1));
        }
      }
    }

    expect(loadedDeckIds, currentQuizApp.deckIds);
    final baselineTotal = fixture['baselineQuestionCount'] as int;
    final minimumTotal = fixture['minimumQuestionCount'] as int;
    expect(minimumTotal, baselineTotal * 9 ~/ 10);
    expect(
      totalQuestions,
      greaterThanOrEqualTo(minimumTotal),
      reason: 'question bank fell below 90% of the 1,380-question baseline',
    );
  });
}
