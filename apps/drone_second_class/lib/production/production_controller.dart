import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quiz_engine/quiz_engine.dart';

import '../generated/app_manifest.g.dart';
import 'production_bank.dart';
import 'production_persistence.dart';
import 'production_purchase.dart';
import 'production_session.dart';

enum DroneProductionView { home, quiz, result }

final class DroneProductionController extends ChangeNotifier {
  DroneProductionController({
    required DroneBankLoader bankLoader,
    required DroneSessionStore sessionStore,
    required DronePurchaseGateway purchaseGateway,
    EntitlementCache? entitlementCache,
  })  : _bankLoader = bankLoader,
        _sessionStore = sessionStore,
        _purchaseGateway = purchaseGateway,
        _entitlementCache = entitlementCache ?? const DroneEntitlementCache() {
    _coordinator = PurchaseEntitlementCoordinator(
      gateway: _purchaseGateway,
      definition: GeneratedAppManifest.monetizationDefinition,
      cache: _entitlementCache,
    );
    _purchaseSubscription = _purchaseGateway.purchaseResults.listen(
      _handlePurchaseResult,
      onError: (Object error, StackTrace stackTrace) {
        purchasePending = false;
        storeMessage = '購入情報を確認できませんでした。無料20問は利用できます。';
        notifyListeners();
      },
    );
    _purchaseGateway.startListening();
  }

  final DroneBankLoader _bankLoader;
  final DroneSessionStore _sessionStore;
  final DronePurchaseGateway _purchaseGateway;
  final EntitlementCache _entitlementCache;
  late final PurchaseEntitlementCoordinator _coordinator;
  late final StreamSubscription<PurchaseResult> _purchaseSubscription;

  DroneProductionBank? bank;
  DroneQuizSession? activeSession;
  DroneQuizResult? result;
  EntitlementSnapshot entitlement = EntitlementSnapshot();
  DroneProductionView view = DroneProductionView.home;
  PurchaseProduct? fullUnlockProduct;
  bool storeAvailable = false;
  bool purchasePending = false;
  bool isLoading = true;
  bool _transitionBusy = false;
  String? fatalError;
  String? storeMessage;

  bool get hasFullUnlock {
    final productId = GeneratedAppManifest.productCatalog.fullUnlockProductId;
    return productId != null && entitlement.ownedProductIds.contains(productId);
  }

  int get accessibleQuestionCount =>
      bank?.cards.where((card) => canAccess(card)).length ?? 0;

  Future<void> initialize() async {
    try {
      bank = await _bankLoader.load();
      entitlement = await _coordinator.loadCachedEntitlements();
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
      final productId = GeneratedAppManifest.productCatalog.fullUnlockProductId;
      fullUnlockProduct = query.products
          .where((product) => product.id == productId)
          .firstOrNull;
      if (!storeAvailable || fullUnlockProduct == null) {
        storeMessage = 'ストア商品を取得できません。無料20問は利用できます。';
      } else if (query.errorMessage != null) {
        storeMessage = 'ストア情報の一部を取得できませんでした。';
      }
    } on Object {
      storeAvailable = false;
      fullUnlockProduct = null;
      storeMessage = 'ストアに接続できません。無料20問は利用できます。';
    }
  }

  bool canAccess(QuizCard card) {
    return GeneratedAppManifest.monetizationDefinition.entitlementPolicy
        .canAccessContent(
      deckId: bank?.decks.first.id ?? '',
      isPremium: card.isPremium,
      snapshot: entitlement,
      catalog: GeneratedAppManifest.productCatalog,
    );
  }

  List<QuizCard> accessibleCardsFor(Unit unit) {
    final cards = unit.cards.where(canAccess).toList(growable: false)
      ..sort((left, right) => stableId(left).compareTo(stableId(right)));
    return cards;
  }

  String stableId(QuizCard card) =>
      GeneratedAppManifest.questionIdentityPolicy.stableIdFor(card);

  Future<void> startUnit(String unitId) async {
    final productionBank = bank;
    final unit = productionBank?.unitById(unitId);
    if (productionBank == null || unit == null) return;
    final cards = accessibleCardsFor(unit);
    if (cards.isEmpty) return;
    activeSession = DroneQuizSession(
      sessionId: 'drone-${DateTime.now().microsecondsSinceEpoch}',
      bankRevision: productionBank.bankRevision,
      unitId: unit.id,
      questionIds: cards.map(stableId).toList(growable: false),
      currentIndex: 0,
      responses: const {},
      updatedAt: DateTime.now().toUtc(),
    );
    result = null;
    view = DroneProductionView.quiz;
    await _sessionStore.save(activeSession!);
    notifyListeners();
  }

