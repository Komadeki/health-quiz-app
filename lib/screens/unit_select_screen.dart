// lib/screens/unit_select_screen.dart
import 'dart:math'; // ← 追加：均等配分やshuffleに利用
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart'; // ← 追加
import '../services/app_settings.dart'; // ← 追加
import '../services/gate.dart';
import '../models/deck.dart';
import '../models/unit.dart';
import '../models/card.dart';
import 'quiz_screen.dart';
import 'package:health_quiz_app/utils/logger.dart'; // ← 追加（AppLog）
import '../screens/purchase_screen.dart';

class UnitSelectScreen extends StatefulWidget {
  final Deck deck;
  const UnitSelectScreen({super.key, required this.deck});

  @override
  State<UnitSelectScreen> createState() => _UnitSelectScreenState();
}

class _UnitSelectScreenState extends State<UnitSelectScreen> {
  // 永続化キー（デッキ毎に独立）
  late final String _prefsKeySelectedUnits = 'selectedUnits.${widget.deck.id}';
  late final String _prefsKeyQuestionLimit = 'questionLimit.${widget.deck.id}';

  // 状態
  final Set<String> _selectedUnitIds = {}; // 選択中 unit.id
  int? _limit; // null=制限なし／数値=出題上限

  // 直近の設定値を記録（ON→OFF切替時の検知用）
  bool _lastSaveUnitsOn = true;

  @override
  void initState() {
    super.initState();
    _restorePrefs();
  }

