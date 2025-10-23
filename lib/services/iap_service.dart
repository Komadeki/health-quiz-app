// lib/services/iap_service.dart

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'purchase_store.dart';

/// ストアに登録した productId と**完全一致**させること
class ProductCatalog {
  // 個別単元（必要に応じて増減）
  static const deckIds = [
    'deck_M01',
    'deck_M02',
    'deck_M03',
    'deck_M04',
    'deck_M05',
    'deck_M06',
    'deck_M07',
    'deck_M08',
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

class IapService {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// 価格表示用（ProductDetails.id -> ProductDetails）
  Map<String, ProductDetails> products = {};

  /// ストア接続/製品取得の可否
  bool available = false;
  bool get isReady => available && products.isNotEmpty;

  /// 初期化：可用性チェック→製品情報取得→購入ストリーム購読
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
    debugPrint(
      '✅ Loaded products: ${products.keys.toList()} (count=${products.length})',
    );

    _sub?.cancel();
    _sub = _iap.purchaseStream.listen(
      _onUpdated,
      onError: (e) {
        debugPrint('purchaseStream error: $e');
      },
    );
  }

  void dispose() => _sub?.cancel();

  // ---- 購入API ----
  Future<void> buy(String productId) async {
    final p = products[productId];
    if (!isReady) {
      throw StateError('Store not ready (isReady=false)');
    }
    if (p == null) {
      throw StateError('Product not loaded: $productId');
    }
    await _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: p),
    );
  }

  Future<void> restore() async => _iap.restorePurchases();

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

  // 付与ロジック（将来サーバ検証に差し替え可）
  Future<void> _grantEntitlement(String productId) async {
    // Pro: 機能解放
    if (productId == ProductCatalog.pro) {
      await PurchaseStore.setPro(true);
      debugPrint('✔ grant: pro enabled');
      return;
    }

    // 全体パック
    if (productId == ProductCatalog.bundleAll) {
      await PurchaseStore.addOwnedDecks(ProductCatalog.deckIds);
      debugPrint('✔ grant: bundle_all -> all deckIds');
      return;
    }

    // 5単元パック（必要に応じて構成を変更）
    if (productId == ProductCatalog.bundle5) {
      final five = ProductCatalog.deckIds.take(5);
      await PurchaseStore.addOwnedDecks(five);
      debugPrint('✔ grant: bundle_5 -> first 5 deckIds');
      return;
    }

    // 個別デッキ: deck_Xxx_unlock -> deck_Xxx
    if (productId.endsWith('_unlock')) {
      final deckId = productId.substring(
        0,
        productId.length - '_unlock'.length,
      );
      await PurchaseStore.addOwnedDecks([deckId]);
      debugPrint('✔ grant: single deck -> $deckId');
    }
  }
}
