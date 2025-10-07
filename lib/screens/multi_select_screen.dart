// lib/screens/multi_select_screen.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';             // ← 追加
import '../services/app_settings.dart';              // ← 追加
import '../models/deck.dart';
import '../models/unit.dart';
import '../models/card.dart';
import 'quiz_screen.dart';

/// 複数デッキ・複数ユニットを横断選択してミックス出題
class MultiSelectScreen extends StatefulWidget {
  final List<Deck> decks;
  const MultiSelectScreen({super.key, required this.decks});

  @override
  State<MultiSelectScreen> createState() => _MultiSelectScreenState();
}

class _MultiSelectScreenState extends State<MultiSelectScreen> {
  /// deckId -> unitId の選択集合
  final Map<String, Set<String>> selected = {};

  // 永続化キー
  late final String _prefsKeyMultiSelected = 'multi.selected.v1';
  late final String _prefsKeyMultiLimit = 'multi.limit.v1';

  // 出題上限（null=制限なし）
  int? _limit;

  bool get hasSelection => selected.values.any((set) => set.isNotEmpty);

  // 設定の直近値（ON→OFFを検知して即リセットするため）
  bool _lastSaveUnitsOn = true;

  @override
  void initState() {
    super.initState();
    _restorePrefs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final saveOn = context.watch<AppSettings>().saveUnitSelection;
    if (_lastSaveUnitsOn && !saveOn) {
      // ON→OFF に切替 → その場で選択と上限をリセット
      setState(() {
        selected.clear();
        _limit = null;
      });
      // ignore: avoid_print
      print('🛑 MultiSelect: saveUnitSelection OFF → reset local selections & limit');
    }
    _lastSaveUnitsOn = saveOn;
  }

  // ================= 永続化 =================

  Future<void> _restorePrefs() async {
    final sp = await SharedPreferences.getInstance();
    final saveOn = Provider.of<AppSettings>(context, listen: false).saveUnitSelection;

    selected.clear();

    if (!saveOn) {
      // 保存OFF：常に未選択＋上限なしで開始。保存もロードもしない
      setState(() {
        _limit = null;
      });
      // ignore: avoid_print
      print('⏭️ MultiSelect: load skipped (OFF) → selections cleared, limit=null');
      return;
    }

    final jsonStr = sp.getString(_prefsKeyMultiSelected);
    final savedLimit = sp.getInt(_prefsKeyMultiLimit);

    if (jsonStr != null && jsonStr.isNotEmpty) {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      // 既存デッキ/ユニットに対してのみ復元
      for (final entry in map.entries) {
        final deckId = entry.key;
        final unitIds = List<String>.from(entry.value as List);
        final deck = widget.decks.where((d) => d.id == deckId);
        if (deck.isEmpty) continue;
        final valid = unitIds.where(
          (u) => deck.first.units.any((x) => x.id == u),
        );
        selected[deckId] = {...valid};
      }
    }

    _limit = savedLimit;
    if (mounted) setState(() {});
    // ignore: avoid_print
    print('📥 MultiSelect: load selected=${selected.map((k,v)=>MapEntry(k, v.length))}, limit=$_limit');
  }

  Future<void> _savePrefs() async {
    final saveOn = Provider.of<AppSettings>(context, listen: false).saveUnitSelection;
    if (!saveOn) {
      // ignore: avoid_print
      print('⏭️ MultiSelect: save skipped (OFF)');
      return;
    }
    final sp = await SharedPreferences.getInstance();
    final map = selected.map((k, v) => MapEntry(k, v.toList()));
    await sp.setString(_prefsKeyMultiSelected, jsonEncode(map));
    if (_limit == null) {
      await sp.remove(_prefsKeyMultiLimit);
    } else {
      await sp.setInt(_prefsKeyMultiLimit, _limit!);
    }
    // ignore: avoid_print
    print('📤 MultiSelect: saved selected=${selected.map((k,v)=>MapEntry(k, v.length))}, limit=$_limit');
  }

  // ================= 集計/ビルド =================

