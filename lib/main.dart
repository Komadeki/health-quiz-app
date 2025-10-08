// lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/foundation.dart'; // kDebugMode 用
import 'package:provider/provider.dart';
import 'models/deck.dart';
import 'services/deck_loader.dart';
import 'services/app_settings.dart';
import 'screens/multi_select_screen.dart';
import 'screens/unit_select_screen.dart';
import 'screens/scores_screen.dart'; 
import 'screens/settings_screen.dart';
import 'utils/logger.dart'; // AppLog を使うため

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ===== デバッグ検証 =====
  AppLog.enabled = true; // ← 一時ON（確認後は false やコメントアウトでOK）
  // await AttemptStore().clearAll(); // ← 使い終わったら必ずコメントアウト
  // AppLog.d('[DEBUG] AttemptStore cleared.');
  // await debugSmokeTestScoreStore();
  // =======================

  // ✅ AppSettingsの初期化を追加
  final settings = AppSettings();
  await settings.load();

  // ✅ Providerで包んで起動
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
    // ✅ AppSettingsを取得
    final s = context.watch<AppSettings>();

    return MaterialApp(
      title: '高校保健一問一答',
      locale: const Locale('ja', 'JP'),
      supportedLocales: const [Locale('ja', 'JP'), Locale('en')],
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],

      // ✅ テーマ関連を差し替え
      themeMode: s.themeMode, // ← ライト／ダーク切替に対応
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(1.0),
        ),
        child: child!,
      ),

      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
        fontFamily: 'NotoSansJP',
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.dark,
        ),
        fontFamily: 'NotoSansJP',
      ),

      routes: {
        '/': (_) => const HomeScreen(),
        '/settings': (_) => const SettingsScreen(),
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

  @override
  void initState() {
    super.initState();
    _loadDecks();
  }

  Future<void> _loadDecks() async {
    try {
      final loader = DeckLoader();
      final all = await loader.loadAll();
      setState(() {
        decks = all;
        loading = false;
        error = null;
      });
    } catch (e) {
      setState(() {
        error = e.toString();
        loading = false;
      });
    }
  }

  // ========== デバッグ用 購入フラグ切替 ==========
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
  // ==========================================

  void _openMultiSelect() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MultiSelectScreen(decks: decks)),
    );
  }

  void _openUnitSelect(Deck deck) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => UnitSelectScreen(deck: deck)),
    );
  }

  void _notImplemented(String title) {
    if (title == '設定') {
      Navigator.pushNamed(context, '/settings');
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$title は今後実装予定です')));
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
              onRefresh: _loadDecks,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.menu_book_outlined,
                        color: theme.colorScheme.primary,
                      ),
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
                  SizedBox(
                    height: 140,
                    child: decks.isEmpty
                        ? Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'デッキが見つかりません（assets/decks を確認）',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          )
                        : PageView.builder(
                            controller: PageController(viewportFraction: 1.0),
                            padEnds: false,
                            itemCount: (decks.length + 1) ~/ 2,
                            itemBuilder: (context, pageIndex) {
                              const spacing = 12.0;
                              final left = pageIndex * 2;
                              final right = left + 1;

                              final leftDeck = decks[left];
                              final rightDeck = (right < decks.length)
                                  ? decks[right]
                                  : null;

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
                                            isPurchased: rightDeck.isPurchased,
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
                  _DeckLikeButton(
                    leadingIcon: Icons.shuffle_outlined,
                    title: 'ミックス練習（複数単元・横断）',
                    subtitle: '選んだ単元をランダム出題',
                    onTap: _openMultiSelect,
                  ),
                  const SizedBox(height: 16),
                  const Divider(height: 32),

                  _MenuTile(
                    icon: Icons.query_stats_outlined,
                    label: '成績を見る',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ScoresScreen(), // ★ 新画面へ
                        ),
                      );
                    },
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

// ========== UIコンポーネントは既存のまま ==========

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
                  Icon(
                    Icons.menu_book_outlined,
                    size: 22,
                    color: theme.colorScheme.primary,
                  ),
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
                        Icon(
                          Icons.lock_open_rounded,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
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
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 18,
                          color: theme.colorScheme.outline,
                        ),
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
