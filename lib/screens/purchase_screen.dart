// lib/screens/purchase_screen.dart
import 'package:flutter/material.dart';
import '../services/iap_service.dart';
import '../services/purchase_store.dart';
import '../services/deck_loader.dart';

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

  /// JSONから動的に読み込むための表示用キャッシュ（productId側=小文字キー）
  Map<String, List<String>> _deckUnitTitles = {};

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

  // 追加: 小単元プレビューを1行に整形（最大4件 + 「+N件」）
  String? _unitPreview(List<String> units) {
    if (units.isEmpty) return null;
    const max = 5;
    final shown = units.take(max).toList();
    final rest = units.length - shown.length;
    final base = shown.join('／');
    return rest > 0 ? '$base／+${rest}件' : base;
  }

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
      // ✅ 追加：assets/decks/deck_M01.json 等から小単元名を動的取得
      // DeckLoaderはJSON上のID（例：deck_M01 / deck_M02 ...）。IAPのproductIdは deck_m01（小文字）。
      // 読み取り後に小文字キーへ正規化して `_deckUnitTitles` に格納する。
      final loader = await DeckLoader.instance();
      const assetDeckIds = [
        'deck_M01',
        'deck_M02',
        'deck_M03',
        'deck_M04',
        'deck_M05',
        'deck_M06',
        'deck_M07',
        'deck_M08',
      ];
      final metaMap = await loader.unitTitlesFor(assetDeckIds);
      _deckUnitTitles = {
        for (final e in metaMap.entries) e.key.toLowerCase(): e.value,
      };
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
      // 1) 購入フロー開始（IapService 側で purchaseStream を購読/完了処理）
      await iap.buy(productId);

      // 2) 旧ローカル互換の表示だけ更新（不要なら削除可）
      await _refreshOwnedLegacy();

      if (!mounted) return;

      // 3) 成功判定：本当に「所有状態になっているか」を確認
      final purchasedNow =
          iap.isOwnedProduct(productId) || _ownedDeckLegacy(productId.replaceAll('_unlock', ''));

      if (purchasedNow) {
        // ✅ ここで初めて成功ダイアログを出す（＝キャンセル時は出ない）
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
      } else {
        // ❌ 所有状態でなければ「キャンセル or 失敗 or ペンディング」扱い（通知しない）
      }
    } catch (e) {
      if (!mounted) return;
      // 例外＝明確なエラーのみ通知（キャンセル時は IAP 側で例外を投げない前提）
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('購入に失敗しました: $e')));
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
    // 復元時のみ全体オーバーレイを表示（_pendingProductId == null）
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

    // --- 変更点: subtitle を Column にして「含まれる小単元」を追記 ---
    final unitLine = _unitPreview(_deckUnitTitles[deckId] ?? const []);
    final subtitle = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(bought ? '購入済' : price),
        if (unitLine != null) ...[
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2, right: 4),
                child: Icon(Icons.menu_book, size: 14),
              ),
              Expanded(
                child: Text(
                  '単元構成：$unitLine',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ],
    );

    return ListTile(
      leading: Icon(bought ? Icons.lock_open : Icons.lock_outline),
      title: titleRow,
      subtitle: subtitle,
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

              // 5単元パック（文言は現状維持＋既存サブを残す）
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

              // 全単元フル解放（ポジティブ表現を追加）
              ListTile(
                leading: const Icon(Icons.school_outlined),
                title: Row(
                  children: [
                    const Expanded(child: Text('全単元フル解放（学び放題）')),
                    if (ownedAll) _purchasedChip(),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ownedAll ? '購入済' : _safePrice('bundle_all_unlock')),
                    const SizedBox(height: 2),
                    const Text(
                      'すべてのデッキ・小単元が勉強し放題。ミックス練習・見直し・復習テストも範囲の制限なし。',
                      style: TextStyle(fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      '進捗・履歴の学習データも一元管理できます。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                trailing: (ownedAll || (busy && _pendingProductId == 'bundle_all_unlock'))
                    ? null
                    : _buyButton('bundle_all_unlock'),
              ),

              const Divider(),

              // Pro アップグレード（何ができるかを明示）
              ListTile(
                leading: Icon(
                  ownedPro ? Icons.workspace_premium : Icons.workspace_premium_outlined,
                ),
                title: Row(
                  children: [
                    Expanded(child: Text(ownedPro ? 'Pro' : 'Proアップグレード（学習サポート強化）')),
                    if (ownedPro) _purchasedChip(),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ownedPro ? '購入済' : _safePrice('pro_upgrade')),
                    const SizedBox(height: 2),
                    const Text('・復習リマインダー（1/3/7/14/30日など）', style: TextStyle(fontSize: 12)),
                    const Text('・見直し／復習テストの詳細設定（範囲・期間・頻度）', style: TextStyle(fontSize: 12)),
                    const Text('・スコア／履歴の高度なフィルタ', style: TextStyle(fontSize: 12)),
                    // 実装済みの追加要素があればここに行を足す
                  ],
                ),
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
