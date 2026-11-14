// Retain Flutter 3.47 compatibility while Flutter 3.50 deprecates this import.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:health_quiz_app/data/quiz_session_local_repository.dart';
import 'package:health_quiz_app/models/quiz_session.dart';
import 'package:health_quiz_app/models/unit.dart';
import 'package:health_quiz_app/screens/quiz_screen.dart';
import 'package:health_quiz_app/screens/result_screen.dart';
import 'package:health_quiz_app/services/app_settings.dart';
import 'package:health_quiz_app/services/deck_loader.dart';
import 'package:health_quiz_app/services/score_store.dart';
import 'package:health_quiz_app/utils/stable_id.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final mode in ['normal', 'unit', 'mix', 'review_test']) {
    testWidgets('$mode preserves marks after interrupted practice', (
      tester,
    ) async {
      final loader = await tester.runAsync(DeckLoader.instance);
      final decks = await loader!.loadAll();
      final deck = decks.first;
      final cards = (mode == 'unit' ? deck.units.first.cards : deck.cards)
          .where((c) => !c.isPremium)
          .take(10)
          .toList();
      final settings = AppSettings();
      await settings.setRandomize(false);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: MaterialApp(
            navigatorKey: nav,
            home: const Scaffold(body: Text('Home')),
          ),
        ),
      );
      void open(QuizSession? saved) {
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => QuizScreen(
              deck: mode == 'normal' && saved == null
                  ? deck.copyWith(
                      units: [Unit(id: 'test', title: 'test', cards: cards)],
                    )
                  : deck,
              overrideCards: saved == null && mode != 'normal' ? cards : null,
              resumeSession: saved,
              type: mode == 'review_test' ? mode : 'normal',
            ),
          ),
        );
      }

      open(null);
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      final repo = QuizSessionLocalRepository(prefs);
      for (var i = 0; i < cards.length; i++) {
        if (i == 3) {
          final saved = (await repo.loadActive())!;
          expect(saved.currentIndex, 3);
          expect(saved.answers, hasLength(3));
          nav.currentState!.pop();
          await tester.pumpAndSettle();
          // Exercise the historical null scope/limit mixed checkpoint too.
          final restored = mode == 'mix' || mode == 'review_test'
              ? QuizSession(
                  sessionId: saved.sessionId,
                  deckId: 'mixed',
                  itemIds: saved.itemIds,
                  currentIndex: saved.currentIndex,
                  isFinished: false,
                  type: mode,
                  answers: saved.answers,
                  choiceOrders: saved.choiceOrders,
                )
              : saved;
          open(restored);
          await tester.pumpAndSettle();
        }
        final c = cards[i];
        final choice = i < cards.length - 3
            ? c.answerIndex
            : (c.answerIndex + 1) % c.choices.length;
        final target = find.text(c.choices[choice]);
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(
            FilledButton,
            i == cards.length - 1 ? '結果へ' : '次へ',
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(find.byType(ResultScreen), findsOneWidget);
      final scores = await ScoreStore.instance.loadAll();
      expect(scores, hasLength(1));
      expect(scores.single.score, cards.length - 3);
      expect(scores.single.total, cards.length);
      expect(
        scores.single.unitBreakdown!.values.reduce((a, b) => a + b),
        cards.length,
      );
      expect(await repo.loadActive(), isNull);
      expect(scores.single.sessionId, isNotEmpty);
      expect(stableIdForOriginal(cards.first), isNotEmpty);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('legacy completed checkpoint shows the recovered last mark', (
    tester,
  ) async {
    final loader = await tester.runAsync(DeckLoader.instance);
    final deck = (await loader!.loadAll()).first;
    final cards = deck.cards.where((c) => !c.isPremium).take(3).toList();
    final ids = cards.map(stableIdForOriginal).toList();
    final saved = QuizSession(
      sessionId: 'legacy-final',
      deckId: deck.id,
      itemIds: ids,
      currentIndex: 3,
      isFinished: false,
      answers: {
        for (final id in ids) id: {'isCorrect': true},
      },
    );
    final settings = AppSettings();
    await settings.setRandomize(false);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          home: QuizScreen(deck: deck, resumeSession: saved),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('正解！'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '結果へ'));
    await tester.pumpAndSettle();
    expect((await ScoreStore.instance.loadAll()).single.score, 3);
    expect(tester.takeException(), isNull);
  });
}
