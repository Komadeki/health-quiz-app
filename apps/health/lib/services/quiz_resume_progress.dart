import '../models/attempt_entry.dart';
import '../models/card.dart';
import '../models/quiz_session.dart';

/// Restore only trusted completed responses; never silently zero earlier marks.
class QuizResumeProgress {
  const QuizResumeProgress({
    required this.correctCount,
    required this.tagCorrect,
    required this.tagWrong,
    required this.answers,
  });

  final int correctCount;
  final Map<String, int> tagCorrect;
  final Map<String, int> tagWrong;
  final Map<String, dynamic> answers;
}

QuizResumeProgress restoreQuizProgress({
  required QuizSession session,
  required List<QuizCard> sequence,
  required List<String> stableOrder,
  required List<AttemptEntry> attempts,
}) {
  if (sequence.length != stableOrder.length ||
      session.currentIndex < 0 ||
      session.currentIndex > sequence.length) {
    throw const FormatException('Invalid quiz resume position or sequence');
  }

  final tagsCorrect = <String, int>{};
  final tagsWrong = <String, int>{};
  final recovered = <String, dynamic>{};
  var correct = 0;

  for (var i = 0; i < session.currentIndex; i++) {
    final card = sequence[i];
    final stableId = stableOrder[i];
    final saved = session.answers?[stableId];
    bool? wasCorrect;
    int? selectedIndex;

    if (saved is Map) {
      final rawIndex = saved['selectedIndex'];
      final rawCorrect = saved['isCorrect'];
      if (rawIndex is int) {
        if (rawIndex < 0 || rawIndex >= card.choices.length) {
          throw FormatException('Invalid saved answer for question ${i + 1}');
        }
        selectedIndex = rawIndex;
        wasCorrect = rawIndex == card.answerIndex;
        if (rawCorrect is bool && rawCorrect != wasCorrect) {
          throw FormatException('Inconsistent answer for question ${i + 1}');
        }
      } else if (rawCorrect is bool) {
        // Recovered legacy attempt without reliable choice-order metadata.
        wasCorrect = rawCorrect;
      }
    }

    if (wasCorrect == null) {
      // bySession returns newest attempts first. Match position and ID.
      for (final attempt in attempts) {
        if (attempt.sessionId != session.sessionId ||
            attempt.questionNumber != i + 1) {
          continue;
        }
        final sameId = attempt.stableId == stableId;
        final legacyQuestionKey = attempt.stableId?.startsWith('Q::') == true &&
            attempt.question == card.question;
        if (!sameId && !legacyQuestionKey) continue;
        wasCorrect = attempt.isCorrect;
        // Current published app writes one-based indexes.
        if (session.choiceOrders?[stableId] != null &&
            attempt.correctIndex == card.answerIndex + 1 &&
            attempt.selectedIndex > 0 &&
            attempt.selectedIndex <= card.choices.length) {
          selectedIndex = attempt.selectedIndex - 1;
        }
        break;
      }
    }

    if (wasCorrect == null) {
      throw FormatException(
        'No trusted answer for previously completed question ${i + 1}',
      );
    }

    if (wasCorrect) correct++;
    for (final tag in card.tags) {
      final map = wasCorrect ? tagsCorrect : tagsWrong;
      map.update(tag, (n) => n + 1, ifAbsent: () => 1);
    }
    recovered[stableId] = {
      if (selectedIndex != null) 'selectedIndex': selectedIndex,
      'isCorrect': wasCorrect,
    };
  }

  return QuizResumeProgress(
    correctCount: correct,
    tagCorrect: Map.unmodifiable(tagsCorrect),
    tagWrong: Map.unmodifiable(tagsWrong),
    answers: Map.unmodifiable(recovered),
  );
}
