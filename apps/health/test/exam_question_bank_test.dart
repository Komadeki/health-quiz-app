import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/features/exam/exam_question.dart';

void main() {
  test('all authored term-exam questions are valid, unique and in known units',
      () {
    final data = jsonDecode(
      File('assets/exam/exam_questions_v1.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    expect(data['schemaVersion'], 2);
    final entries = data['questions'] as List<dynamic>;
    expect(entries.every((q) => (q['sourceUrls'] as List).isNotEmpty), isTrue);
    final all = entries
        .map((x) => ExamQuestion.fromJson(Map<String, dynamic>.from(x as Map)))
        .toList(growable: false);

    final knownUnits = <String>{};
    for (final file in Directory('assets/decks')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))) {
      final deck = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final unit in deck['units'] as List<dynamic>) {
        knownUnits.add((unit as Map<String, dynamic>)['id'] as String);
      }
    }

    expect(all, hasLength(40));
    expect(all.map((q) => q.id).toSet(), hasLength(all.length));
    expect(all.every((q) => knownUnits.contains(q.unitId)), isTrue);
    expect(all.every((q) => q.type != ExamQuestionType.choice), isTrue);
    expect(all.where((q) => q.id.startsWith('h1-')), hasLength(15));
    expect(all.where((q) => q.id.startsWith('h2-')), hasLength(25));
    expect(all.where((q) => q.type == ExamQuestionType.fill), hasLength(15));
    expect(
        all.where((q) => q.type == ExamQuestionType.trueFalse), hasLength(15));
    final shortAnswers =
        all.where((q) => q.type == ExamQuestionType.shortAnswer);
    expect(shortAnswers, hasLength(10));
    expect(shortAnswers.every((q) => !q.question.contains('（　）')), isTrue);
    expect(all.every((q) => q.explanation.trim().isNotEmpty), isTrue);
    expect(all.map((q) => q.question.trim()).toSet(), hasLength(40));
    for (final q in all) {
      expect(q.isCorrect(q.answer), isTrue, reason: q.id);
      for (final alias in q.acceptedAnswers) {
        expect(q.isCorrect(alias), isTrue, reason: '${q.id}: $alias');
      }
      expect(q.isCorrect(''), isFalse, reason: q.id);
      expect(q.isCorrect('不明な解答'), isFalse, reason: q.id);
      if (q.type == ExamQuestionType.shortAnswer) {
        expect(q.isCorrect('${q.answer}ではない'), isFalse, reason: q.id);
        expect(q.isCorrect(q.answer.substring(0, 1)), isFalse, reason: q.id);
        expect(ExamQuestion.fromJson(q.toJson()).type,
            ExamQuestionType.shortAnswer);
      }
    }
  });
}