  /// 実際に出題できる件数（購入状態を考慮：未購入は無料のみ）
  int get _availableCount {
    int count = 0;
    for (final deck in widget.decks) {
      final unitIds = selected[deck.id];
      if (unitIds == null || unitIds.isEmpty) continue;

      final units = deck.units.where((u) => unitIds.contains(u.id));
      for (final u in units) {
        count += deck.isPurchased
            ? u.cards.length
            : u.cards.where((c) => !c.isPremium).length;
      }
    }
    return count;
  }

  /// ボタン表示用の件数（min(available, limit)）
  int get _startCount {
    if (_limit == null) return _availableCount;
    return _availableCount < _limit! ? _availableCount : _limit!;
  }

  /// ミックス用の集計：
  /// purchasedTotal …… 購入済みデッキから出題できる総数（無料/有料すべて）
  /// freeUnpurchased … 未購入デッキから出題できる無料数
  /// premiumUnpurchased … 未購入デッキの有料数（参考表示用）
  /// hasPurchased / hasUnpurchased … 状態フラグ
  ({
    int purchasedTotal,
    int freeUnpurchased,
    int premiumUnpurchased,
    bool hasPurchased,
    bool hasUnpurchased,
  })
  _countAllMixed() {
    int purchasedTotal = 0;
    int freeUnpurchased = 0;
    int premiumUnpurchased = 0;
    bool hasPurchased = false;
    bool hasUnpurchased = false;

    for (final deck in widget.decks) {
      final unitIds = selected[deck.id];
      if (unitIds == null || unitIds.isEmpty) continue;

      final cards = deck.units
          .where((u) => unitIds.contains(u.id))
          .expand((u) => u.cards);

      if (deck.isPurchased) {
        hasPurchased = true;
        purchasedTotal += cards.length;
      } else {
        hasUnpurchased = true;
        for (final c in cards) {
          if (c.isPremium) {
            premiumUnpurchased++;
          } else {
            freeUnpurchased++;
          }
        }
      }
    }

    return (
      purchasedTotal: purchasedTotal,
      freeUnpurchased: freeUnpurchased,
      premiumUnpurchased: premiumUnpurchased,
      hasPurchased: hasPurchased,
      hasUnpurchased: hasUnpurchased,
    );
  }

  /// カウンタの文言（混在ルール）
  ///
  /// - すべて購入済みのみ → 「選択中：合計X問」
  /// - すべて未購入のみ → 「選択中：X問（無料X / 有料Y）」 ※無料だけ出題
  /// - 混在 → 「選択中：X問（購入済みY + 無料Z）」
  String _counterLabel() {
    if (!hasSelection) return 'ユニットを選択してください';

    final c = _countAllMixed();
    final effectiveTotal = c.purchasedTotal + c.freeUnpurchased;

    if (c.hasPurchased && c.hasUnpurchased) {
      return '選択中：$effectiveTotal問（購入済み ${c.purchasedTotal} + 無料 ${c.freeUnpurchased}）';
    } else if (c.hasPurchased) {
      return '選択中：$effectiveTotal問';
    } else {
      // 全部未購入
      return '選択中：${c.freeUnpurchased}問（無料 ${c.freeUnpurchased} / 有料 ${c.premiumUnpurchased}）';
    }
  }

  /// 出題カードを作成（購入未購入考慮・上限適用）
  List<QuizCard> _buildCards() {
    final List<QuizCard> out = [];
    for (final deck in widget.decks) {
      final unitIds = selected[deck.id] ?? {};
      if (unitIds.isEmpty) continue;

      final units = deck.units.where((u) => unitIds.contains(u.id));
      for (final u in units) {
        out.addAll(
          deck.isPurchased ? u.cards : u.cards.where((c) => !c.isPremium),
        );
      }
    }
    // 出題順は QuizScreen 側で一本化（settings.randomize）して決定する。
    // ここではシャッフルしない。
    // out.shuffle();
    return (_limit == null) ? out : out.take(_limit!).toList();
  }

  // ================= トグル操作 =================

