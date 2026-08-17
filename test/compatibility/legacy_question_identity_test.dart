import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/models/card.dart';
import 'package:health_quiz_app/quiz_app_definition.dart';
import 'package:health_quiz_app/utils/stable_id.dart';

void main() {
  final fixture = jsonDecode(
    File(
      'test/fixtures/legacy_question_identity_v1.json',
    ).readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (fixture['cases'] as List<dynamic>)
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList();

  test('LegacyHashQuestionIdentityV1 matches frozen representative hashes', () {
    expect(currentQuizApp.preferExplicitStableIds, isFalse);

    for (final item in cases) {
      final card = QuizCard(
        stableId: 'EXPLICIT-ID-MUST-NOT-WIN-FOR-HEALTH',
        question: item['question'] as String,
        choices: List<String>.from(item['choices'] as List),
        answerIndex: item['answerIndex'] as int,
      );
      final expected = item['expectedStableId'] as String;

      expect(
        legacyStableIdForOriginal(card),
        expected,
        reason: item['name'] as String,
      );
      expect(stableIdForOriginal(card), expected);
      expect(stableIdFromStrings(card.question, card.choices), expected);
    }
  });

  test('legacy identity changes with question, choice content, or order', () {
    final item = cases.first;
    final question = item['question'] as String;
    final choices = List<String>.from(item['choices'] as List);
    final expected = item['expectedStableId'] as String;

    expect(stableIdFromStrings('$question（変更）', choices), isNot(expected));

    final changedChoice = [...choices]..[0] = '${choices[0]}（変更）';
    expect(stableIdFromStrings(question, changedChoice), isNot(expected));

    final reorderedChoices = [...choices.reversed];
    expect(stableIdFromStrings(question, reorderedChoices), isNot(expected));
  });

  test('legacy identity collapses whitespace but preserves content order', () {
    final whitespaceCase = cases.singleWhere(
      (item) => item['name'] == 'whitespace normalization',
    );
    final expected = whitespaceCase['expectedStableId'] as String;

    expect(
      stableIdFromStrings(
        '空白 を 正規化',
        const ['選択肢 A', '選択肢 B', '選択肢 C'],
      ),
      expected,
    );
  });
}
