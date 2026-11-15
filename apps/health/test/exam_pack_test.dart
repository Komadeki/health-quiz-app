import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/features/exam/exam_access.dart';
import 'package:health_quiz_app/features/exam/exam_question.dart';
import 'package:health_quiz_app/features/exam/exam_range_selector.dart';
import 'package:health_quiz_app/services/exam_pack.dart';
import 'package:health_quiz_app/services/purchase_store.dart';
import 'package:quiz_engine/quiz_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class _Gateway implements PurchaseGateway {
  final completed = <String>[];
  @override
  Stream<PurchaseResult> get purchaseResults => const Stream.empty();
  @override
  Future<void> complete(PurchaseResult result) async =>
      completed.add(result.eventId);
  @override
  Future<void> purchase(String id) async {}
  @override
  Future<void> restore() async {}
  @override
  Future<ProductQueryResult> queryProducts(Set<String> ids) async =>
      ProductQueryResult(storeAvailable: true);
}

class _FailingDisk extends InMemorySharedPreferencesStore {
  _FailingDisk() : super.withData({});
  @override
  Future<bool> setValue(String type, String key, Object value) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final raw =
      (jsonDecode(File('assets/exam/exam_pack_v1.json').readAsStringSync())
          as Map)['questions'] as List;
  final pack = raw
      .map((q) => ExamQuestion.fromJson(Map<String, dynamic>.from(q as Map)))
      .toList();
  test('46 units each have all four formats and preserve rights in snapshots',
      () {
    final units = <String>{};
    for (final file in Directory('assets/decks').listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final deck = jsonDecode(file.readAsStringSync()) as Map;
      for (final unit in deck['units'] as List) {
        units.add(unit['id'] as String);
      }
    }
    expect(units, hasLength(46));
    expect(pack, hasLength(736));
    expect(pack.map((q) => q.id).toSet(), hasLength(736));
    expect(pack.map((q) => q.question).toSet(), hasLength(736));
    for (final q in pack) {
      expect(q.requiresExamPack, isTrue);
      expect(q.isPremium, isFalse);
      expect(q.isCorrect(q.answer), isTrue);
      for (final alias in q.acceptedAnswers) {
        expect(q.isCorrect(alias), isTrue);
      }
      expect(q.isCorrect('未登録の解答'), isFalse);
      expect(ExamQuestion.fromJson(q.toJson()).requiresExamPack, isTrue);
      expect(q.shuffledChoices(random: Random(1)).requiresExamPack, isTrue);
    }
    for (final file in Directory('assets/decks').listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final deck = jsonDecode(file.readAsStringSync()) as Map;
      for (final unit in deck['units'] as List) {
        final unitId = unit['id'] as String;
        final free = (unit['cards'] as List)
            .where((c) => c['isPremium'] != true)
            .map((c) {
          return ExamQuestion.fromLegacy(QuizCard.fromJson(
              {...Map<String, dynamic>.from(c as Map), 'unitId': unitId}));
        });
        final selected = const ExamRangeSelector().select(accessibleQuestions: [
          ...free,
          ...pack.where((q) => q.unitId == unitId)
        ], selectedUnitIds: {
          unitId
        }, questionCount: 10, random: Random(1));
        expect(selected, hasLength(10), reason: unitId);
        final counts = ExamQuestionType.values
            .map((t) => selected.where((q) => q.type == t).length)
            .toList();
        expect(counts.reduce(max) - counts.reduce(min), lessThanOrEqualTo(1),
            reason: unitId);
        expect(selected.map((q) => q.type).toSet(),
            ExamQuestionType.values.toSet(),
            reason: unitId);
      }
    }
    for (final unit in units) {
      final qs = pack.where((q) => q.unitId == unit).toList();
      expect(qs, hasLength(16), reason: unit);
      expect(qs.map((q) => q.type).toSet(), ExamQuestionType.values.toSet());
      for (final type in ExamQuestionType.values) {
        expect(qs.where((q) => q.type == type), hasLength(4), reason: unit);
      }
      final full = const ExamRangeSelector().select(
        accessibleQuestions: qs,
        selectedUnitIds: {unit},
        questionCount: 20,
        random: Random(2),
      );
      expect(full, hasLength(16), reason: unit);
      for (final type in ExamQuestionType.values) {
        expect(full.where((q) => q.type == type), hasLength(4), reason: unit);
      }
    }
  });
  test('reviewed answer constraints and practical spelling variants', () {
    ExamQuestion question(String id) => pack.singleWhere((q) => q.id == id);
    expect(question('ep1-u01-fill').isCorrect('生活の質'), isFalse);
    expect(question('ep1-u17-short_answer').isCorrect('ヒト免疫不全ウイルス'), isFalse);
    expect(question('ep1-u17-short_answer').isCorrect('ｈｉｖ'), isTrue);
    expect(question('ep1-u25-short_answer').isCorrect('自動体外式除細動器'), isFalse);
    expect(question('ep1-u06-short-3').isCorrect('ストレッチ'), isTrue);
    expect(question('ep1-u26-short_answer').isCorrect('母子手帳'), isTrue);
    expect(question('ep1-u32-fill').isCorrect('骨そしょう症'), isTrue);
    expect(question('ep2-u27-short_answer-4').isCorrect('第2次性徴'), isTrue);
    expect(question('ep1-u29-short-3').isCorrect('へその緒'), isFalse);
    expect(question('ep2-u25-true_false-4').isCorrect('×'), isTrue);
    expect(
        question('ep2-u08-choice-4')
            .choices[int.parse(question('ep2-u08-choice-4').answer)],
        '8～10時間');
  });
  test('free40 stay free and legacy products do not unlock independent pack',
      () async {
    final free = (jsonDecode(
            File('assets/exam/exam_questions_v1.json').readAsStringSync())
        as Map)['questions'] as List;
    expect(free, hasLength(40));
    for (final q in free) {
      expect(
          ExamQuestion.fromJson(Map<String, dynamic>.from(q as Map))
              .requiresExamPack,
          isFalse);
    }
    await PurchaseStore.setPro(true);
    await PurchaseStore.addOwnedDecks(
        List.generate(8, (i) => 'deck_m0${i + 1}'));
    await expectLater(ensureExamAccess(pack), throwsStateError);
    await PurchaseStore.setExamPackOwned(true);
    await ensureExamAccess(pack);
    await PurchaseStore.setExamPackOwned(false);
    await expectLater(ensureExamAccess(pack), throwsStateError);
  });
  test('pack purchase and restore preserve every existing purchase cache',
      () async {
    SharedPreferences.setMockInitialValues({
      'ownedDeckIds': ['deck_m01', 'deck_m08'],
      'fivePack.owned': true,
      'fivePack.selectedDecks': [
        'deck_m02',
        'deck_m03',
        'deck_m04',
        'deck_m05',
        'deck_m06'
      ],
      'proUpgrade': true,
    });
    final prefs = await SharedPreferences.getInstance();
    final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    final gateway = _Gateway();
    for (final status in PurchaseResultStatus.values) {
      await handleExamPackPurchase(
          PurchaseResult(
              eventId: 'preserve-$status',
              productId: examPackProductId,
              status: status,
              pendingCompletePurchase: true),
          gateway);
      for (final entry in before.entries) {
        expect(prefs.get(entry.key), entry.value,
            reason: '$status: ${entry.key}');
      }
    }
    expect(await PurchaseStore.isPro(), isTrue);
    expect(await PurchaseStore.ownedDeckIds(),
        containsAll(['deck_m01', 'deck_m08']));
    expect(await PurchaseStore.getFivePackDecks(),
        {'deck_m02', 'deck_m03', 'deck_m04', 'deck_m05', 'deck_m06'});
  });
  for (final status in PurchaseResultStatus.values) {
    test('pack $status grants rights only for purchase and restore', () async {
      final gateway = _Gateway();
      await handleExamPackPurchase(
          PurchaseResult(
              eventId: 'event',
              productId: examPackProductId,
              status: status,
              pendingCompletePurchase: true),
          gateway);
      final own = status == PurchaseResultStatus.purchased ||
          status == PurchaseResultStatus.restored;
      await (await SharedPreferences.getInstance()).reload();
      expect(await PurchaseStore.isExamPackOwned(), own);
      expect(await PurchaseStore.getPro(), isFalse);
      expect(await PurchaseStore.getOwnedDeckIds(), isEmpty);
      expect(await PurchaseStore.isFivePackOwned(), isFalse);
      expect(gateway.completed,
          status == PurchaseResultStatus.pending ? isEmpty : ['event']);
    });
  }
  test('disk failure keeps transaction unfinished and rights locked', () async {
    SharedPreferencesStorePlatform.instance = _FailingDisk();
    final gateway = _Gateway();
    await expectLater(
        handleExamPackPurchase(
            const PurchaseResult(
                eventId: 'retry',
                productId: examPackProductId,
                status: PurchaseResultStatus.restored,
                pendingCompletePurchase: true),
            gateway),
        throwsStateError);
    expect(gateway.completed, isEmpty);
    expect(await PurchaseStore.isExamPackOwned(), isFalse);
  });
}
