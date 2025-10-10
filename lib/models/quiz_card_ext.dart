// lib/models/quiz_card_ext.dart
import 'card.dart';

extension QuizCardChoiceOrderExt on QuizCard {
  /// 与えられた order で choices を並べ替えた新インスタンスを返す
  QuizCard withChoiceOrder(List<int> order) {
    assert(order.length == choices.length);
    final newChoices = [for (final i in order) choices[i]];
    final oldAnswerIndex = answerIndex; // 0-based
    final newAnswerIndex = order.indexOf(oldAnswerIndex);
    return copyWith(choices: newChoices, answerIndex: newAnswerIndex);
  }
}
