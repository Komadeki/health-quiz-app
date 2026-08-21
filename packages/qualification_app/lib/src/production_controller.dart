import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'production_bank.dart';
import 'production_persistence.dart';
import 'production_purchase.dart';

enum QualificationProductionView { home, quiz, result }

final class QualificationSessionResult {
  const QualificationSessionResult({
    required this.sessionId,
    required this.mode,
    required this.correctCount,
    required this.totalCount,
    required this.incorrectQuestionIds,
    this.mockExamResult,
  });

  final String sessionId;
  final LearningModeV1 mode;
  final int correctCount;
  final int totalCount;
  final List<String> incorrectQuestionIds;
  final MockExamResultV1? mockExamResult;
}

final class QualificationProductionController extends ChangeNotifier {
  QualificationProductionController({
    required this.definition,
    required QualificationBankLoader bankLoader,
    required QualificationSessionStore sessionStore,
    required LearningRepository learningRepository,
    required LifecyclePurchaseGateway purchaseGateway,
    required EntitlementCache entitlementCache,
    DateTime Function()? now,
    QuestionRandomizer? randomizer,
  })  : _bankLoader = bankLoader,
        _sessionStore = sessionStore,
        _learningRepository = learningRepository,
        _purchaseGateway = purchaseGateway,
        _entitlementCache = entitlementCache,
        _now = now ?? (() => DateTime.now().toUtc()),
        _randomizer = randomizer ?? DartQuestionRandomizer() {
    _coordinator = PurchaseEntitlementCoordinator(
      gateway: _purchaseGateway,
      definition: definition.monetization,
      cache: _entitlementCache,
    );
    _purchaseSubscription = _purchaseGateway.purchaseResults.listen(
      _handlePurchaseResult,
      onError: (Object error, StackTrace stackTrace) {
        purchasePending = false;
        storeMessage = '購入情報を確認できませんでした。無料問題は利用できます。';
        notifyListeners();
      },
    );
    _purchaseGateway.startListening();
  }

  final QualificationAppDefinition definition;
  final QualificationBankLoader _bankLoader;
  final QualificationSessionStore _sessionStore;
  final LearningRepository _learningRepository;
  final LifecyclePurchaseGateway _purchaseGateway;
  final EntitlementCache _entitlementCache;
  final DateTime Function() _now;
  final QuestionRandomizer _randomizer;
  late final PurchaseEntitlementCoordinator _coordinator;
  late final StreamSubscription<PurchaseResult> _purchaseSubscription;
  Timer? _mockExamDeadlineTimer;

  QualificationBank? bank;
  QualificationSessionV1? activeSession;
  QualificationSessionResult? result;
  EntitlementSnapshot entitlement = EntitlementSnapshot();
  QualificationProductionView view = QualificationProductionView.home;
  PurchaseProduct? fullUnlockProduct;
  bool storeAvailable = false;
  bool purchasePending = false;
  bool isLoading = true;
  bool _transitionBusy = false;
  String? fatalError;
  String? storeMessage;
  DateTime? _questionShownAt;
  List<LearningEventV1> events = const [];
  List<SessionHistoryV1> history = const [];
  ProgressSnapshotV1? progress;
  WeaknessSummaryV1? weakness;
  RecommendationV1? recommendation;

  bool get hasFullUnlock {
    final productId =
        definition.monetization.productCatalog.fullUnlockProductId;
    return productId != null && entitlement.ownedProductIds.contains(productId);
  }

  int get accessibleQuestionCount => bank?.cards.where(canAccess).length ?? 0;

  int get freeQuestionCount =>
      bank?.cards.where((card) => !card.isPremium).length ?? 0;

