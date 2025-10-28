// lib/services/iap_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'purchase_store.dart';

/// ストアに登録した productId と**完全一致**させること
class ProductCatalog {
  // Play Console の productId（deck_xxx_unlock）と対になる“デッキID本体”
  // ※ 小文字に統一（例: deck_m01）
  static const deckIds = [
    'deck_m01',
    'deck_m02',
    'deck_m03',
    'deck_m04',
    'deck_m05',
    'deck_m06',
    'deck_m07',
    'deck_m08',
  ];

  // セット/全体/Pro
  static const bundle5 = 'bundle_5decks_unlock';
  static const bundleAll = 'bundle_all_unlock';
  static const pro = 'pro_upgrade';

  // まとめ
  static const bundles = [bundle5, bundleAll];
  static const specials = [pro];

  static Set<String> allProductIds() => {
    ...deckIds.map((d) => '${d}_unlock'),
    ...bundles,
    ...specials,
  };
}

class IapService with ChangeNotifier {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// 価格表示用（ProductDetails.id -> ProductDetails）
  final Map<String, ProductDetails> products = {};

  /// ストア接続/製品取得の可否
  bool available = false;
  bool get isReady => available && products.isNotEmpty;

  // ===== 所有状態（メモリキャッシュ） =====
  /// 例: {'deck_m01', 'deck_m02', ...}
  final Set<String> _ownedDeckIds = <String>{};

  /// Pro フラグ（機能フル解放等に使用）
  bool _isPro = false;
  bool get isPro => _isPro;

  /// 初期化：products取得 → 所有状態ロード → purchaseStream購読 →（Androidのみ）restorePurchases()
  Future<void> init() async {
    available = await _iap.isAvailable();
    debugPrint('IAP available: $available');
    if (!available) {
      debugPrint('❌ IAP not available (Play Store無効/端末非対応 or 非Playビルド)');
      return;
    }

    final ids = ProductCatalog.allProductIds();
    debugPrint('Querying products: $ids');

    final resp = await _iap.queryProductDetails(ids);

    if (resp.error != null) {
      debugPrint('❌ queryProductDetails error: ${resp.error}');
    }
    if (resp.notFoundIDs.isNotEmpty) {
      debugPrint(
        '❗ notFoundIDs: ${resp.notFoundIDs} '
        '(productId不一致/未公開/テスター外の可能性)',
      );
    }

    products
      ..clear()
      ..addEntries(resp.productDetails.map((p) => MapEntry(p.id, p)));
    debugPrint('✅ Loaded products: ${products.keys.toList()} (count=${products.length})');

    // 所有状態をローカルストアからロード（=即時UI反映の基礎）
    await _reloadOwnershipFromStore();

    // 先に購読を開始（以降の restore で流れてくるイベントを受ける）
    _sub?.cancel();
    _sub = _iap.purchaseStream.listen(
      _onUpdated,
      onError: (e) => debugPrint('purchaseStream error: $e'),
    );

    // ▼ 過去購入の再送をトリガ（Androidは自動呼び出しOK / iOSはユーザー起点が望ましい）
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _iap.restorePurchases();
      }
    } catch (e) {
      debugPrint('restorePurchases on init failed: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  // ---- API: 購入/復元 ----
  Future<void> buy(String productId) async {
    final p = products[productId];
    if (!isReady) {
      throw StateError('Store not ready (isReady=false)');
    }
    if (p == null) {
      throw StateError('Product not loaded: $productId');
    }
    await _iap.buyNonConsumable(purchaseParam: PurchaseParam(productDetails: p));
  }

  Future<void> restore() async {
    // Android/iOS 共通：過去購入の再送をトリガ
    await _iap.restorePurchases();
  }

  // ---- 内部: ストアから所有状態をロード ----
  Future<void> _reloadOwnershipFromStore() async {
    _ownedDeckIds
      ..clear()
      ..addAll(await PurchaseStore.getOwnedDeckIds());
    _isPro = await PurchaseStore.getPro();
    notifyListeners();
  }

  // ---- ストリーム処理 ----
  Future<void> _onUpdated(List<PurchaseDetails> list) async {
    for (final p in list) {
      debugPrint('purchase updated: id=${p.productID}, status=${p.status}');
      switch (p.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          try {
            await _grantEntitlement(p.productID);
          } catch (e) {
            debugPrint('grantEntitlement failed: $e');
          } finally {
            if (p.pendingCompletePurchase) {
              await _iap.completePurchase(p);
            }
          }
          break;

        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          if (p.pendingCompletePurchase) {
            await _iap.completePurchase(p);
          }
          break;

        case PurchaseStatus.pending:
          // UI 側でスピナー等を表示するなら busy を使う
          break;
      }
    }
  }

  // ---- 付与ロジック（将来サーバ検証に差し替え可） ----
  Future<void> _grantEntitlement(String productId) async {
    // Pro: 機能解放
    if (productId == ProductCatalog.pro) {
      await PurchaseStore.setPro(true);
      debugPrint('✔ grant: pro enabled');
      _isPro = true;
      notifyListeners(); // ← UI即時反映
      return;
    }

    // 全体パック
    if (productId == ProductCatalog.bundleAll) {
      await PurchaseStore.addOwnedDecks(ProductCatalog.deckIds);
      debugPrint('✔ grant: bundle_all -> all deckIds');
      _ownedDeckIds
        ..clear()
        ..addAll(ProductCatalog.deckIds);
      notifyListeners();
      return;
    }

    // 5単元パック（必要に応じて構成を変更）
    if (productId == ProductCatalog.bundle5) {
      final five = ProductCatalog.deckIds.take(5);
      await PurchaseStore.addOwnedDecks(five);
      debugPrint('✔ grant: bundle_5 -> first 5 deckIds');
      _ownedDeckIds.addAll(five);
      notifyListeners();
      return;
    }

    // 個別デッキ: deck_Xxx_unlock -> deck_Xxx
    if (productId.endsWith('_unlock')) {
      final deckId = productId
          .substring(0, productId.length - '_unlock'.length)
          .toLowerCase(); // 念のため小文字正規化
      await PurchaseStore.addOwnedDecks([deckId]);
      debugPrint('✔ grant: single deck -> $deckId');
      _ownedDeckIds.add(deckId);
      notifyListeners();
    }
  }

  // ---- 所有判定API（UI用）：この productId は購入済みか？ ----
  bool isOwnedProduct(String productId) {
    if (productId == ProductCatalog.pro) return _isPro;

    if (productId == ProductCatalog.bundleAll) {
      // 全デッキ所有で bundle_all を「購入済み」扱い
      return ProductCatalog.deckIds.every(_ownedDeckIds.contains);
    }

    if (productId == ProductCatalog.bundle5) {
      // 先頭5デッキ所有で bundle_5 を「購入済み」扱い
      return ProductCatalog.deckIds.take(5).every(_ownedDeckIds.contains);
    }

    if (productId.endsWith('_unlock')) {
      final deckId = productId.substring(0, productId.length - '_unlock'.length).toLowerCase();
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
      final owned = ProductCatalog.deckIds.take(5).where(_ownedDeckIds.contains).length;
      return '5単元: $owned/5 所有';
    }
    if (productId.endsWith('_unlock')) {
      final deckId = productId.substring(0, productId.length - '_unlock'.length).toLowerCase();
      return _ownedDeckIds.contains(deckId) ? '$deckId: 所有' : '$deckId: 未所有';
    }
    return '不明';
  }
}
