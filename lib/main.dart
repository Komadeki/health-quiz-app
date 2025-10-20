// lib/main.dart
import 'dart:async'; // ← 非同期ユーティリティ用（unawaited, microtask 等）

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kDebugMode
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'models/deck.dart';
import 'services/deck_loader.dart';
import 'services/app_settings.dart';
import 'services/gate.dart';

import 'screens/multi_select_screen.dart';
import 'screens/unit_select_screen.dart';
import 'screens/scores_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/quiz_screen.dart';
import 'screens/review_menu_screen.dart'; // ← 先頭の import 群に追加
import 'screens/purchase_screen.dart';

import 'utils/logger.dart';

// 続きから用
import 'package:shared_preferences/shared_preferences.dart';
import 'data/quiz_session_local_repository.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 必要ならログをON
  AppLog.enabled = true;

  // AppSettings 初期化
  final settings = AppSettings();
  await settings.load();

  // ★安定ID式のバージョン移行（古いセッションを安全にクリア）
  final prefs = await SharedPreferences.getInstance();

  // ⚙️ 改善点① migrateIfNeededをmicrotaskで非同期遅延実行（UIブロック防止）
  unawaited(Future.microtask(() async {
    await QuizSessionLocalRepository(prefs).migrateIfNeeded();
  }));

  // ⚙️ 改善点② DeckLoaderの初期化を遅延バックグラウンド実行（compute負荷を分散）
  Future.delayed(const Duration(milliseconds: 500), () {
    DeckLoader.instance();
  });

  // ここからrunApp（UI優先）
  runApp(
    ChangeNotifierProvider(
      create: (_) => settings,
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();

    return MaterialApp(
      title: '高校保健一問一答',
      locale: const Locale('ja', 'JP'),
      supportedLocales: const [Locale('ja', 'JP'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // ✅ テーマ関連：ライト/ダーク切替＋文字倍率反映
      themeMode: s.themeMode,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // AppSettings の textScaleFactor を適用
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(s.textScaleFactor),
          ),
          child: child!,
        );
      },

      theme: ThemeData(
        useMaterial3: true,
        colorScheme:
            ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.light),
        fontFamily: 'NotoSansJP',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme:
            ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.dark),
        fontFamily: 'NotoSansJP',
      ),
      routes: {
        '/': (_) => const HomeScreen(),
        '/settings': (_) => const SettingsScreen(),

        // ★ 追加：/quiz ルート（将来の引数受け取りに備えた登録）
        // いまは直接 MaterialPageRoute でも可。順次こちらに寄せる想定。
        // 例）Navigator.pushNamed(context, '/quiz', arguments: QuizScreenArgs(...));
      },
      initialRoute: '/',
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool loading = true;
  String? error;
  List<Deck> decks = [];

  // 続きから制御
  bool _isResuming = false; // 多重タップ防止
  bool _canResume = false;  // ボタン表示制御

  @override
  void initState() {
    super.initState();
    _loadDecks();
    _checkResume(); // 起動時に一度チェック
  }

  Future<void> _loadDecks() async {
    try {
      // 🔸 修正版：DeckLoader.instance() を await で取得（UIブロックしない）
      final loader = await DeckLoader.instance();
      final all = await loader.loadAll();

      if (!mounted) return;
      setState(() {
        decks = all;
        loading = false;
        error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  // ===== デバッグ用：購入フラグ切り替え =====
  void _setAllPurchased(bool value) {
    setState(() {
      decks = decks.map((d) => d.copyWith(isPurchased: value)).toList();
    });
  }

  void _setFirstOnlyPurchased() {
    if (decks.isEmpty) return;
    setState(() {
      decks = [
        decks.first.copyWith(isPurchased: true),
        ...decks.skip(1).map((d) => d.copyWith(isPurchased: false)),
      ];
    });
  }

  void _setAlternatePurchased() {
    setState(() {
      decks = [
        for (int i = 0; i < decks.length; i++)
          decks[i].copyWith(isPurchased: i.isEven),
      ];
    });
  }
  // ===================================

  Future<void> _openMultiSelect() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MultiSelectScreen(decks: decks)),
    );
    if (mounted) _checkResume();
  }

  // ← ソフトゲート付きのラッパー関数
  Future<void> _openUnitSelectSoft(Deck deck) async {
    final ok = await Gate.canAccessDeck(deck.id);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('一部無料で体験できます。全カード解放は「購入」から。'),
        ),
      );
    }
    _openUnitSelect(deck); // 既存の遷移関数をそのまま利用
  }

  Future<void> _openUnitSelect(Deck deck) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UnitSelectScreen(deck: deck)),
    );
    if (mounted) _checkResume();
  }

  void _notImplemented(String title) {
    if (title == '設定') {
      Navigator.pushNamed(context, '/settings');
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$title は今後実装予定です')));
  }

  // 起動／復帰時に「続きから」可能かチェック
  Future<void> _checkResume() async {
    if (_isResuming) return; // 遷移中は覗かない
    final prefs = await SharedPreferences.getInstance();
    final repo = QuizSessionLocalRepository(prefs);
    await repo.migrateIfNeeded(); // ← これを追加
    final active = await repo.loadActive();
    AppLog.d('[RESUME] probe: ${active == null ? "none" : "exists"}');
    if (!mounted) return;
    setState(() => _canResume = active != null);
  }

  // 「続きから」押下時
  Future<void> _resumeIfExists() async {
    if (_isResuming) return;
    setState(() => _isResuming = true);
    AppLog.d('[RESUME] tapped resume button');

    try {
      final prefs = await SharedPreferences.getInstance();
      final repo = QuizSessionLocalRepository(prefs);
      final active = await repo.loadActive();

      AppLog.d('[RESUME/PROBE] deck=${active?.deckId} '
          'idx=${active?.currentIndex} len=${active?.itemIds.length} '
          'units=${active?.selectedUnitIds} limit=${active?.limit} '
          'choiceOrders=${active?.choiceOrders?.length}');

      if (active == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('再開できるセッションはありません')),
          );
        }
        setState(() => _isResuming = false);
        return;
      }

      // デッキ一覧が空なら再ロード（見た目用に1つ渡すだけ）
      var list = decks;
      if (list.isEmpty) {
        try {
          final loader = await DeckLoader.instance();
          list = await loader.loadAll();
          AppLog.d('[RESUME] decks reloaded for resume: ${list.length}');
        } catch (e) {
          AppLog.d('[RESUME] deck reload failed: $e');
        }
      }

      Deck? deck;
      if (active.deckId == 'mixed') {
        deck = (list.isNotEmpty)
            ? list.first
            : Deck(id: 'mixed', title: 'ミックス練習', units: const [], isPurchased: true);
      } else {
        try {
          deck = list.firstWhere((d) => d.id == active.deckId);
        } catch (_) {
          deck = null;
        }
        if (deck == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('対応するデッキが見つかりません（${active.deckId}）')),
            );
          }
          setState(() => _isResuming = false);
          return;
        }
        AppLog.d('[RESUME] navigate deck=${deck.id} len=${active.itemIds.length}');
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QuizScreen(
            deck: deck!,
            resumeSession: active, // ← ここが肝
          ),
        ),
      );
      AppLog.d('[RESUME] returned from QuizScreen');
    } finally {
      if (mounted) {
        setState(() => _isResuming = false);
        _checkResume();
      }
    }
  }

  // ======= build 以下は変更なし =======
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('高校保健一問一答'),
        actions: [
          if (kDebugMode)
            PopupMenuButton<String>(
              tooltip: '購入状態を切り替え',
              icon: const Icon(Icons.lock_outline),
              onSelected: (v) {
                switch (v) {
                  case 'all_on':
                    _setAllPurchased(true);
                    break;
                  case 'all_off':
                    _setAllPurchased(false);
                    break;
                  case 'first_on':
                    _setFirstOnlyPurchased();
                    break;
                  case 'alt':
                    _setAlternatePurchased();
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'all_on', child: Text('すべて購入にする')),
                PopupMenuItem(value: 'all_off', child: Text('すべて未購入にする')),
                PopupMenuItem(value: 'first_on', child: Text('先頭だけ購入にする（混在）')),
                PopupMenuItem(value: 'alt', child: Text('交互に購入にする（混在）')),
              ],
            ),
        ],
      ),

      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      '読み込みエラー: $error',
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    await _loadDecks();
                    await _checkResume();
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [
                      Row(
                        children: [
                          Icon(Icons.menu_book_outlined,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Text(
                            '単元を選ぶ',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // デッキ一覧
                      SizedBox(
                        height: 140,
                        child: decks.isEmpty
                            ? Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    'デッキが見つかりません（assets/decks を確認）',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium,
                                  ),
                                ),
                              )
                            : PageView.builder(
                                controller:
                                    PageController(viewportFraction: 1.0),
                                padEnds: false,
                                itemCount: (decks.length + 1) ~/ 2,
                                itemBuilder: (context, pageIndex) {
                                  const spacing = 12.0;
                                  final left = pageIndex * 2;
                                  final right = left + 1;

                                  final leftDeck = decks[left];
                                  final rightDeck =
                                      (right < decks.length) ? decks[right] : null;

                                  return Row(
                                    children: [
                                      Expanded(
                                        child: _DeckTile(
                                          title: leftDeck.title,
                                          isPurchased: leftDeck.isPurchased,
                                          onTap: () => _openUnitSelectSoft(leftDeck),
                                        ),
                                      ),
                                      const SizedBox(width: spacing),
                                      Expanded(
                                        child: rightDeck == null
                                            ? const SizedBox.shrink()
                                            : _DeckTile(
                                                title: rightDeck.title,
                                                isPurchased:
                                                    rightDeck.isPurchased,
                                                onTap: () =>
                                                    _openUnitSelectSoft(rightDeck),
                                              ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),

                      const SizedBox(height: 24),

                      // ミックス練習（＝単元カードと同じ見た目）
                      _DeckLikeButton(
                        leadingIcon: Icons.shuffle_outlined,
                        title: 'ミックス練習（複数単元・横断）',
                        subtitle: '選んだ単元をランダム出題',
                        onTap: _openMultiSelect,
                        style: DeckButtonStyle.normal,
                      ),

                      const SizedBox(height: 16),

                      // 続きから再開（形は同じカード、色だけ淡グリーン）
                      if (_canResume)
                        _DeckLikeButton(
                          leadingIcon: Icons.play_circle_fill,
                          title: _isResuming ? '開いています…' : '続きから再開',
                          subtitle: '前回の続きからクイズを再開',
                          onTap: _isResuming ? null : _resumeIfExists,
                          trailing: _isResuming
                              ? const SizedBox(
                                  width: 18, height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : null,
                          style: DeckButtonStyle.tonal,
                        ),

                      if (_canResume) const SizedBox(height: 16),

                      // 復習（＝単元カードと同じ見た目）
                      _DeckLikeButton(
                        leadingIcon: Icons.refresh,
                        title: '復習',
                        subtitle: '間違えた問題の見直し・復習テスト',
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const ReviewMenuScreen()),
                          );
                        },
                        style: DeckButtonStyle.normal,
                      ),

                      const Divider(height: 32),




                      _MenuTile(
                        icon: Icons.query_stats_outlined,
                        label: '成績を見る',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ScoresScreen(),
                          ),
                        ),
                      ),
                      _MenuTile(
                        icon: Icons.settings_outlined,
                        label: '設定',
                        onTap: () => _notImplemented('設定'),
                      ),
                      _MenuTile(
                        icon: Icons.shopping_bag_outlined,
                        label: '購入',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => PurchaseScreen()),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

// ======= 共通 UI パーツ =======

class _DeckTile extends StatelessWidget {
  final String title;
  final bool isPurchased;
  final VoidCallback onTap;
  const _DeckTile({
    required this.title,
    required this.isPurchased,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              blurRadius: 8,
              spreadRadius: 1,
              offset: const Offset(0, 2),
              color: Colors.black.withValues(alpha: 0.06),
            ),
          ],
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.menu_book_outlined,
                      size: 22, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isPurchased)
                    Row(
                      children: [
                        Icon(Icons.lock_open_rounded,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          '購入済み',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            size: 18, color: theme.colorScheme.outline),
                        const SizedBox(width: 6),
                        Text(
                          '一部無料',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.outline,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum DeckButtonStyle { normal, tonal }

class _DeckLikeButton extends StatelessWidget {
  final IconData leadingIcon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final DeckButtonStyle style;

  const _DeckLikeButton({
    super.key,
    required this.leadingIcon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.style = DeckButtonStyle.normal, // ← 既定：単元カードと同じ
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isTonal = style == DeckButtonStyle.tonal;

    // ✅ “単元カード”と同じ質感（surface色＋薄い枠＋やわらかい影）
    final BoxDecoration normalDecoration = BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: theme.colorScheme.outline.withOpacity(0.12)),
      boxShadow: const [
        BoxShadow(
          blurRadius: 12,
          offset: Offset(0, 2),
          color: Color(0x1A000000), // ~6% (0x1A) 黒のごく薄い影
        ),
      ],
    );

    // ✅ “続きから再開”用（淡いグリーンのトーナル、薄め＋軽い枠）
    final BoxDecoration tonalDecoration = BoxDecoration(
      // ← 色味を少し淡くするため、withOpacity(0.85)
      color: theme.colorScheme.primaryContainer.withOpacity(0.5),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        // ← ごく淡いグリーンの枠線（彩度控えめ）
        color: theme.colorScheme.primary.withOpacity(0.07),
        width: 1.0,
      ),
      boxShadow: const [
        BoxShadow(
          blurRadius: 10,
          offset: Offset(0, 2),
          color: Color(0x12000000), // 透明度約7%のやわらかい影
        ),
      ],
    );

    final decoration = isTonal ? tonalDecoration : normalDecoration;

    final Color iconColor =
        isTonal ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.primary;
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: isTonal ? theme.colorScheme.onPrimaryContainer : null,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: isTonal ? theme.colorScheme.onPrimaryContainer.withOpacity(0.8) : null,
    );

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Ink(
        decoration: decoration,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(leadingIcon, size: 24, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: titleStyle),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(subtitle!, style: subtitleStyle),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}



class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(icon, color: theme.colorScheme.primary),
        title: Text(
          label,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
