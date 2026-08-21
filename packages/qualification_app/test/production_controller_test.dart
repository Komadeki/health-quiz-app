import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'test_support.dart';

void main() {
  late MemoryQualificationSessionStore sessionStore;
  late InMemoryLearningRepository learningRepository;
  late MemoryEntitlementCache entitlementCache;
  late FakePurchaseGateway gateway;
  late TestClock clock;

  QualificationProductionController createController({
    MemoryQualificationSessionStore? store,
    InMemoryLearningRepository? learning,
    MemoryEntitlementCache? cache,
    FakePurchaseGateway? purchaseGateway,
  }) {
    sessionStore = store ?? MemoryQualificationSessionStore();
    learningRepository = learning ?? InMemoryLearningRepository();
    entitlementCache = cache ?? MemoryEntitlementCache();
    gateway = purchaseGateway ?? FakePurchaseGateway();
    clock = TestClock();
    return QualificationProductionController(
      definition: fixtureDefinition,
      bankLoader: FixedBankLoader(loadFixtureBank()),
      sessionStore: sessionStore,
      learningRepository: learningRepository,
      purchaseGateway: gateway,
      entitlementCache: entitlementCache,
      now: clock.call,
      randomizer: const IdentityQuestionRandomizer(),
    );
  }

  test('free and unlocked access are configuration driven', () async {
    final free = createController();
    await free.initialize();
    expect(free.bank!.cards, hasLength(2));
    expect(free.accessibleQuestionCount, 1);
    expect(free.freeQuestionCount, 1);
    free.dispose();

    final unlockedCache = MemoryEntitlementCache()
      ..value = EntitlementSnapshot(
        ownedProductIds: const {'fixture_full_unlock'},
      );
    final unlocked = createController(cache: unlockedCache);
    await unlocked.initialize();
    expect(unlocked.accessibleQuestionCount, 2);
    unlocked.dispose();
  });

  test(
    'answer event, progress, completed history and retry share one runtime',
    () async {
      final controller = createController();
      await controller.initialize();
      expect(await controller.startUnit('fixture_safety'), isTrue);
      final card = controller.currentCard!;
      final incorrect = (card.answerIndex + 1) % card.choices.length;

      expect(await controller.commitAnswer(incorrect), isTrue);
      expect(await controller.commitAnswer(card.answerIndex), isFalse);
      expect(await controller.advance(), isTrue);

      expect(controller.result!.incorrectQuestionIds, ['FIXTURE-Q-000001']);
      expect(controller.history, hasLength(1));
      expect(controller.progress!.overall.completedQuestions, 1);
      expect(controller.events.single.attemptNumber, 1);
      expect(controller.events.single.questionVersion, 1);
      expect(await controller.startRetry(), isTrue);
      expect(controller.activeSession!.mode, LearningModeV1.retry);
      expect(controller.activeSession!.questionIds, ['FIXTURE-Q-000001']);
      controller.dispose();
    },
  );

  test('active session saves and resumes the exact committed position',
      () async {
    final store = MemoryQualificationSessionStore();
    final learning = InMemoryLearningRepository();
    final first = createController(store: store, learning: learning);
    await first.initialize();
    await first.startUnit('fixture_safety');
    final questionId = first.activeSession!.currentQuestionId;
    final choice = first.currentCard!.answerIndex;
    await first.commitAnswer(choice);
    first.dispose();

    final resumed = createController(store: store, learning: learning);
    await resumed.initialize();
    expect(resumed.activeSession!.currentQuestionId, questionId);
    expect(resumed.currentResponse, choice);
    await resumed.resume();
    expect(resumed.view, QualificationProductionView.quiz);
    resumed.dispose();
  });

  test(
    'answer commit reconciles one event after a crash before session save',
    () async {
      final store = FaultingSessionStore();
      final learning = InMemoryLearningRepository();
      final first = QualificationProductionController(
        definition: fixtureDefinition,
        bankLoader: FixedBankLoader(loadFixtureBank()),
        sessionStore: store,
        learningRepository: learning,
        purchaseGateway: FakePurchaseGateway(),
        entitlementCache: MemoryEntitlementCache(),
        now: TestClock().call,
        randomizer: const IdentityQuestionRandomizer(),
      );
      await first.initialize();
      await first.startUnit('fixture_safety');
      final choice = first.currentCard!.answerIndex;
      store.failNextSave = true;

      await expectLater(first.commitAnswer(choice), throwsStateError);
      expect(await learning.loadAllEvents(), hasLength(1));
      expect((await learning.loadAllEvents()).single.attemptNumber, 1);
      expect(store.value!.committedResponses, isEmpty);
      first.dispose();

      final resumed = QualificationProductionController(
        definition: fixtureDefinition,
        bankLoader: FixedBankLoader(loadFixtureBank()),
        sessionStore: store,
        learningRepository: learning,
        purchaseGateway: FakePurchaseGateway(),
        entitlementCache: MemoryEntitlementCache(),
        now: TestClock().call,
        randomizer: const IdentityQuestionRandomizer(),
      );
      await resumed.initialize();
      expect(await resumed.commitAnswer(choice), isTrue);
      expect(await learning.loadAllEvents(), hasLength(1));
      expect((await learning.loadAllEvents()).single.attemptNumber, 1);
      expect(resumed.currentResponse, choice);
      resumed.dispose();
    },
  );

  test('answer reconciliation rejects a conflicting choice', () async {
    final store = FaultingSessionStore();
    final learning = InMemoryLearningRepository();
    final first = QualificationProductionController(
      definition: fixtureDefinition,
      bankLoader: FixedBankLoader(loadFixtureBank()),
      sessionStore: store,
      learningRepository: learning,
      purchaseGateway: FakePurchaseGateway(),
      entitlementCache: MemoryEntitlementCache(),
      now: TestClock().call,
      randomizer: const IdentityQuestionRandomizer(),
    );
    await first.initialize();
    await first.startUnit('fixture_safety');
    final committedChoice = first.currentCard!.answerIndex;
    store.failNextSave = true;
    await expectLater(first.commitAnswer(committedChoice), throwsStateError);
    first.dispose();

    final resumed = QualificationProductionController(
      definition: fixtureDefinition,
      bankLoader: FixedBankLoader(loadFixtureBank()),
      sessionStore: store,
      learningRepository: learning,
      purchaseGateway: FakePurchaseGateway(),
      entitlementCache: MemoryEntitlementCache(),
      now: TestClock().call,
      randomizer: const IdentityQuestionRandomizer(),
    );
    await resumed.initialize();
    final conflictingChoice =
        (committedChoice + 1) % resumed.currentCard!.choices.length;
    await expectLater(
      resumed.commitAnswer(conflictingChoice),
      throwsStateError,
    );
    expect(await learning.loadAllEvents(), hasLength(1));
    expect(store.value!.committedResponses, isEmpty);
    resumed.dispose();
  });

  test(
    'session completion reconciles history after a crash before clear',
    () async {
      final store = FaultingSessionStore();
      final learning = InMemoryLearningRepository();
      final first = QualificationProductionController(
        definition: fixtureDefinition,
        bankLoader: FixedBankLoader(loadFixtureBank()),
        sessionStore: store,
        learningRepository: learning,
        purchaseGateway: FakePurchaseGateway(),
        entitlementCache: MemoryEntitlementCache(),
        now: TestClock().call,
        randomizer: const IdentityQuestionRandomizer(),
      );
      await first.initialize();
      await first.startUnit('fixture_safety');
      await first.commitAnswer(first.currentCard!.answerIndex);
      store.failNextClear = true;

      await expectLater(first.advance(), throwsStateError);
      expect(await learning.loadSessionHistory(), hasLength(1));
      expect(store.value, isNotNull);
      first.dispose();

      final resumed = QualificationProductionController(
        definition: fixtureDefinition,
        bankLoader: FixedBankLoader(loadFixtureBank()),
        sessionStore: store,
        learningRepository: learning,
        purchaseGateway: FakePurchaseGateway(),
        entitlementCache: MemoryEntitlementCache(),
        now: TestClock().call,
        randomizer: const IdentityQuestionRandomizer(),
      );
      await resumed.initialize();
      expect(resumed.fatalError, isNull);
      expect(resumed.activeSession, isNull);
      expect(store.value, isNull);
      expect(await learning.loadSessionHistory(), hasLength(1));
      expect(resumed.result, isNotNull);
      resumed.dispose();
    },
  );

  test('session completion fails closed for conflicting persisted history',
      () async {
    final store = FaultingSessionStore();
    final learning = InMemoryLearningRepository();
    final first = QualificationProductionController(
      definition: fixtureDefinition,
      bankLoader: FixedBankLoader(loadFixtureBank()),
      sessionStore: store,
      learningRepository: learning,
      purchaseGateway: FakePurchaseGateway(),
      entitlementCache: MemoryEntitlementCache(),
      now: TestClock().call,
      randomizer: const IdentityQuestionRandomizer(),
    );
    await first.initialize();
    await first.startUnit('fixture_safety');
    await first.commitAnswer(first.currentCard!.answerIndex);
    final session = store.value!;
    await learning.recordSessionHistory(
      SessionHistoryV1(
        appKey: session.appKey,
        sessionId: session.sessionId,
        mode: session.mode,
        questionIds: session.questionIds,
        correctCount: 0,
        completedAt: DateTime.utc(2026, 1, 2),
        unitId: session.unitId,
      ),
    );
    first.dispose();

    final resumed = QualificationProductionController(
      definition: fixtureDefinition,
      bankLoader: FixedBankLoader(loadFixtureBank()),
      sessionStore: store,
      learningRepository: learning,
      purchaseGateway: FakePurchaseGateway(),
      entitlementCache: MemoryEntitlementCache(),
      now: TestClock().call,
      randomizer: const IdentityQuestionRandomizer(),
    );
    await resumed.initialize();
    expect(resumed.fatalError, contains('Conflicting session completion'));
    expect(store.value, isNotNull);
    expect(await learning.loadSessionHistory(), hasLength(1));
    resumed.dispose();
  });

  test(
    'unanswered and incorrect use durable committed history semantics',
    () async {
      final controller = createController();
      await controller.initialize();
      await controller.startUnit('fixture_safety');
      final firstCard = controller.currentCard!;
      await controller.commitAnswer((firstCard.answerIndex + 1) % 3);
      await controller.advance();
      controller.returnHome();

      expect(await controller.startIncorrect(), isTrue);
      expect(controller.activeSession!.questionIds, ['FIXTURE-Q-000001']);
      await controller.commitAnswer(controller.currentCard!.answerIndex);
      await controller.advance();
      controller.returnHome();
      expect(await controller.startIncorrect(), isFalse);

      expect(await controller.startUnanswered(), isFalse);
      controller.dispose();
    },
  );

  test(
    'mock exam freezes sequence, scores sections, and preserves history',
    () async {
      final cache = MemoryEntitlementCache()
        ..value = EntitlementSnapshot(
          ownedProductIds: const {'fixture_full_unlock'},
        );
      final controller = createController(cache: cache);
      await controller.initialize();

      expect(await controller.startMockExam(), isTrue);
      expect(controller.activeSession!.questionIds, hasLength(2));
      expect(controller.activeSession!.examProfileVersion, 'fixture-exam-v1');
      while (controller.activeSession != null) {
        await controller.commitAnswer(controller.currentCard!.answerIndex);
        await controller.advance();
      }

      expect(controller.result!.mockExamResult!.correctCount, 2);
      expect(controller.result!.mockExamResult!.passed, isNull);
      expect(await learningRepository.loadMockExamHistory(), hasLength(1));
      controller.dispose();
    },
  );

  test('configured mock-exam time limit closes an expired session', () async {
    final timedDefinition = QualificationAppDefinition(
      appKey: fixtureDefinition.appKey,
      displayName: fixtureDefinition.displayName,
      publisher: fixtureDefinition.publisher,
      brandName: fixtureDefinition.brandName,
      legalese: fixtureDefinition.legalese,
      urls: fixtureDefinition.urls,
      questionBankAsset: fixtureDefinition.questionBankAsset,
      questionIdentityPolicy: fixtureDefinition.questionIdentityPolicy,
      monetization: fixtureDefinition.monetization,
      examProfile: MockExamProfileV1(
        profileVersion: 'fixture-exam-v1',
        questionCount: 2,
        timeLimitMinutes: 1,
        allocations: const [
          ExamUnitAllocationV1(
            unitId: 'fixture_operations',
            questionCount: 1,
          ),
          ExamUnitAllocationV1(
            unitId: 'fixture_safety',
            questionCount: 1,
          ),
        ],
        overallPassPercent: null,
        sectionPassRules: const [],
        shuffleQuestions: false,
      ),
      branding: fixtureDefinition.branding,
      learningProduct: fixtureDefinition.learningProduct,
    );
    final timedClock = TestClock();
    final learning = InMemoryLearningRepository();
    final cache = MemoryEntitlementCache()
      ..value = EntitlementSnapshot(
        ownedProductIds: const {'fixture_full_unlock'},
      );
    final controller = QualificationProductionController(
      definition: timedDefinition,
      bankLoader: FixedBankLoader(loadFixtureBank()),
      sessionStore: MemoryQualificationSessionStore(),
      learningRepository: learning,
      purchaseGateway: FakePurchaseGateway(),
      entitlementCache: cache,
      now: timedClock.call,
      randomizer: const IdentityQuestionRandomizer(),
    );
    await controller.initialize();
    await controller.startMockExam();
    timedClock.value = timedClock.value.add(const Duration(minutes: 2));

    expect(await controller.commitAnswer(0), isFalse);
    expect(controller.view, QualificationProductionView.result);
    expect(controller.events, isEmpty);
    expect((await learning.loadMockExamHistory()).single.correctCount, 0);
    controller.dispose();
  });

  test(
    'incompatible bank revision and entitlement sessions fail closed',
    () async {
      final store = MemoryQualificationSessionStore()
        ..value = QualificationSessionV1(
          sessionId: 'old-session',
          appKey: 'qualification_fixture',
          bankRevision: 'old-bank',
          mode: LearningModeV1.unitPractice,
          questionIds: const ['FIXTURE-Q-000001'],
          currentIndex: 0,
          committedResponses: const {},
          startedAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );
      final controller = createController(store: store);
      await controller.initialize();

      expect(controller.activeSession, isNull);
      expect(store.value, isNull);
      expect(controller.fatalError, isNull);
      controller.dispose();
    },
  );

  test('purchase and restore use shared coordinator and cache', () async {
    final purchase = createController();
    await purchase.initialize();
    await purchase.purchaseFullUnlock();
    await settleEvents();
    expect(purchase.hasFullUnlock, isTrue);
    expect(gateway.purchased, ['fixture_full_unlock']);
    purchase.dispose();

    final restore = createController();
    await restore.initialize();
    await restore.restorePurchases();
    await settleEvents();
    expect(restore.hasFullUnlock, isTrue);
    restore.dispose();
  });
}
