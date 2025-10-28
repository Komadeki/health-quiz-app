// lib/screens/purchase_screen.dart
import 'package:flutter/material.dart';
import '../services/iap_service.dart';
import '../services/purchase_store.dart';

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});
  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  // 画面内インスタンス（Provider化は任意）
  final iap = IapService();

  bool loading = true; // ProductDetailsロード中
  bool busy = false; // 購入/復元 進行中（復元時は全体オーバーレイ、購入時は対象ボタンのみスピナー）
  bool isProLegacy = false; // 旧フラグ（後方互換用）
  Set<String> ownedLegacy = {}; // 旧デッキ所有（後方互換用）

  String? _pendingProductId; // 購入中の商品ID
  late final VoidCallback _iapListener;

  // ---- helpers ----
  String _priceOf(String productId) => iap.products[productId]?.price ?? '';
  bool _ownedDeckLegacy(String deckId) => isProLegacy || ownedLegacy.contains(deckId);

  String _safePrice(String productId) {
    final p = _priceOf(productId);
    return p.isEmpty ? '…' : p;
    // 価格未取得は “…” を表示し、ボタンは無効にする（_buyButton内で制御）
  }

  Widget _purchasedChip() => const Chip(
    avatar: Icon(Icons.check_circle, size: 18, color: Colors.green),
    label: Text('購入済み', style: TextStyle(fontWeight: FontWeight.w600)),
  );

  // 購入ボタン（商品ごとに状態反映）
  Widget _buyButton(String productId) {
    final busyThis = busy && _pendingProductId == productId;
    final hasPrice = _priceOf(productId).isNotEmpty;
    return ElevatedButton(
      onPressed: (!busy && _pendingProductId == null && hasPrice) ? () => _buy(productId) : null,
      child: busyThis
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : const Text('購入'),
    );
  }

  @override
  void initState() {
    super.initState();
    // ChangeNotifier を購読して UI を即時更新（restore/purchase による所有変化を反映）
    _iapListener = () {
      if (mounted) setState(() {});
    };
    iap.addListener(_iapListener);
    _boot();
  }

  Future<void> _boot() async {
    try {
      await iap.init(); // ProductDetails取得 &（IapService側で）過去購入反映
      // 後方互換のためにローカルStoreも参照（いずれ削除可）
      isProLegacy = await PurchaseStore.getPro();
      ownedLegacy = (await PurchaseStore.getOwnedDeckIds()).toSet();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('購入情報の初期化に失敗しました: $e')));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    iap.removeListener(_iapListener);
    iap.dispose();
    super.dispose();
  }

  Future<void> _refreshOwnedLegacy() async {
    // 旧ローカルの後方互換表示用のみ更新（新ロジックは ChangeNotifier で反映済み）
    isProLegacy = await PurchaseStore.getPro();
    ownedLegacy = (await PurchaseStore.getOwnedDeckIds()).toSet();
    if (mounted) setState(() {});
  }

  Future<void> _buy(String productId) async {
    setState(() {
      busy = true;
      _pendingProductId = productId;
    });
    try {
      await iap.buy(productId);
      await _refreshOwnedLegacy();

      if (!mounted) return;

      // 解放内容の文言
      String unlocked;
      if (productId == 'bundle_all_unlock') {
        unlocked = '全単元が解放されました';
      } else if (productId == 'bundle_5decks_unlock') {
        unlocked = '5単元パックが解放されました';
      } else if (productId == 'pro_upgrade') {
        unlocked = 'Pro機能が有効になりました';
      } else if (productId.endsWith('_unlock')) {
        unlocked = '対象の単元が解放されました';
      } else {
        unlocked = '購入が反映されました';
      }

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('購入が完了しました'),
          content: Text(unlocked),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('購入に失敗しました: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          _pendingProductId = null;
        });
      }
    }
  }

  Future<void> _restore() async {
    // 復元時のみ全体オーバーレイを表示（購入中は対象ボタンだけスピナー）
    setState(() {
      busy = true;
      _pendingProductId = null;
    });
    try {
      await iap.restore();
      await _refreshOwnedLegacy();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('復元が完了しました'),
          content: const Text('過去の購入が反映されました。'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('復元に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  // 単元タイル（個別デッキ）
  ListTile _deckTile({required String deckId, required String title}) {
    final productId = '${deckId}_unlock';
    // 新ロジック（IapService）を最優先。念のため旧ロジックもORで併用（後方互換）。
    final bought = iap.isOwnedProduct(productId) || _ownedDeckLegacy(deckId);
    final price = _safePrice(productId);

    final titleRow = Row(
      children: [
        Expanded(child: Text(title)),
        if (bought) _purchasedChip(), // Chipはタイトル側のみ（trailingには出さない）
      ],
    );

    final isBusyThis = busy && _pendingProductId == productId;

    return ListTile(
      leading: Icon(bought ? Icons.lock_open : Icons.lock_outline),
      title: titleRow,
      subtitle: Text(bought ? '購入済' : price),
      trailing: (bought || isBusyThis) ? null : _buyButton(productId),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // バンドル/Pro 所有判定は IapService で一本化（旧ロジックは後方互換でOR可能）
    final owned5 = iap.isOwnedProduct('bundle_5decks_unlock');
    final ownedAll = iap.isOwnedProduct('bundle_all_unlock');
    final ownedPro = iap.isOwnedProduct('pro_upgrade') || isProLegacy; // 後方互換込み

    return Scaffold(
      appBar: AppBar(title: const Text('購入')),
      body: Stack(
        children: [
          ListView(
            children: [
              const ListTile(title: Text('アプリ内購入')),

              // 単元（必要に応じて動的生成に変更可）
              _deckTile(deckId: 'deck_m01', title: '現代社会と健康（上）'),
              _deckTile(deckId: 'deck_m02', title: '現代社会と健康（中）'),
              _deckTile(deckId: 'deck_m03', title: '現代社会と健康（下）'),
              _deckTile(deckId: 'deck_m04', title: '安全な社会生活'),
              _deckTile(deckId: 'deck_m05', title: '生涯を通じる健康（前半）'),
              _deckTile(deckId: 'deck_m06', title: '生涯を通じる健康（後半）'),
              _deckTile(deckId: 'deck_m07', title: '健康を支える環境づくり（前半）'),
              _deckTile(deckId: 'deck_m08', title: '健康を支える環境づくり（後半）'),

              const Divider(),

              // 5単元パック（Chipはタイトル右、trailingはボタンのみ）
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Row(
                  children: [
                    const Expanded(child: Text('5単元パック')),
                    if (owned5) _purchasedChip(),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(owned5 ? '購入済' : _safePrice('bundle_5decks_unlock')),
                    const SizedBox(height: 2),
                    const Text('人気の入門パック。まずはここから', style: TextStyle(fontSize: 12)),
                  ],
                ),
                trailing: (owned5 || (busy && _pendingProductId == 'bundle_5decks_unlock'))
                    ? null
                    : _buyButton('bundle_5decks_unlock'),
              ),

              // 全単元フル解放
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: Row(
                  children: [
                    const Expanded(child: Text('全単元フル解放')),
                    if (ownedAll) _purchasedChip(),
                  ],
                ),
                subtitle: Text(ownedAll ? '購入済' : _safePrice('bundle_all_unlock')),
                trailing: (ownedAll || (busy && _pendingProductId == 'bundle_all_unlock'))
                    ? null
                    : _buyButton('bundle_all_unlock'),
              ),

              const Divider(),

              // Pro アップグレード
              ListTile(
                leading: Icon(
                  ownedPro ? Icons.workspace_premium : Icons.workspace_premium_outlined,
                ),
                title: Row(
                  children: [
                    Expanded(child: Text(ownedPro ? 'Pro' : 'Proアップグレード')),
                    if (ownedPro) _purchasedChip(),
                  ],
                ),
                subtitle: Text(ownedPro ? '購入済' : _safePrice('pro_upgrade')),
                trailing: (ownedPro || (busy && _pendingProductId == 'pro_upgrade'))
                    ? null
                    : _buyButton('pro_upgrade'),
              ),

              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: busy ? null : _restore,
                  icon: const Icon(Icons.restore),
                  label: const Text('購入を復元'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),

          // 全体オーバーレイは「復元」時のみ（_pendingProductId == null）
          if (busy && _pendingProductId == null)
            Container(
              color: Colors.black.withOpacity(0.04),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
