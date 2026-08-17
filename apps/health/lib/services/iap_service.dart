// lib/services/iap_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:quiz_engine/quiz_engine.dart' as engine;

import '../quiz_app_definition.dart';
import 'in_app_purchase_gateway.dart';
import 'purchase_store.dart';
import 'shared_preferences_entitlement_cache.dart';

/// ストアに登録した productId と**完全一致**させること
class ProductCatalog {
  static engine.ProductCatalog get _catalog =>
      currentQuizApp.monetization.productCatalog;

  static List<String> get deckIds => _catalog.deckIds;
  static String get bundle5 => _catalog.bundle5ProductId!;
  static String get bundleAll => _catalog.bundleAllProductId!;
  static String get pro => _catalog.proProductId!;
  static List<String> get bundles => [bundle5, bundleAll];
  static List<String> get specials => [pro];
  static Set<String> allProductIds() => _catalog.productIds;
}

class IapService with ChangeNotifier {
  IapService._internal();
  static final IapService _instance = IapService._internal();
  factory IapService() => _instance;

  final InAppPurchaseGateway _gateway = InAppPurchaseGateway();
  late final SharedPreferencesEntitlementCache _cache =
      SharedPreferencesEntitlementCache(
    catalog: currentQuizApp.monetization.productCatalog,
  );
  late final engine.PurchaseEntitlementCoordinator _coordinator =
      engine.PurchaseEntitlementCoordinator(
    gateway: _gateway,
    definition: currentQuizApp.monetization,
    cache: _cache,
  );
  StreamSubscription<engine.PurchaseResult>? _sub;
  static bool _initialized = false;

  /// 価格表示用（ProductDetails.id -> ProductDetails）
  Map<String, ProductDetails> get products => _gateway.products;

  /// ストア接続/製品取得の可否
  bool available = false;
  bool get isReady => available && products.isNotEmpty;

  // ===== 所有状態（メモリキャッシュ） =====
  /// 例: {'deck_m01', 'deck_m02', ...}  ※単体デッキ購入の所有状況
  final Set<String> _ownedDeckIds = <String>{};

  /// Pro フラグ
  bool _isPro = false;
  bool get isPro => _isPro;

  /// ★選べる5単元パックの所有フラグ（権利そのもの）
  bool _hasFivePack = false;
  bool get hasFivePack => _hasFivePack;

