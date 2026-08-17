import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'fixture_bank.dart';
import 'fixture_purchase.dart';
import 'generated/app_manifest.g.dart';

final class FixtureShellController extends ChangeNotifier {
  FixtureShellController({
    required FixtureBankLoader bankLoader,
    FixturePurchaseGateway? purchaseGateway,
    InMemoryEntitlementCache? entitlementCache,
  })  : _bankLoader = bankLoader,
        _purchaseGateway = purchaseGateway ?? FixturePurchaseGateway(),
        _entitlementCache = entitlementCache ?? InMemoryEntitlementCache() {
    _coordinator = PurchaseEntitlementCoordinator(
      gateway: _purchaseGateway,
      definition: GeneratedAppManifest.monetizationDefinition,
      cache: _entitlementCache,
    );
    _purchaseSubscription = _purchaseGateway.purchaseResults.listen(
      _handlePurchaseResult,
    );
  }

  final FixtureBankLoader _bankLoader;
  final FixturePurchaseGateway _purchaseGateway;
  final InMemoryEntitlementCache _entitlementCache;
  late final PurchaseEntitlementCoordinator _coordinator;
  late final StreamSubscription<PurchaseResult> _purchaseSubscription;
  Completer<void>? _pendingPurchase;

  FixtureBank? bank;
  EntitlementSnapshot snapshot = EntitlementSnapshot();
  bool isLoading = true;
  String? error;

  Future<void> load() async {
    try {
      bank = await _bankLoader.load();
      snapshot = await _coordinator.loadCachedEntitlements();
      error = null;
    } on Object catch (caught) {
      error = caught.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  bool canAccess(String deckId, QuizCard card) {
    return GeneratedAppManifest.monetizationDefinition.entitlementPolicy
        .canAccessContent(
      deckId: deckId,
      isPremium: card.isPremium,
      snapshot: snapshot,
      catalog: GeneratedAppManifest.productCatalog,
    );
  }

  Future<void> purchaseFullUnlock() async {
    final productId = GeneratedAppManifest.productCatalog.fullUnlockProductId;
    if (productId == null) {
      throw StateError('Fixture full-unlock product is not configured.');
    }
    final handled = Completer<void>();
    _pendingPurchase = handled;
    await _coordinator.purchase(productId);
    await handled.future;
  }

  Future<void> _handlePurchaseResult(PurchaseResult result) async {
    try {
      snapshot = await _coordinator.handlePurchaseResult(result);
      notifyListeners();
      _pendingPurchase?.complete();
    } on Object catch (error, stackTrace) {
      _pendingPurchase?.completeError(error, stackTrace);
    } finally {
      _pendingPurchase = null;
    }
  }

  @override
  void dispose() {
    unawaited(_purchaseSubscription.cancel());
    unawaited(_purchaseGateway.dispose());
    super.dispose();
  }
}
