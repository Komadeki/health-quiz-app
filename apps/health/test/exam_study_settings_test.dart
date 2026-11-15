import 'dart:convert';
// Retain Flutter 3.47 compatibility while Flutter 3.50 deprecates this import.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/features/exam/exam_setup_screen.dart';
import 'package:health_quiz_app/features/exam/exam_study_settings.dart';
import 'package:health_quiz_app/services/deck_loader.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _FailingSettings extends InMemorySharedPreferencesStore {
  _FailingSettings() : super.withData({});
  @override
  Future<bool> setValue(String type, String key, Object value) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('settings round trip preserves purchases and checkpoints', () async {
    SharedPreferences.setMockInitialValues({
      'proUpgrade': true,
      'examPack.owned.v1': true,
      'fivePack.selectedDecks': ['deck_m02'],
      'health_term_exam_active_v1': 'unfinished'
    });
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    await ExamStudySettings(
            unitIds: {'u2', 'u1'}, questionCount: 30, usePack: true)
        .save();
    expect((await ExamStudySettings.load())!.matches({'u1', 'u2'}, 30, true),
        isTrue);
    for (final entry in before.entries) {
      expect(prefs.get(entry.key), entry.value);
    }
  });
  test('clearing only removes the study setting', () async {
    SharedPreferences.setMockInitialValues(
        {'proUpgrade': true, 'health_term_exam_active_v1': 'keep'});
    await ExamStudySettings(unitIds: {'u'}, questionCount: 10, usePack: true)
        .save();
    await ExamStudySettings.clear();
    expect(await ExamStudySettings.load(), isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('proUpgrade'), isTrue);
    expect(prefs.getString('health_term_exam_active_v1'), 'keep');
  });
  test('malformed and future settings are preserved', () async {
    for (final raw in [
      '{bad',
      jsonEncode({'schemaVersion': 9}),
      jsonEncode({
        'schemaVersion': 1,
        'unitIds': ['u'],
        'questionCount': 12,
        'usePack': true
      })
    ]) {
      SharedPreferences.setMockInitialValues(
          {ExamStudySettings.storageKey: raw});
      await expectLater(
          ExamStudySettings.load(), throwsA(isA<FormatException>()));
      expect(
          (await SharedPreferences.getInstance())
              .getString(ExamStudySettings.storageKey),
          raw);
    }
  });
  test('failed writes are reported and never grant purchases', () async {
    SharedPreferencesStorePlatform.instance = _FailingSettings();
    await expectLater(
        ExamStudySettings(unitIds: {'u'}, questionCount: 10, usePack: true)
            .save(),
        throwsStateError);
    expect(
        (await SharedPreferences.getInstance())
            .containsKey('examPack.owned.v1'),
        isFalse);
  });
  for (final packOwned in [true, false]) {
    testWidgets('restore checks live purchase rights: $packOwned',
        (tester) async {
      final saved = jsonEncode({
        'schemaVersion': 1,
        'unitIds': ['unit_health_concepts', 'removed_unit'],
        'questionCount': 20,
        'usePack': true
      });
      SharedPreferences.setMockInitialValues({
        ExamStudySettings.storageKey: saved,
        'examPack.owned.v1': packOwned
      });
      final loader = await tester.runAsync(DeckLoader.instance);
      final decks = await loader!.loadAll();
      await tester.runAsync(() async {
        await tester
            .pumpWidget(MaterialApp(home: ExamSetupScreen(decks: decks)));
        for (var i = 0;
            i < 200 &&
                find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
            i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          await tester.pump();
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('1 / 6単元を選択'), findsOneWidget);
      if (packOwned) {
        expect(
            tester
                .widget<SwitchListTile>(
                    find.widgetWithText(SwitchListTile, '追加パックから出題'))
                .value,
            isTrue);
        expect(find.text('この範囲から16問を自動作成'), findsOneWidget);
      } else {
        expect(find.textContaining('購入状態を復元してください。'), findsOneWidget);
        expect(find.widgetWithText(SwitchListTile, '追加パックから出題'), findsNothing);
      }
      final chip = find.widgetWithText(ChoiceChip, '20問');
      await tester.scrollUntilVisible(chip, 250);
      expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
      expect(
          (await SharedPreferences.getInstance())
              .getString(ExamStudySettings.storageKey),
          saved);
      if (packOwned) {
        final save = find.text('この試験範囲を保存');
        await tester.ensureVisible(save);
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(
            (await ExamStudySettings.load())!
                .matches({'unit_health_concepts'}, 20, true),
            isTrue);
        expect(find.text('試験範囲を保存済み'), findsOneWidget);
        final clear = find.text('保存設定だけを解除');
        await tester.ensureVisible(clear);
        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(await ExamStudySettings.load(), isNull);
        expect(find.text('この範囲から16問を自動作成'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
