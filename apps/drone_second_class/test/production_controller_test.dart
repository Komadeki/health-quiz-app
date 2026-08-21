import 'dart:io';

import 'package:drone_second_class/generated/app_manifest.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'production_test_support.dart';

void main() {
  test('Reference Product preserves the released 100Q/20Q/four-unit bank', () {
    final bank = loadProductionBank();

    expect(bank.bankRevision, 'drone-second-class-v1-release-2026-08-20');
    expect(bank.examProfileVersion, 'drone-second-class-v1');
    expect(bank.cards, hasLength(100));
    expect(bank.cardsById, hasLength(100));
    expect(bank.units, hasLength(4));
    expect(bank.cards.where((card) => !card.isPremium), hasLength(20));
    for (final unit in bank.units) {
      expect(unit.cards.where((card) => !card.isPremium), hasLength(5));
    }
  });

  test('Drone composition uses shared Factory architecture only', () {
    final source = File(
      'lib/production/production_app.dart',
    ).readAsStringSync();
    final productionFiles = Directory('lib/production')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();

    expect(productionFiles, hasLength(1));
    expect(source, contains('QualificationProductionBootstrap'));
    expect(source, isNot(contains('DroneProductionController')));
    expect(File('lib/main_validation.dart').existsSync(), isTrue);
    expect(
      File('lib/main.dart').readAsStringSync(),
      isNot(contains('main_validation.dart')),
    );
  });

  test(
    'free/premium access, learning event and resume use the shared runtime',
    () async {
      final free = createProductionController();
      await free.initialize();
      expect(free.accessibleQuestionCount, 20);
      expect(await free.startUnit('drone_rules'), isTrue);
      final questionId = free.activeSession!.currentQuestionId;
      expect(await free.commitAnswer(free.currentCard!.answerIndex), isTrue);
      expect(free.events.single.questionId, questionId);
      expect(free.events.single.bankRevision, free.bank!.bankRevision);
      expect(
        free.progress!.overall.completedQuestions,
        0,
        reason: 'Progress updates after the completed session boundary.',
      );
      free.dispose();

      final cache = MemoryEntitlementCache()
        ..value = EntitlementSnapshot(
          ownedProductIds: {
            GeneratedAppManifest.productCatalog.fullUnlockProductId!,
          },
        );
      final unlocked = createProductionController(entitlementCache: cache);
      await unlocked.initialize();
      expect(unlocked.accessibleQuestionCount, 100);
      expect(await unlocked.startMockExam(), isTrue);
      expect(unlocked.activeSession!.questionIds, hasLength(100));
      unlocked.dispose();
    },
  );
}
