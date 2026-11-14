import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_quiz_app/features/exam/exam_access.dart';
import 'package:health_quiz_app/features/exam/exam_question.dart';
import 'package:health_quiz_app/services/deck_loader.dart';
import 'package:health_quiz_app/services/purchase_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'free, purchased, and revoked access are checked on saved questions',
      (tester) async {
    final loader = await tester.runAsync(DeckLoader.instance);
    final deck = (await loader!.loadAll()).first;
    final free =
        ExamQuestion.fromLegacy(deck.cards.firstWhere((c) => !c.isPremium));
    final premium =
        ExamQuestion.fromLegacy(deck.cards.firstWhere((c) => c.isPremium));
    await ensureExamAccess([free]);
    await expectLater(ensureExamAccess([premium]), throwsStateError);
    await PurchaseStore.addOwnedDecks({deck.id.toLowerCase()});
    await ensureExamAccess([premium]);
    SharedPreferences.setMockInitialValues({});
    await expectLater(ensureExamAccess([premium]), throwsStateError);
  });
}