  /// 初期化：products取得 → 所有状態ロード → purchaseStream購読 →（Androidのみ）restorePurchases()
  Future<void> init() async {
    // すでに初期化済みでも、products が空 or 購買ストリーム未購読なら再初期化
    if (_initialized && products.isNotEmpty && _sub != null) {
      debugPrint('IAP init: reuse existing (already initialized)');
      return;
    }
    // Existing SharedPreferences remain the offline entitlement cache.
    await _reloadOwnershipFromStore();

    final response = await _coordinator.queryProducts();
    available = response.storeAvailable;
    debugPrint('IAP available: $available');
    if (!available) {
      debugPrint('❌ IAP not available (Play Store無効/端末非対応 or 非Playビルド)');
      // 利用不可でも“初期化済み扱い”にして以降の再初期化を抑制
      _initialized = true;
      return;
    }

    final ids = ProductCatalog.allProductIds();
    debugPrint('Querying products: $ids');

    if (response.errorMessage != null) {
      debugPrint('❌ queryProductDetails error: ${response.errorMessage}');
    }
    if (response.notFoundProductIds.isNotEmpty) {
      debugPrint(
        '❗ notFoundIDs: ${response.notFoundProductIds} '
        '(productId不一致/未公開/テスター外の可能性)',
      );
    }

    debugPrint(
        '✅ Loaded products: ${products.keys.toList()} (count=${products.length})');

    // 先に購読を開始（以降の restore で流れてくるイベントを受ける）
    await _sub?.cancel();
    _sub = _gateway.purchaseResults.listen(
      _onUpdated,
      onError: (e) => debugPrint('purchaseStream error: $e'),
    );
    _gateway.startListening();

    // ▼ 過去購入の再送をトリガ（Androidは自動呼び出しOK / iOSはユーザー起点が望ましい）
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _coordinator.restore();
      }
    } catch (e) {
      debugPrint('restorePurchases on init failed: $e');
    }
    _initialized = true; // ← ★これを正常系の最後に追加！
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_gateway.dispose());
    super.dispose();
  }

  /// 指定 productId が isOwnedProduct=true になるまで待機（購買ストリーム反映を待つ）
  Future<bool> waitUntilOwned(String productId,
      {Duration timeout = const Duration(seconds: 8)}) async {
    // 即時チェック
    if (isOwnedProduct(productId)) return true;
    final completer = Completer<bool>();
    late VoidCallback listener;
    listener = () {
      if (isOwnedProduct(productId) && !completer.isCompleted) {
        removeListener(listener);
        completer.complete(true);
      }
    };
    addListener(listener);
    // タイムアウト監視
    Future.delayed(timeout, () {
      if (!completer.isCompleted) {
        removeListener(listener);
        completer.complete(false);
      }
    });
    return completer.future;
  }

  // ---- API: 購入/復元 ----
  Future<void> buy(String productId) async {
    if (!isReady) {
      throw StateError('Store not ready (isReady=false)');
    }
    await _coordinator.purchase(productId);
  }

  Future<void> restore() async {
    // Android/iOS 共通：過去購入の再送をトリガ
    await _coordinator.restore();
  }

  // ---- 内部: ストアから所有状態をロード ----
  Future<void> _reloadOwnershipFromStore() async {
    // ★ ここで未選択なら自動割り当てを実施（サイレント修復）
    await PurchaseStore.autoAssignFivePackIfOwnedAndEmpty();
    final snapshot = await _coordinator.loadCachedEntitlements();
    _applySnapshot(snapshot);
    notifyListeners();
  }

  // ---- ストリーム処理 ----
  Future<void> _onUpdated(engine.PurchaseResult result) async {
    debugPrint(
      'purchase updated: id=${result.productId}, status=${result.status}',
    );
    try {
      final snapshot = await _coordinator.handlePurchaseResult(result);
      final granted = result.status == engine.PurchaseResultStatus.purchased ||
          result.status == engine.PurchaseResultStatus.restored;
      if (granted &&
          currentQuizApp.monetization.productCatalog
              .recognizes(result.productId)) {
        _applySnapshot(snapshot);
        notifyListeners();
      }
    } catch (error) {
      debugPrint('purchase result handling failed: $error');
    }
  }

  void _applySnapshot(engine.EntitlementSnapshot snapshot) {
    final catalog = currentQuizApp.monetization.productCatalog;
    _ownedDeckIds
      ..clear()
      ..addAll(
        snapshot.ownedProductIds
            .map(catalog.deckIdForProduct)
            .whereType<String>(),
      );
    _isPro = catalog.proProductId != null &&
        snapshot.ownedProductIds.contains(catalog.proProductId);
    _hasFivePack = catalog.bundle5ProductId != null &&
        snapshot.ownedProductIds.contains(catalog.bundle5ProductId);
  }

  // ---- 所有判定API（UI用）：この productId は購入済みか？ ----
  bool isOwnedProduct(String productId) {
    if (productId == ProductCatalog.pro) return _isPro;

    if (productId == ProductCatalog.bundleAll) {
      // 全デッキ所有で bundle_all を「購入済み」扱い
      return ProductCatalog.deckIds.every(_ownedDeckIds.contains);
    }

    if (productId == ProductCatalog.bundle5) {
      // 新方式：5パックの「権利」を持っているかで判定
      // 互換：旧「先頭5デッキ所有」ユーザーにも配慮
      final legacyOwnedFirst5 =
          ProductCatalog.deckIds.take(5).every(_ownedDeckIds.contains);
      return _hasFivePack || legacyOwnedFirst5;
    }

    if (productId.endsWith('_unlock')) {
      final deckId = productId
          .substring(0, productId.length - '_unlock'.length)
          .toLowerCase();
      return _ownedDeckIds.contains(deckId);
    }

    return false;
  }

  // ---- （任意）デバッグ/表示用：所有状況の要約 ----
  String ownedSummaryFor(String productId) {
    if (productId == ProductCatalog.pro) return _isPro ? 'Pro: 有効' : 'Pro: 無効';
    if (productId == ProductCatalog.bundleAll) {
      final owned = ProductCatalog.deckIds.where(_ownedDeckIds.contains).length;
      return '全解放: $owned/${ProductCatalog.deckIds.length} 所有';
    }
    if (productId == ProductCatalog.bundle5) {
      return _hasFivePack ? '5単元パック: 権利あり' : '5単元パック: 未所有';
    }
    if (productId.endsWith('_unlock')) {
      final deckId = productId
          .substring(0, productId.length - '_unlock'.length)
          .toLowerCase();
      return _ownedDeckIds.contains(deckId) ? '$deckId: 所有' : '$deckId: 未所有';
    }
    return '不明';
  }
}
