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
    expect(pack, hasLength(552));
    expect(pack.map((q) => q.id).toSet(), hasLength(552));
    expect(pack.map((q) => q.question).toSet(), hasLength(552));
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
      expect(qs, hasLength(12), reason: unit);
      expect(qs.map((q) => q.type).toSet(), ExamQuestionType.values.toSet());
    }
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
