import 'package:flutter/material.dart';
import '../services/iap_service.dart';
import '../services/purchase_store.dart';

class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen({super.key});
  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  final iap = IapService();

  bool loading = true; // 価格などProductDetailsロード中
  bool busy = false; // 購入/復元の進行中
  bool isPro = false;
  Set<String> owned = {};

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await iap.init(); // ← 価格(ProductDetails)が埋まる
      isPro = await PurchaseStore.isPro();
      owned = (await PurchaseStore.ownedDeckIds()).toSet();
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
    iap.dispose();
    super.dispose();
  }

  // ---- helpers ----
  String _priceOf(String productId) => iap.products[productId]?.price ?? '';
  bool _ownedDeck(String deckId) => isPro || owned.contains(deckId);

  Future<void> _refreshOwned() async {
    isPro = await PurchaseStore.isPro();
    owned = (await PurchaseStore.ownedDeckIds()).toSet();
    if (mounted) setState(() {});
  }

  Future<void> _buy(String productId) async {
    setState(() => busy = true);
    try {
      await iap.buy(productId);
      await _refreshOwned();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('購入が反映されました')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('購入に失敗しました: $e')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => busy = true);
    try {
      await iap.restore();
      await _refreshOwned();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('購入を復元しました')));
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
    final bought = _ownedDeck(deckId);
    final price = _priceOf(productId);
    return ListTile(
      leading: Icon(bought ? Icons.lock_open : Icons.lock_outline),
      title: Text(title),
      subtitle: Text(bought ? '購入済' : (price.isEmpty ? '' : price)),
      trailing: bought || busy
          ? null
          : TextButton(onPressed: () => _buy(productId), child: const Text('購入')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('購入')),
      body: Stack(
        children: [
          ListView(
            children: [
              const ListTile(title: Text('アプリ内購入')),

              // 単元（必要に応じて増やす／DeckLoaderから動的生成にしてもOK）
              _deckTile(deckId: 'deck_m01', title: '現代社会と健康（上）'),
              _deckTile(deckId: 'deck_m02', title: '現代社会と健康（中）'),
              _deckTile(deckId: 'deck_m03', title: '現代社会と健康（下）'),
              _deckTile(deckId: 'deck_m04', title: '安全な社会生活'),
              _deckTile(deckId: 'deck_m05', title: '生涯を通じる健康（前半）'),
              _deckTile(deckId: 'deck_m06', title: '生涯を通じる健康（後半）'),
              _deckTile(deckId: 'deck_m07', title: '健康を支える環境づくり（前半）'),
              _deckTile(deckId: 'deck_m08', title: '健康を支える環境づくり（後半）'),

              // _deckTile(deckId: 'deck_m09', title: 'スポーツの発祥と発展'),
              // _deckTile(deckId: 'deck_m10', title: '運動・スポーツの学び方'),
              // _deckTile(deckId: 'deck_m11', title: '豊かなスポーツライフの設計'),
              const Divider(),

              // セット／全体
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('5単元パック'),
                subtitle: Text(_priceOf('bundle_5decks_unlock')),
                trailing: busy
                    ? null
                    : TextButton(
                        onPressed: () => _buy('bundle_5decks_unlock'),
                        child: const Text('購入'),
                      ),
              ),
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: const Text('全単元フル解放'),
                subtitle: Text(_priceOf('bundle_all_unlock')),
                trailing: busy
                    ? null
                    : TextButton(
                        onPressed: () => _buy('bundle_all_unlock'),
                        child: const Text('購入'),
                      ),
              ),

              const Divider(),

              // Pro
              ListTile(
                leading: Icon(isPro ? Icons.workspace_premium : Icons.workspace_premium_outlined),
                title: Text(isPro ? 'Pro（購入済）' : 'Proアップグレード'),
                subtitle: Text(_priceOf('pro_upgrade')),
                trailing: isPro || busy
                    ? null
                    : TextButton(onPressed: () => _buy('pro_upgrade'), child: const Text('購入')),
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

          // 購入操作中の簡易オーバーレイ
          if (busy)
            Container(
              color: Colors.black.withOpacity(0.04),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}