  void _toggleDeckAll(Deck deck, bool value) {
    setState(() {
      final set = selected.putIfAbsent(deck.id, () => <String>{});
      set.clear();
      if (value) {
        set.addAll(deck.units.map((e) => e.id));
      } else {
        selected.remove(deck.id);
      }
    });
    _savePrefs();
  }

  void _toggleUnit(Deck deck, Unit unit, bool value) {
    setState(() {
      final set = selected.putIfAbsent(deck.id, () => <String>{});
      if (value) {
        set.add(unit.id);
      } else {
        set.remove(unit.id);
        if (set.isEmpty) selected.remove(deck.id);
      }
    });
    _savePrefs();
  }

  void _toggleAll(bool select) {
    setState(() {
      selected.clear();
      if (select) {
        for (final d in widget.decks) {
          selected[d.id] = d.units.map((u) => u.id).toSet();
        }
      }
    });
    _savePrefs();
  }

  int _selectedUnitCount(Deck deck) => (selected[deck.id] ?? {}).length;

  // ================= 起動 =================

  void _startQuiz() {
    final all = _buildCards();
    if (all.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('選択範囲に出題可能な問題がありません')));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuizScreen(
          deck: Deck(
            id: 'mixed',
            title: 'ミックス練習',
            units: const [],
            isPurchased: true, // タイトル用の仮Deck。出題は overrideCards を使用
          ),
          overrideCards: all,
        ),
      ),
    );
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool canStart = hasSelection && _availableCount > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ミックス練習'),
        actions: [
          TextButton.icon(
            onPressed: () => _toggleAll(!hasSelection),
            icon: const Icon(Icons.select_all),
            label: Text(hasSelection ? 'すべて解除' : 'すべて選択'),
          ),
        ],
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: widget.decks.length,
        itemBuilder: (_, i) {
          final deck = widget.decks[i];
          final selCount = _selectedUnitCount(deck);
          final allSelected = selCount == deck.units.length && selCount > 0;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      deck.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Chip(
                    label: Text(deck.isPurchased ? '購入済み' : '一部無料'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              children: [
                // デッキ全選択/解除 行
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.only(left: 8, right: 4),
                    title: Text('この単元をすべて選択（${deck.units.length}ユニット）'),
                    value: allSelected,
                    onChanged: (v) => _toggleDeckAll(deck, v),
                  ),
                ),
                const Divider(height: 8),
                // ユニット一覧（チェック可）
                ...deck.units.map((u) {
                  final checked = selected[deck.id]?.contains(u.id) ?? false;

                  // 出題可能件数の簡易表示（購入状況による）
                  final total = u.cards.length;
                  final available = deck.isPurchased
                      ? total
                      : u.cards.where((c) => !c.isPremium).length;

                  return CheckboxListTile(
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(u.title),
                    subtitle: Text('出題可能: $available / 全$total'),
                    value: checked,
                    onChanged: (v) => _toggleUnit(deck, u, v ?? false),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // カウンタ + 上限ドロップダウン
            Row(
              children: [
                Icon(
                  Icons.quiz_outlined,
                  size: 20,
                  color: hasSelection
                      ? theme.colorScheme.primary
                      : theme.colorScheme.outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hasSelection ? _counterLabel() : 'ユニットを選択してください',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: hasSelection
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline,
                      fontWeight: hasSelection
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(Icons.tune, size: 18),
                const SizedBox(width: 6),
                DropdownButton<int?>(
                  value: _limit,
                  onChanged: (v) {
                    setState(() => _limit = v);
                    _savePrefs();
                  },
                  items: const [
                    DropdownMenuItem(value: null, child: Text('制限なし')),
                    DropdownMenuItem(value: 5, child: Text('5問')),
                    DropdownMenuItem(value: 10, child: Text('10問')),
                    DropdownMenuItem(value: 20, child: Text('20問')),
                    DropdownMenuItem(value: 50, child: Text('50問')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 開始ボタン（min 表示）
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canStart ? _startQuiz : null,
                child: Text(
                  hasSelection ? 'この選択で開始（$_startCount問）' : 'ユニットを選択してください',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
