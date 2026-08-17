import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/models/card.dart';

void main() {
  final rawCards = (jsonDecode(
    File('test/fixtures/legacy_quiz_cards.json').readAsStringSync(),
  ) as List<dynamic>)
      .map((item) => Map<String, dynamic>.from(item as Map));

  test('pre-Phase 1 QuizCard JSON decodes without qualification metadata', () {
    const qualificationFields = {
      'stableId',
      'sourceTitle',
      'sourceSection',
      'difficulty',
      'importance',
      'revisionTag',
    };

    final cards = <QuizCard>[];
    for (final raw in rawCards) {
      expect(raw.keys.where(qualificationFields.contains), isEmpty);
      cards.add(QuizCard.fromJson(raw));
    }

    expect(cards, hasLength(2));
    expect(cards.first.choices, hasLength(3));
    expect(cards.first.tags, ['感染症', '予防']);
    expect(cards.first.unitId, 'unit_legacy_three_choices');
    expect(cards.last.choices, hasLength(4));
    expect(cards.last.tags, ['生活習慣', '運動']);
    expect(cards.last.answerIndex, 2);
    expect(cards.last.isPremium, isTrue);

    for (final card in cards) {
      expect(card.stableId, isNull);
      expect(card.questionVersion, isNull);
      expect(card.sourceId, isNull);
      expect(card.sourceTitle, isNull);
      expect(card.sourceSection, isNull);
      expect(card.sourceVersion, isNull);
      expect(card.difficulty, isNull);
      expect(card.importance, isNull);
      expect(card.revisionTag, isNull);
    }
  });
}
