import '../../services/deck_loader.dart';
import '../../services/gate.dart';
import 'exam_question.dart';

Future<void> ensureExamAccess(Iterable<ExamQuestion> questions) async {
  final premium = questions.where((q) => q.isPremium).toList();
  if (premium.isEmpty) return;
  await DeckLoader.instance();
  final checked = <String, bool>{};
  for (final q in premium) {
    final deckId = DeckLoader.deckIdOfUnit(q.unitId);
    final allowed = checked[deckId] ??=
        deckId.isNotEmpty && await Gate.canAccessDeck(deckId);
    if (!allowed) {
      throw StateError('購入状態を確認できない問題が含まれています。購入を復元してから再開してください。');
    }
  }
}
