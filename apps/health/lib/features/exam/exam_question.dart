import 'dart:math';

import '../../models/card.dart';
import '../../utils/stable_id.dart';

enum ExamQuestionType { choice, fill, trueFalse }

/// A test question with an explicit correct answer. Legacy quiz cards remain
/// untouched; converting them into this view never changes their stable IDs.
class ExamQuestion {
  const ExamQuestion({
    required this.id,
    required this.unitId,
    required this.question,
    required this.type,
    required this.answer,
    required this.explanation,
    this.choices = const <String>[],
    this.acceptedAnswers = const <String>[],
    this.isPremium = false,
  });

  final String id;
  final String unitId;
  final String question;
  final ExamQuestionType type;
  /// For choice this is a zero-based choice index; for trueFalse, '○' or '×'.
  final String answer;
  final String explanation;
  final List<String> choices;
  final List<String> acceptedAnswers;
  final bool isPremium;

  factory ExamQuestion.fromLegacy(QuizCard card) {
    final unitId = card.unitId;
    if (unitId == null || unitId.isEmpty) {
      throw const FormatException('Legacy card is missing unitId');
    }
    if (card.answerIndex < 0 || card.answerIndex >= card.choices.length) {
      throw const FormatException('Legacy card has an invalid answer index');
    }
    return ExamQuestion(
      id: stableIdForOriginal(card),
      unitId: unitId,
      question: card.question,
      type: ExamQuestionType.choice,
      answer: card.answerIndex.toString(),
      explanation: card.explanation ?? '',
      choices: List<String>.unmodifiable(card.choices),
      isPremium: card.isPremium,
    );
  }

  factory ExamQuestion.fromJson(Map<String, dynamic> json) {
    final rawType = json['type']?.toString();
    final type = switch (rawType) {
      'choice' => ExamQuestionType.choice,
      'fill' => ExamQuestionType.fill,
      'true_false' => ExamQuestionType.trueFalse,
      _ => throw FormatException('Unknown exam question type: $rawType'),
    };
    final id = json['id']?.toString().trim() ?? '';
    final unitId = json['unitId']?.toString().trim() ?? '';
    final question = json['question']?.toString().trim() ?? '';
    final answer = json['answer']?.toString().trim() ?? '';
    final explanation = json['explanation']?.toString().trim() ?? '';
    final choices = (json['choices'] as List<dynamic>? ?? const [])
        .map((e) => e.toString()).toList(growable: false);
    final accepted = (json['acceptedAnswers'] as List<dynamic>? ?? const [])
        .map((e) => e.toString()).toList(growable: false);
    if (id.isEmpty || unitId.isEmpty || question.isEmpty ||
        answer.isEmpty || explanation.isEmpty) {
      throw FormatException('Incomplete exam question: $id');
    }
    if (type == ExamQuestionType.choice &&
        (choices.length < 2 || (int.tryParse(answer) ?? -1) < 0 ||
        int.parse(answer) >= choices.length)) {
      throw FormatException('Invalid choice question: $id');
    }
    if (type == ExamQuestionType.trueFalse &&
        answer != '○' && answer != '×') {
      throw FormatException('Invalid true/false question: $id');
    }
    return ExamQuestion(
      id: id,
      unitId: unitId,
      question: question,
      type: type,
      answer: answer,
      explanation: explanation,
      choices: List.unmodifiable(choices),
      acceptedAnswers: List.unmodifiable(accepted),
      isPremium: json['isPremium'] == true,
    );
  }

  /// Shuffle the displayed choices without changing the question identity.
  ExamQuestion shuffledChoices({Random? random}) {
    if (type != ExamQuestionType.choice) return this;
    final order = List<int>.generate(choices.length, (i) => i)
      ..shuffle(random ?? Random());
    return ExamQuestion(
      id: id,
      unitId: unitId,
      question: question,
      type: type,
      answer: order.indexOf(int.parse(answer)).toString(),
      explanation: explanation,
      choices: List.unmodifiable(order.map((i) => choices[i])),
      acceptedAnswers: acceptedAnswers,
      isPremium: isPremium,
    );
  }

  /// Exact-answer grading with explicit aliases, not unreliable fuzzy matches.
  bool isCorrect(String? response) {
    if (response == null || response.trim().isEmpty) return false;
    final value = normalizeAnswer(response);
    if (type == ExamQuestionType.choice) return value == answer;
    if (type == ExamQuestionType.trueFalse) return value == answer;
    return <String>[answer, ...acceptedAnswers]
        .any((accepted) => normalizeAnswer(accepted) == value);
  }

  String get answerLabel {
    if (type == ExamQuestionType.choice) {
      final index = int.parse(answer);
      return choices[index];
    }
    return answer;
  }

  static String normalizeAnswer(String text) {
    // Only normalize typographic variants: no semantic/fuzzy acceptance.
    final converted = text.runes.map((rune) {
      if (rune >= 0xFF10 && rune <= 0xFF19) return rune - 0xFF10 + 0x30;
      if (rune >= 0xFF21 && rune <= 0xFF3A) return rune - 0xFF21 + 0x41;
      if (rune >= 0xFF41 && rune <= 0xFF5A) return rune - 0xFF41 + 0x61;
      return rune;
    }).toList(growable: false);
    return String.fromCharCodes(converted)
        .replaceAll(RegExp(r'\s+|　+'), '')
        .toLowerCase();
  }
}