  void resume() {
    if (activeSession == null) return;
    result = null;
    view = DroneProductionView.quiz;
    notifyListeners();
  }

  QuizCard? get currentCard {
    final session = activeSession;
    if (session == null) return null;
    return bank?.cardsById[session.currentQuestionId];
  }

  int? get currentResponse {
    final session = activeSession;
    if (session == null) return null;
    return session.responses[session.currentQuestionId];
  }

  Future<bool> commitAnswer(int choiceIndex) async {
    final session = activeSession;
    final card = currentCard;
    if (_transitionBusy || session == null || card == null) return false;
    if (session.responses.containsKey(session.currentQuestionId) ||
        choiceIndex < 0 ||
        choiceIndex >= card.choices.length) {
      return false;
    }
    _transitionBusy = true;
    try {
      activeSession = session.copyWith(
        responses: {
          ...session.responses,
          session.currentQuestionId: choiceIndex
        },
        updatedAt: DateTime.now().toUtc(),
      );
      await _sessionStore.save(activeSession!);
      notifyListeners();
      return true;
    } finally {
      _transitionBusy = false;
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
        result = DroneQuizResult(
          correct: _correctCount(session),
          total: session.questionIds.length,
        );
        activeSession = null;
        await _sessionStore.clear();
        view = DroneProductionView.result;
      } else {
        activeSession = session.copyWith(
          currentIndex: session.currentIndex + 1,
          updatedAt: DateTime.now().toUtc(),
        );
        await _sessionStore.save(activeSession!);
      }
      notifyListeners();
      return true;
    } finally {
      _transitionBusy = false;
    }
  }

  void returnHome() {
    result = null;
    view = DroneProductionView.home;
    notifyListeners();
  }

  Future<void> purchaseFullUnlock() async {
    final product = fullUnlockProduct;
    if (purchasePending || !storeAvailable || product == null) {
      storeMessage = '購入商品を利用できません。無料20問は引き続き利用できます。';
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
          storeMessage = hasFullUnlock ? '全100問を利用できます。' : null;
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

  Future<void> _loadActiveSession() async {
    final loaded = await _sessionStore.load();
    if (loaded == null) return;
    if (!_isCompatible(loaded)) {
      await _sessionStore.clear();
      return;
    }
    activeSession = loaded;
  }

  bool _isCompatible(DroneQuizSession session) {
    final productionBank = bank;
    if (productionBank == null ||
        session.sessionId.isEmpty ||
        session.bankRevision != productionBank.bankRevision ||
        session.questionIds.isEmpty ||
        session.currentIndex < 0 ||
        session.currentIndex >= session.questionIds.length ||
        session.questionIds.toSet().length != session.questionIds.length) {
      return false;
    }
    final unit = productionBank.unitById(session.unitId);
    if (unit == null) return false;
    final unitIds = unit.cards.map(stableId).toSet();
    if (!unitIds.containsAll(session.questionIds)) return false;
    final byId = productionBank.cardsById;
    for (final questionId in session.questionIds) {
      final card = byId[questionId];
      if (card == null || !canAccess(card)) return false;
    }
    if (!session.questionIds.toSet().containsAll(session.responses.keys)) {
      return false;
    }
    for (final entry in session.responses.entries) {
      final card = byId[entry.key];
      if (card == null ||
          entry.value < 0 ||
          entry.value >= card.choices.length) {
        return false;
      }
      if (session.questionIds.indexOf(entry.key) > session.currentIndex) {
        return false;
      }
    }
    for (var index = 0; index < session.currentIndex; index += 1) {
      if (!session.responses.containsKey(session.questionIds[index])) {
        return false;
      }
    }
    return true;
  }

  int _correctCount(DroneQuizSession session) {
    final cards = bank!.cardsById;
    var correct = 0;
    for (final entry in session.responses.entries) {
      if (cards[entry.key]?.answerIndex == entry.value) correct += 1;
    }
    return correct;
  }

  @override
  void dispose() {
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
