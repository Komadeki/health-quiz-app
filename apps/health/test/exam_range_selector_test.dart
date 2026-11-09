import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/features/exam/exam_question.dart';
import 'package:health_quiz_app/features/exam/exam_range_selector.dart';
import 'package:health_quiz_app/models/card.dart';
import 'package:health_quiz_app/utils/stable_id.dart';

ExamQuestion sample(String id, String unit, ExamQuestionType type) =>
    ExamQuestion(
      id: id,
      unitId: unit,
      question: '問題 $id',
      type: type,
      answer: type == ExamQuestionType.choice ? '0'
          : type == ExamQuestionType.trueFalse ? '○' : '肝臓',
      choices: type == ExamQuestionType.choice
          ? const ['正解', '不正解'] : const [],
      explanation: '解説 $id',
    );

void main() {
  const selector = ExamRangeSelector();

  test('only explicitly selected units are eligible', () {
    final bank = [
      for (var i = 0; i < 10; i++) sample('a$i', 'unit_a', ExamQuestionType.choice),
      for (var i = 0; i < 10; i++) sample('b$i', 'unit_b', ExamQuestionType.choice),
    ];
    final selected = selector.select(
      accessibleQuestions: bank,
      selectedUnitIds: {'unit_b'},
      questionCount: 7,
      random: Random(2),
    );
    expect(selected, hasLength(7));
    expect(selected.every((q) => q.unitId == 'unit_b'), isTrue);
  });

  test('question IDs and identical prompts do not repeat', () {
    final bank = [
      sample('1', 'unit_a', ExamQuestionType.choice),
      sample('1', 'unit_a', ExamQuestionType.choice),
      sample('2', 'unit_a', ExamQuestionType.choice)
          .copyWithQuestionForTest('問題 1'),
      sample('3', 'unit_a', ExamQuestionType.fill),
    ];
    final selected = selector.select(
      accessibleQuestions: bank,
      selectedUnitIds: {'unit_a'},
      questionCount: 30,
      random: Random(1),
    );
    expect(selected, hasLength(2));
    expect(selected.map((q) => q.id).toSet(), hasLength(2));
  });

  test('formats and units are balanced when supply permits', () {
    final bank = [
      for (final type in ExamQuestionType.values)
        for (final unit in ['unit_a', 'unit_b'])
          for (var i = 0; i < 10; i++)
            sample('$type-$unit-$i', unit, type),
    ];
    final selected = selector.select(
      accessibleQuestions: bank,
      selectedUnitIds: {'unit_a', 'unit_b'},
      questionCount: 18,
      random: Random(11),
    );
    expect(selected, hasLength(18));
    for (final type in ExamQuestionType.values) {
      expect(selected.where((q) => q.type == type), hasLength(6));
    }
    expect(selected.where((q) => q.unitId == 'unit_a'), hasLength(9));
    expect(selected.where((q) => q.unitId == 'unit_b'), hasLength(9));
  });

  test('shortage never repeats questions or samples outside scope', () {
    final bank = [
      sample('a', 'unit_a', ExamQuestionType.fill),
      sample('b', 'unit_a', ExamQuestionType.choice),
      sample('c', 'unit_b', ExamQuestionType.trueFalse),
    ];
    final selected = selector.select(
      accessibleQuestions: bank,
      selectedUnitIds: {'unit_a'},
      questionCount: 20,
      random: Random(4),
    );
    expect(selected, hasLength(2));
    expect(selector.availableCount(
      accessibleQuestions: bank,
      selectedUnitIds: {'unit_a'},
    ), 2);
  });

  test('fill accepts only documented aliases and typographic normalization', () {
    const q = ExamQuestion(
      id: 'f1', unitId: 'health', question: '筋肉をつくる栄養素は？',
      type: ExamQuestionType.fill, answer: 'たんぱく質',
      acceptedAnswers: ['タンパク質'], explanation: '体の材料となる。',
    );
    expect(q.isCorrect(' タンパク質 '), isTrue);
    expect(q.isCorrect('たんぱく 質'), isTrue);
    expect(q.isCorrect('ビタミン'), isFalse);
    expect(q.isCorrect(''), isFalse);
  });

  test('true/false and choice use exact scoring', () {
    final tf = sample('tf', 'unit_a', ExamQuestionType.trueFalse);
    final choice = sample('choice', 'unit_a', ExamQuestionType.choice);
    expect(tf.isCorrect('○'), isTrue);
    expect(tf.isCorrect('×'), isFalse);
    expect(choice.isCorrect('0'), isTrue);
    expect(choice.isCorrect('1'), isFalse);
  });

  test('legacy question identity stays stable', () {
    const card = QuizCard(
      question: 'テスト問題',
      choices: ['正解', '不正解', 'その他', '上記以外'],
      answerIndex: 0,
      unitId: 'unit_a',
      isPremium: true,
    );
    final exam = ExamQuestion.fromLegacy(card);
    expect(exam.id, stableIdForOriginal(card));
    expect(exam.isPremium, isTrue);
    expect(exam.isCorrect('0'), isTrue);
    expect(exam.isCorrect('1'), isFalse);
  });
}

/// Construct another distinct record with a duplicate prompt for testing.
extension on ExamQuestion {
  ExamQuestion copyWithQuestionForTest(String prompt) => ExamQuestion(
    id: id,
    unitId: unitId,
    question: prompt,
    type: type,
    answer: answer,
    explanation: explanation,
    choices: choices,
  );
}
