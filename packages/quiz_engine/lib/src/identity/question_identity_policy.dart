import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../models/card.dart';

/// Selects the stable identity contract for a quiz card.
abstract interface class QuestionIdentityPolicy {
  const QuestionIdentityPolicy();

  String stableIdFor(QuizCard card);
}

/// The published health-app identity contract.
///
/// The normalized question and the original choice order are joined exactly as
/// before Phase 2C. Changing this algorithm would orphan saved health sessions,
/// attempts, review state, and scores.
final class LegacyHashQuestionIdentityV1 implements QuestionIdentityPolicy {
  const LegacyHashQuestionIdentityV1();

  static String _normalize(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ').trim();

  String stableIdFromStrings(String question, List<String> choices) {
    final normalizedQuestion = _normalize(question);
    final normalizedChoices = choices.map(_normalize).join('|');
    final bytes = utf8.encode('$normalizedQuestion\n$normalizedChoices');
    return crypto.md5.convert(bytes).toString();
  }

  @override
  String stableIdFor(QuizCard card) =>
      stableIdFromStrings(card.question, card.choices);
}

/// Identity contract for qualification banks with permanent authored IDs.
///
/// This policy intentionally never falls back to a content hash.
final class ExplicitQuestionIdentityV1 implements QuestionIdentityPolicy {
  const ExplicitQuestionIdentityV1();

  @override
  String stableIdFor(QuizCard card) {
    final stableId = card.stableId?.trim();
    if (stableId == null || stableId.isEmpty) {
      throw const QuestionIdentityException(
        'ExplicitQuestionIdentityV1 requires a non-empty stableId.',
      );
    }
    return stableId;
  }
}

final class QuestionIdentityException extends FormatException {
  const QuestionIdentityException(super.message);
}