  bool get canStartMockExam {
    final profile = definition.examProfile;
    final productionBank = bank;
    if (!hasFullUnlock ||
        !modeEnabled(LearningModeV1.mockExam) ||
        profile == null ||
        productionBank == null) {
      return false;
    }
    final accessible = productionBank.candidates.where(
      (candidate) => canAccess(productionBank.cardsById[candidate.questionId]!),
    );
    if (profile.allocations.isEmpty) {
      return accessible.length >= profile.questionCount;
    }
    final countByUnit = <String, int>{};
    for (final candidate in accessible) {
      countByUnit.update(
        candidate.unitId,
        (count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    return profile.allocations.every(
      (allocation) =>
          (countByUnit[allocation.unitId] ?? 0) >= allocation.questionCount,
    );
  }

  bool get isMockExamLocked {
    return definition.examProfile != null &&
        modeEnabled(LearningModeV1.mockExam) &&
        !hasFullUnlock;
  }

  bool get hasTimedMockExam {
    final session = activeSession;
    return session?.mode == LearningModeV1.mockExam &&
        definition.examProfile?.timeLimitMinutes != null;
  }

  Duration? get remainingMockExamDuration {
    final session = activeSession;
    if (session == null) return null;
    return _mockExamRemaining(session, _now());
  }

  bool modeEnabled(LearningModeV1 mode) =>
      definition.learningProduct.enabledModes.contains(mode);

  Future<void> initialize() async {
    try {
      bank = await _bankLoader.load();
      entitlement = await _coordinator.loadCachedEntitlements();
      await _refreshLearningState();
      await _loadActiveSession();
      await _loadProduct();
    } on Object catch (error) {
      fatalError = '$error';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadProduct() async {
    try {
      final query = await _coordinator.queryProducts();
      storeAvailable = query.storeAvailable;
      final productId =
          definition.monetization.productCatalog.fullUnlockProductId;
      fullUnlockProduct = query.products
          .where((product) => product.id == productId)
          .firstOrNull;
      if (!storeAvailable || fullUnlockProduct == null) {
        storeMessage = 'ストア商品を取得できません。無料問題は利用できます。';
      } else if (query.errorMessage != null) {
        storeMessage = 'ストア情報の一部を取得できませんでした。';
      }
    } on Object {
      storeAvailable = false;
      fullUnlockProduct = null;
      storeMessage = 'ストアに接続できません。無料問題は利用できます。';
    }
  }

  bool canAccess(QuizCard card) {
    final productionBank = bank;
    if (productionBank == null) return false;
    final questionId = productionBank.stableId(card);
    return definition.monetization.entitlementPolicy.canAccessContent(
      deckId: productionBank.deckIdByQuestionId[questionId] ?? '',
      isPremium: card.isPremium,
      snapshot: entitlement,
      catalog: definition.monetization.productCatalog,
    );
  }

  List<QuizCard> accessibleCardsFor(Unit unit) {
    final productionBank = bank!;
    final cards = unit.cards.where(canAccess).toList(growable: false)
      ..sort(
        (left, right) => productionBank
            .stableId(left)
            .compareTo(productionBank.stableId(right)),
      );
    return cards;
  }

  PracticeSelectionEngine get _practiceEngine => PracticeSelectionEngine(
        canAccess: (candidate) =>
            canAccess(bank!.cardsById[candidate.questionId]!),
        randomizer: _randomizer,
      );

  Future<bool> startUnit(String unitId) async {
    if (!modeEnabled(LearningModeV1.unitPractice)) return false;
    final ids = _practiceEngine.selectUnit(bank!.candidates, unitId);
    return _startSession(
      mode: LearningModeV1.unitPractice,
      questionIds: ids,
      unitId: unitId,
    );
  }

  Future<bool> startRandom() async {
    if (!modeEnabled(LearningModeV1.randomPractice)) return false;
    final count = min(
      definition.learningProduct.practiceQuestionCount,
      accessibleQuestionCount,
    );
    if (count < 1) return false;
    return _startSession(
      mode: LearningModeV1.randomPractice,
      questionIds: _practiceEngine.selectRandom(bank!.candidates, count: count),
    );
  }

  Future<bool> startUnanswered() async {
    if (!modeEnabled(LearningModeV1.unansweredPractice)) return false;
    return _startSession(
      mode: LearningModeV1.unansweredPractice,
      questionIds: _practiceEngine.selectUnanswered(bank!.candidates, events),
    );
  }

  Future<bool> startIncorrect() async {
    if (!modeEnabled(LearningModeV1.incorrectPractice)) return false;
    return _startSession(
      mode: LearningModeV1.incorrectPractice,
      questionIds: _practiceEngine.selectIncorrect(bank!.candidates, events),
    );
  }

  Future<bool> startRetry() async {
    final previous = result;
    if (!modeEnabled(LearningModeV1.retry) || previous == null) return false;
    return _startSession(
      mode: LearningModeV1.retry,
      questionIds: _practiceEngine.selectRetry(
        bank!.candidates,
        previous.incorrectQuestionIds,
      ),
      retrySourceSessionId: previous.sessionId,
    );
  }

  Future<bool> startMockExam() async {
    final profile = definition.examProfile;
    if (!modeEnabled(LearningModeV1.mockExam) || profile == null) return false;
    if (!hasFullUnlock) {
      storeMessage = '模擬試験は全問解放後に利用できます。';
      notifyListeners();
      return false;
    }
    final accessible = bank!.candidates.where(
      (candidate) => canAccess(bank!.cardsById[candidate.questionId]!),
    );
    try {
      final ids =
          MockExamEngineV1(randomizer: _randomizer).createQuestionSequence(
        profile: profile,
        accessibleQuestions: accessible,
      );
      return await _startSession(
        mode: LearningModeV1.mockExam,
        questionIds: ids,
        examProfileVersion: profile.profileVersion,
      );
    } on StateError catch (error) {
      storeMessage = error.message;
      notifyListeners();
      return false;
    }
  }

  Future<bool> _startSession({
    required LearningModeV1 mode,
    required List<String> questionIds,
    String? unitId,
    String? examProfileVersion,
    String? retrySourceSessionId,
  }) async {
    if (questionIds.isEmpty) return false;
    final now = _now();
    final session = QualificationSessionV1(
      sessionId:
          '${definition.appKey}-${now.microsecondsSinceEpoch}-${mode.wireName}',
      appKey: definition.appKey,
      bankRevision: bank!.bankRevision,
      mode: mode,
      questionIds: questionIds,
      currentIndex: 0,
      committedResponses: const {},
      startedAt: now,
      updatedAt: now,
      examProfileVersion: examProfileVersion,
      unitId: unitId,
      retrySourceSessionId: retrySourceSessionId,
    );
    activeSession = session;
    result = null;
    view = QualificationProductionView.quiz;
    _questionShownAt = now;
    await _sessionStore.save(session);
    _armMockExamDeadline(session);
    notifyListeners();
    return true;
  }

  Future<void> resume() async {
    final session = activeSession;
    if (session == null) return;
    if (_mockExamExpired(session, _now())) {
      await _completeSession(session);
      notifyListeners();
      return;
    }
    result = null;
    view = QualificationProductionView.quiz;
    _questionShownAt = _now();
    _armMockExamDeadline(session);
    notifyListeners();
  }

  Future<bool> completeExpiredMockExamIfNeeded() async {
    final session = activeSession;
    if (session == null || !_mockExamExpired(session, _now())) return false;
    await _completeExpiredMockExam(session);
    return activeSession?.sessionId != session.sessionId;
  }

  QuizCard? get currentCard {
    final session = activeSession;
    if (session == null) return null;
    return bank?.cardsById[session.currentQuestionId];
  }

  int? get currentResponse => activeSession
      ?.committedResponses[activeSession!.currentQuestionId]?.choiceIndex;

  Future<bool> commitAnswer(int choiceIndex) async {
    final session = activeSession;
    final card = currentCard;
    if (_transitionBusy || session == null || card == null) return false;
    if (session.committedResponses.containsKey(session.currentQuestionId) ||
        choiceIndex < 0 ||
        choiceIndex >= card.choices.length) {
      return false;
    }
    _transitionBusy = true;
    try {
      final now = _now();
      if (_mockExamExpired(session, now)) {
        await _completeSession(session);
        notifyListeners();
        return false;
      }
      final rawDuration =
          now.difference(_questionShownAt ?? now).inMilliseconds;
      final attemptId = '${session.sessionId}:${session.currentQuestionId}';
      final persistedEvent = (await _learningRepository.loadAllEvents())
          .where((event) => event.attemptId == attemptId)
          .firstOrNull;
      if (persistedEvent != null) {
        _validatePersistedAnswer(
          event: persistedEvent,
          session: session,
          card: card,
          choiceIndex: choiceIndex,
        );
        await _saveCommittedResponse(session, persistedEvent);
        return true;
      }
      final attemptNumber =
          await _learningRepository.countAttempts(session.currentQuestionId) +
              1;
      final response = SessionResponseV1(
        choiceIndex: choiceIndex,
        attemptId: attemptId,
        answeredAt: now,
      );
      final event = LearningEventV1(
        appKey: definition.appKey,
        sessionId: session.sessionId,
        attemptId: attemptId,
        questionId: session.currentQuestionId,
        questionVersion: card.questionVersion!,
        bankRevision: session.bankRevision,
        unitId: card.unitId!,
        knowledgeTarget: null,
        selectedChoice: choiceIndex,
        correct: choiceIndex == card.answerIndex,
        answeredAt: now,
        responseDurationMs: max(0, rawDuration),
        attemptNumber: attemptNumber,
        mode: session.mode,
        appVersion: definition.learningProduct.appVersion,
      );
      await _learningRepository.recordAnswer(event);
      await _saveCommittedResponse(session, event, response: response);
      return true;
    } finally {
      _transitionBusy = false;
    }
  }

  Future<void> _saveCommittedResponse(
    QualificationSessionV1 session,
    LearningEventV1 event, {
    SessionResponseV1? response,
  }) async {
    final committedResponse = response ??
        SessionResponseV1(
          choiceIndex: event.selectedChoice,
          attemptId: event.attemptId,
          answeredAt: event.answeredAt,
        );
    final updatedSession = session.copyWith(
      committedResponses: {
        ...session.committedResponses,
        session.currentQuestionId: committedResponse,
      },
      updatedAt: event.answeredAt.isBefore(session.updatedAt)
          ? session.updatedAt
          : event.answeredAt,
    );
    await _sessionStore.save(updatedSession);
    activeSession = updatedSession;
    if (!events.any((existing) => existing.attemptId == event.attemptId)) {
      events = List.unmodifiable([...events, event]);
    }
    notifyListeners();
  }

  void _validatePersistedAnswer({
    required LearningEventV1 event,
    required QualificationSessionV1 session,
    required QuizCard card,
    required int choiceIndex,
  }) {
    final expectedCorrect = choiceIndex == card.answerIndex;
    if (event.appKey != definition.appKey ||
        event.sessionId != session.sessionId ||
        event.questionId != session.currentQuestionId ||
        event.questionVersion != card.questionVersion ||
        event.bankRevision != session.bankRevision ||
        event.unitId != card.unitId ||
        event.knowledgeTarget != null ||
        event.selectedChoice != choiceIndex ||
        event.correct != expectedCorrect ||
        event.mode != session.mode ||
        event.appVersion != definition.learningProduct.appVersion) {
      throw StateError(
        'Conflicting answer commit: ${event.attemptId}',
      );
    }
  }

  Future<bool> advance() async {
    final session = activeSession;
    if (_transitionBusy || session == null || currentResponse == null) {
      return false;
    }
    _transitionBusy = true;
    try {
      if (session.currentIndex == session.questionIds.length - 1) {
        await _completeSession(session);
      } else {
        final now = _now();
        activeSession = session.copyWith(
          currentIndex: session.currentIndex + 1,
          updatedAt: now,
        );
        _questionShownAt = now;
        await _sessionStore.save(activeSession!);
      }
      notifyListeners();
      return true;
    } finally {
      _transitionBusy = false;
    }
  }

  Future<void> _completeSession(QualificationSessionV1 session) async {
    _mockExamDeadlineTimer?.cancel();
    _mockExamDeadlineTimer = null;
    final cards = bank!.cardsById;
    final incorrectIds = <String>[];
    var correctCount = 0;
    for (final questionId in session.questionIds) {
      final response = session.committedResponses[questionId];
      if (response?.choiceIndex == cards[questionId]!.answerIndex) {
        correctCount += 1;
      } else {
        incorrectIds.add(questionId);
      }
    }
    MockExamResultV1? mockResult;
    if (session.mode == LearningModeV1.mockExam) {
      mockResult = MockExamEngineV1(randomizer: _randomizer).score(
        profile: definition.examProfile!,
        questions: [
          for (final id in session.questionIds)
            MockExamQuestionV1(
              questionId: id,
              unitId: cards[id]!.unitId!,
              correctChoiceIndex: cards[id]!.answerIndex,
            ),
        ],
        responses: {
          for (final entry in session.committedResponses.entries)
            entry.key: entry.value.choiceIndex,
        },
      );
    }
    final existingHistory = (await _learningRepository.loadSessionHistory(
      limit: 1 << 30,
    ))
        .where((item) => item.sessionId == session.sessionId)
        .firstOrNull;
    final completion = SessionHistoryV1(
      appKey: definition.appKey,
      sessionId: session.sessionId,
      mode: session.mode,
      questionIds: session.questionIds,
      correctCount: correctCount,
      completedAt: existingHistory?.completedAt ?? _now(),
      unitId: session.unitId,
      examProfileVersion: session.examProfileVersion,
      passed: mockResult?.passed,
    );
    if (existingHistory == null) {
      await _learningRepository.recordSessionHistory(completion);
    } else {
      _validatePersistedCompletion(existingHistory, completion);
    }
    final completedResult = QualificationSessionResult(
      sessionId: session.sessionId,
      mode: session.mode,
      correctCount: correctCount,
      totalCount: session.questionIds.length,
      incorrectQuestionIds: List.unmodifiable(incorrectIds),
      mockExamResult: mockResult,
    );
    await _sessionStore.clear();
    activeSession = null;
    result = completedResult;
    await _refreshLearningState();
    view = QualificationProductionView.result;
  }

  void _validatePersistedCompletion(
    SessionHistoryV1 existing,
    SessionHistoryV1 expected,
  ) {
    final sameQuestions =
        existing.questionIds.length == expected.questionIds.length &&
            List.generate(
              existing.questionIds.length,
              (index) =>
                  existing.questionIds[index] == expected.questionIds[index],
            ).every((matches) => matches);
    if (existing.appKey != expected.appKey ||
        existing.sessionId != expected.sessionId ||
        existing.mode != expected.mode ||
        !sameQuestions ||
        existing.correctCount != expected.correctCount ||
        existing.unitId != expected.unitId ||
        existing.examProfileVersion != expected.examProfileVersion ||
        existing.passed != expected.passed) {
      throw StateError(
        'Conflicting session completion: ${existing.sessionId}',
      );
    }
  }

  void returnHome() {
    result = null;
    view = QualificationProductionView.home;
    notifyListeners();
  }

  Future<void> _refreshLearningState() async {
    events = await _learningRepository.loadAllEvents();
    history = await _learningRepository.loadSessionHistory();
    final productionBank = bank;
    if (productionBank == null) return;
    progress = ProgressCalculatorV1(
      recentWindow: definition.learningProduct.recentWindowSize,
    ).calculate(productionBank.candidates, events);
    weakness = WeaknessCalculatorV1(
      recentWindow: definition.learningProduct.recentWindowSize,
    ).calculate(productionBank.candidates, events);
    recommendation = const DeterministicRecommendationEngine().recommend(
      questions: productionBank.candidates,
      weakness: weakness!,
    );
  }

  Future<void> _loadActiveSession() async {
    final loaded = await _sessionStore.load();
    if (loaded == null) return;
    if (!_isCompatible(loaded)) {
      await _sessionStore.clear();
      return;
    }
    activeSession = loaded;
    final completed = (await _learningRepository.loadSessionHistory(
      limit: 1 << 30,
    ))
        .any((history) => history.sessionId == loaded.sessionId);
    if (completed) {
      await _completeSession(loaded);
      return;
    }
    if (_mockExamExpired(loaded, _now())) {
      await _completeSession(loaded);
    } else {
      _armMockExamDeadline(loaded);
    }
  }

  bool _mockExamExpired(QualificationSessionV1 session, DateTime now) {
    final remaining = _mockExamRemaining(session, now);
    return remaining != null && remaining == Duration.zero;
  }

  Duration? _mockExamRemaining(QualificationSessionV1 session, DateTime now) {
    if (session.mode != LearningModeV1.mockExam) return null;
    final minutes = definition.examProfile?.timeLimitMinutes;
    if (minutes == null) return null;
    final remaining = session.startedAt
        .add(Duration(minutes: minutes))
        .difference(now);
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void _armMockExamDeadline(QualificationSessionV1 session) {
    _mockExamDeadlineTimer?.cancel();
    _mockExamDeadlineTimer = null;
    final remaining = _mockExamRemaining(session, _now());
    if (remaining == null) return;
    if (remaining == Duration.zero) {
      unawaited(_completeExpiredMockExam(session));
      return;
    }
    _mockExamDeadlineTimer = Timer(
      remaining,
      () => unawaited(_completeExpiredMockExam(session)),
    );
  }

  Future<void> _completeExpiredMockExam(
    QualificationSessionV1 expectedSession,
  ) async {
    final session = activeSession;
    if (_transitionBusy ||
        session == null ||
        session.sessionId != expectedSession.sessionId ||
        !_mockExamExpired(session, _now())) {
      return;
    }
    _transitionBusy = true;
    try {
      await _completeSession(session);
      notifyListeners();
    } finally {
      _transitionBusy = false;
    }
  }

  bool _isCompatible(QualificationSessionV1 session) {
    final productionBank = bank;
    if (productionBank == null ||
        session.appKey != definition.appKey ||
        session.bankRevision != productionBank.bankRevision ||
        session.questionIds.any(
          (id) => !productionBank.cardsById.containsKey(id),
        )) {
      return false;
    }
    if (session.mode == LearningModeV1.mockExam &&
        session.examProfileVersion != definition.examProfile?.profileVersion) {
      return false;
    }
    for (final questionId in session.questionIds) {
      final card = productionBank.cardsById[questionId]!;
      if (!canAccess(card)) return false;
    }
    for (final entry in session.committedResponses.entries) {
      final card = productionBank.cardsById[entry.key];
      if (card == null || entry.value.choiceIndex >= card.choices.length) {
        return false;
      }
      if (session.questionIds.indexOf(entry.key) > session.currentIndex) {
        return false;
      }
    }
    for (var index = 0; index < session.currentIndex; index += 1) {
      if (!session.committedResponses.containsKey(session.questionIds[index])) {
        return false;
      }
    }
    return true;
  }

  Future<void> purchaseFullUnlock() async {
    final product = fullUnlockProduct;
    if (purchasePending || !storeAvailable || product == null) {
      storeMessage = '購入商品を利用できません。無料問題は引き続き利用できます。';
      notifyListeners();
      return;
    }
    purchasePending = true;
    storeMessage = null;
    notifyListeners();
    try {
      await _coordinator.purchase(product.id);
    } on Object {
      purchasePending = false;
      storeMessage = '購入を開始できませんでした。';
      notifyListeners();
    }
  }

  Future<void> restorePurchases() async {
    if (purchasePending) return;
    purchasePending = true;
    storeMessage = null;
    notifyListeners();
    try {
      await _coordinator.restore();
    } on Object {
      storeMessage = '購入の復元に失敗しました。';
    } finally {
      purchasePending = false;
      notifyListeners();
    }
  }

  Future<void> _handlePurchaseResult(PurchaseResult purchaseResult) async {
    try {
      entitlement = await _coordinator.handlePurchaseResult(purchaseResult);
      switch (purchaseResult.status) {
        case PurchaseResultStatus.pending:
          purchasePending = true;
          storeMessage = '購入処理を確認しています。';
        case PurchaseResultStatus.purchased:
        case PurchaseResultStatus.restored:
          purchasePending = false;
          storeMessage =
              hasFullUnlock ? '全${bank?.cards.length ?? 0}問を利用できます。' : null;
        case PurchaseResultStatus.canceled:
          purchasePending = false;
          storeMessage = '購入はキャンセルされました。';
        case PurchaseResultStatus.error:
          purchasePending = false;
          storeMessage = '購入を完了できませんでした。';
      }
    } on Object {
      purchasePending = false;
      storeMessage = '購入情報を保存できませんでした。';
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _mockExamDeadlineTimer?.cancel();
    unawaited(_purchaseSubscription.cancel());
    unawaited(_purchaseGateway.dispose());
    super.dispose();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
