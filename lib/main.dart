// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kDebugMode
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'models/deck.dart';
import 'services/deck_loader.dart';
import 'services/app_settings.dart';
import 'screens/multi_select_screen.dart';
import 'screens/unit_select_screen.dart';
import 'screens/scores_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/quiz_screen.dart';
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

  // ★ 追加：安定ID式のバージョン移行（古いセッションを安全にクリア）
  final prefs = await SharedPreferences.getInstance();
  await QuizSessionLocalRepository(prefs).migrateIfNeeded();

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
<<<<<<< HEAD
      themeMode: s.themeMode,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        // AppSettings（s）から倍率を反映
=======

      // ✅ テーマ関連を差し替え
      themeMode: s.themeMode, // ← ライト／ダーク切替に対応
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final s = context.watch<AppSettings>(); // 設定の textScaleFactor を適用
>>>>>>> origin/main
        return MediaQuery(
          data: mq.copyWith(
            textScaler: TextScaler.linear(s.textScaleFactor),
          ),
          child: child!,
        );
      },
<<<<<<< HEAD
=======

>>>>>>> origin/main
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
      final all = await DeckLoader().loadAll();
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
          list = await DeckLoader().loadAll();
          AppLog.d('[RESUME] decks reloaded for resume: ${list.length}');
        } catch (e) {
          AppLog.d('[RESUME] deck reload failed: $e');
        }
      }

      // 👇 mixed でもブロックしない
      Deck? deck;
      if (active.deckId == 'mixed') {
        // タイトル表示用の仮デッキ（実データ復元は QuizScreen 側がやる）
        deck = (list.isNotEmpty)
            ? list.first
            : Deck(id: 'mixed', title: 'ミックス練習', units: const [], isPurchased: true);
      } else {
        // 通常デッキは ID で検索
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
                                          onTap: () => _openUnitSelect(leftDeck),
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
                                                    _openUnitSelect(rightDeck),
                                              ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),

                      const SizedBox(height: 24),

                      // ミックス練習
                      _DeckLikeButton(
                        leadingIcon: Icons.shuffle_outlined,
                        title: 'ミックス練習（複数単元・横断）',
                        subtitle: '選んだ単元をランダム出題',
                        onTap: _openMultiSelect,
                      ),

                      const SizedBox(height: 16),

                      // 続きからボタン（有効時のみ）
                      
                      if (_canResume)
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.tonalIcon(
                            icon: _isResuming
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.play_circle_fill),
                            label: Text(_isResuming ? '開いています…' : '続きから再開'),
                            onPressed: _isResuming ? null : _resumeIfExists,
                          ),
                        ),

                      const SizedBox(height: 24),

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
                        onTap: () => _notImplemented('購入'),
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

class _DeckLikeButton extends StatelessWidget {
  final IconData leadingIcon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _DeckLikeButton({
    required this.leadingIcon,
    required this.title,
    this.subtitle,
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
              offset: const Offset(0, 2),
              color: Colors.black.withValues(alpha: 0.06),
            ),
          ],
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.12),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(leadingIcon, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.shuffle_rounded, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
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