  // 設定が変わったら即時反映（特に ON→OFF でリセット）
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final saveOn = context.watch<AppSettings>().saveUnitSelection;
    if (_lastSaveUnitsOn && !saveOn) {
      // ON→OFFに切り替わった瞬間：その場で選択をクリア＆上限を無効化
      setState(() {
        _selectedUnitIds.clear();
        _limit = null;
      });
      AppLog.d('🛑 UnitSelect: saveUnitSelection OFF → reset local selections');
    }
    _lastSaveUnitsOn = saveOn;
  }

  // ────── 永続化まわり ──────
  Future<void> _restorePrefs() async {
    final saveOn = context.read<AppSettings>().saveUnitSelection; // await前に読む
    final sp = await SharedPreferences.getInstance();
    if (!mounted) return;

    if (!saveOn) {
      // 保存OFF：常に未選択＋上限なし（null）から開始。読み込みもしない
      setState(() {
        _selectedUnitIds.clear();
        _limit = null;
      });
      AppLog.d(
        '⏭️ UnitSelect: load skipped (OFF) → cleared selections & limit=null',
      );
      return;
    }

    final savedUnits = sp.getStringList(_prefsKeySelectedUnits) ?? [];
    final savedLimit = sp.getInt(_prefsKeyQuestionLimit); // なければ null

    setState(() {
      _selectedUnitIds
        ..clear()
        ..addAll(
          savedUnits.where((id) => widget.deck.units.any((u) => u.id == id)),
        );
      _limit = savedLimit; // null なら制限なし
    });

    AppLog.d(
      '📥 UnitSelect: load units=$_selectedUnitIds, limit=$_limit (deck=${widget.deck.id})',
    );
  }

  Future<void> _saveSelectedUnits() async {
    final saveOn = Provider.of<AppSettings>(
      context,
      listen: false,
    ).saveUnitSelection;
    if (!saveOn) {
      AppLog.d('⏭️ UnitSelect: save skipped (OFF)');
      return;
    }
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_prefsKeySelectedUnits, _selectedUnitIds.toList());
    AppLog.d(
      '📤 UnitSelect: saved units=$_selectedUnitIds (deck=${widget.deck.id})',
    );
  }

  Future<void> _saveQuestionLimit() async {
    final saveOn = Provider.of<AppSettings>(
      context,
      listen: false,
    ).saveUnitSelection;
    if (!saveOn) {
      AppLog.d('⏭️ UnitSelect: limit save skipped (OFF)');
      return;
    }
    final sp = await SharedPreferences.getInstance();
    if (_limit == null) {
      await sp.remove(_prefsKeyQuestionLimit);
    } else {
      await sp.setInt(_prefsKeyQuestionLimit, _limit!);
    }
    AppLog.d('📤 UnitSelect: saved limit=$_limit (deck=${widget.deck.id})');
  }

  // ────── 集計/表示ヘルパー ──────

  // 選択ユニットのカード（購入状況でフィルタ）を収集
  List<QuizCard> _collectSelectedCards() {
    final selectedUnits = widget.deck.units.where(
      (u) => _selectedUnitIds.contains(u.id),
    );
    final all = selectedUnits.expand((u) => u.cards).toList();
    if (widget.deck.isPurchased) return all;
    return all.where((c) => !c.isPremium).toList();
  }

  // 素の内訳（無料/有料）を数える
  ({int free, int premium}) _rawBreakdown() {
    final selectedUnits = widget.deck.units.where(
      (u) => _selectedUnitIds.contains(u.id),
    );
    final all = selectedUnits.expand((u) => u.cards);
    final free = all.where((c) => !c.isPremium).length;
    final premium = all.where((c) => c.isPremium).length;
    return (free: free, premium: premium);
  }

  // カウンタ表示文言
  String _counterLabel() {
    final b = _rawBreakdown();
    if (widget.deck.isPurchased) {
      return '選択中：${b.free + b.premium}問';
    } else {
      return '選択中：${b.free}問（無料 ${b.free} / 有料 ${b.premium}）';
    }
  }

  // 実際に開始できる問題数（購入状態＋上限を考慮）
  int get _startCount {
    final b = _rawBreakdown();
    final base = widget.deck.isPurchased ? (b.free + b.premium) : b.free;
    if (_limit == null) return base;
    return base < _limit! ? base : _limit!;
  }

  bool get _canStart => _selectedUnitIds.isNotEmpty && _startCount > 0;

  // ────── 出題カード構築（均等配分＋無料制限＋不足補完＋全体シャッフル）──────
  List<QuizCard> _buildCards() {
    // ランダム設定を一度だけ取得
    final rnd = context.read<AppSettings>().randomize;

    final selectedUnits = widget.deck.units
        .where((u) => _selectedUnitIds.contains(u.id))
        .toList();
    if (selectedUnits.isEmpty) return [];

    // 各ユニットのカードを取得（購入状況で制限）
    final pools = <List<QuizCard>>[];
    final poolNames = <String>[];
    for (final u in selectedUnits) {
      final pool = widget.deck.isPurchased
          ? u.cards.toList()
          : u.cards.where((c) => !c.isPremium).toList();
      if (rnd) {
        pool.shuffle();
      }
      pools.add(pool);
      poolNames.add(u.title);
    }

    // 制限なしなら全問シャッフル
    if (_limit == null) {
      final all = pools.expand((x) => x).toList();
      if (rnd) {
        all.shuffle();
      }
      AppLog.d('🎲 UnitSelect (no-limit) summary:');
      for (int i = 0; i < pools.length; i++) {
        AppLog.d('  ${poolNames[i]}: ${pools[i].length}問');
      }
      AppLog.d('  → total=${all.length} (limit=∞)');
      return all;
    }

    final limit = _limit!;
    final unitCount = pools.length;
    final base = (limit / unitCount).floor();
    int remainder = limit % unitCount;
    final rand = Random();
    final order = List<int>.generate(unitCount, (i) => i);
    if (rnd) {
      order.shuffle(rand);
    }
    final picked = <QuizCard>[];
    final perUnitPicked = <int>[...List.filled(unitCount, 0)];
    final remainderAssigned = <bool>[...List.filled(unitCount, false)];

    for (final i in order) {
      final pool = pools[i];
      if (pool.isEmpty) continue;

      final extra = (remainder > 0) ? 1 : 0;
      if (remainder > 0) {
        remainder--;
        remainderAssigned[i] = true;
      }
      final takeCount = min(base + extra, pool.length);
      picked.addAll(pool.take(takeCount));
      perUnitPicked[i] = takeCount;
    }

    // 不足補完
    if (picked.length < limit) {
      final backfill = <QuizCard>[];
      for (int i = 0; i < pools.length; i++) {
        final used = perUnitPicked[i];
        if (used < pools[i].length) {
          backfill.addAll(pools[i].skip(used));
        }
      }
      if (rnd) {
        backfill.shuffle(rand);
      }
      final need = limit - picked.length;
      picked.addAll(backfill.take(need));
    }

    if (rnd) {
      picked.shuffle(rand);
    }

    // ログ出力
    AppLog.d('🎲 UnitSelect build summary (limit=$limit):');
    for (int i = 0; i < pools.length; i++) {
      final extraFlag = remainderAssigned[i] ? ' (+1配分)' : '';
      AppLog.d('  ${poolNames[i]}: ${perUnitPicked[i]}問$extraFlag (pool=${pools[i].length})');
    }
    AppLog.d('  → total=${picked.length}');

    return picked;
  }

  // ────── UIイベント ──────
  void _toggleUnit(Unit u) {
    setState(() {
      if (_selectedUnitIds.contains(u.id)) {
        _selectedUnitIds.remove(u.id);
      } else {
        _selectedUnitIds.add(u.id);
      }
    });
    _saveSelectedUnits();
  }

  void _toggleAll() {
    final isAll = _selectedUnitIds.length == widget.deck.units.length;
    setState(() {
      _selectedUnitIds
        ..clear()
        ..addAll(isAll ? <String>{} : widget.deck.units.map((u) => u.id));
    });
    _saveSelectedUnits();
  }

  void _startQuiz() {
    final cards = _buildCards();
    if (cards.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('選択範囲に出題可能な問題がありません')));
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>QuizScreen(
          deck: widget.deck,
          overrideCards: cards,
          selectedUnitIds: _selectedUnitIds.toList(),
          limit: _limit ?? cards.length,
        ),
      ),
    );
  }

  // ────── Build ──────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = widget.deck.units;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.deck.title} のユニット選択'),
        actions: [
          TextButton.icon(
            onPressed: _toggleAll,
            icon: Icon(
              _selectedUnitIds.length == units.length
                  ? Icons.check_box_outline_blank
                  : Icons.select_all,
            ),
            label: Text(
              _selectedUnitIds.length == units.length ? 'すべて解除' : 'すべて選択',
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              '出題したいユニットを選択してください（複数可）',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),

          // ユニット一覧
          Expanded(
            child: ListView.builder(
              itemCount: units.length,
              itemBuilder: (_, i) {
                final u = units[i];
                final checked = _selectedUnitIds.contains(u.id);
                return CheckboxListTile(
                  title: Text(u.title),
                  value: checked,
                  onChanged: (_) => _toggleUnit(u),
                );
              },
            ),
          ),

          // カウンタ + 出題数上限
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                if (_selectedUnitIds.isEmpty) ...[
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'ユニットを選択してください',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ] else ...[
                  Icon(
                    Icons.quiz_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _counterLabel(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 12),
                const Icon(Icons.tune, size: 18),
                const SizedBox(width: 6),
                DropdownButton<int?>(
                  value: _limit,
                  onChanged: (v) {
                    setState(() => _limit = v);
                    _saveQuestionLimit();
                  },
                  items: const [
                    DropdownMenuItem(value: null, child: Text('制限なし')),
                    DropdownMenuItem(value: 5, child: Text('5問')),
                    DropdownMenuItem(value: 10, child: Text('10問')),
                    DropdownMenuItem(value: 20, child: Text('20問')),
                    DropdownMenuItem(value: 50, child: Text('50問')),
                    DropdownMenuItem(value: 100, child: Text('100問')),
                  ],
                ),
              ],
            ),
          ),

          // 開始ボタン
          SafeArea(
            minimum: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canStart
                    ? () async {
                        AppLog.d(
                          'start quiz: selectedUnitIds=$_selectedUnitIds, limit=$_limit',
                        );

                        // 🧩 Gate制御（フェイルセーフ）
                        final deckOk = await Gate.canAccessDeck(widget.deck.id);

                        // いま選ばれているユニットの中に isPremium なカードが含まれるか？（簡易判定）
                        final units = widget.deck.units;
                        final hasPremium = _selectedUnitIds.any((uid) {
                          final u = units.firstWhere((x) => x.id == uid);
                          return u.cards.any((c) => c.isPremium == true);
                        });

                        if (!deckOk && hasPremium) {
                          final go = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('有料カードが含まれています'),
                              content: const Text('購入すると全カードが解放されます。無料カードのみで続けることもできます。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('無料だけで続ける'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('購入へ進む'),
                                ),
                              ],
                            ),
                          );

                          if (go == true) {
                            if (!context.mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => PurchaseScreen()), // ← const を付けない
                            );
                            return;
                          }

                          // 「無料だけで続ける」：現状は無料カードのみ想定なので何もせず続行
                          // （将来"一部無料"運用に変えるなら、この場で有料カードを除外する処理を追加）
                        }

                        // ✅ ここまで来たら開始OK（既存の開始処理を呼ぶ）
                        _startQuiz();
                      }
                    : null,
                child: Text(
                  _selectedUnitIds.isEmpty
                      ? 'この選択で開始'
                      : 'この選択で開始（$_startCount問）',
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
