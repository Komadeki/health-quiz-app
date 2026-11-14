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
    expect(data['schemaVersion'], 1);
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

    expect(all, hasLength(30));
    expect(all.map((q) => q.id).toSet(), hasLength(all.length));
    expect(all.every((q) => knownUnits.contains(q.unitId)), isTrue);
    expect(all.every((q) => q.type != ExamQuestionType.choice), isTrue);
    expect(all.where((q) => q.id.startsWith('h1-')), hasLength(10));
    expect(all.where((q) => q.id.startsWith('h2-')), hasLength(20));
    expect(all.every((q) => q.explanation.trim().isNotEmpty), isTrue);
    expect(all.map((q) => q.question.trim()).toSet(), hasLength(30));
    for (final q in all) {
      expect(q.isCorrect(q.answer), isTrue, reason: q.id);
      for (final alias in q.acceptedAnswers) {
        expect(q.isCorrect(alias), isTrue, reason: '${q.id}: $alias');
      }
      expect(q.isCorrect(''), isFalse, reason: q.id);
      expect(q.isCorrect('不明な解答'), isFalse, reason: q.id);
    }
  });
}
