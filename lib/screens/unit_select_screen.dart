// lib/screens/unit_select_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/deck.dart';
import '../models/unit.dart';
import '../models/card.dart';
import 'quiz_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _restorePrefs();
  }

  // ────── 永続化まわり ──────
  Future<void> _restorePrefs() async {
    final sp = await SharedPreferences.getInstance();
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
  }

  Future<void> _saveSelectedUnits() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_prefsKeySelectedUnits, _selectedUnitIds.toList());
  }

  Future<void> _saveQuestionLimit() async {
    final sp = await SharedPreferences.getInstance();
    if (_limit == null) {
      await sp.remove(_prefsKeyQuestionLimit);
    } else {
      await sp.setInt(_prefsKeyQuestionLimit, _limit!);
    }
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
    final available = _collectSelectedCards();
    if (available.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('選択範囲に出題可能な問題がありません')));
      return;
    }
    available.shuffle();
    final startCards = (_limit == null)
        ? available
        : available.take(_limit!).toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            QuizScreen(deck: widget.deck, overrideCards: startCards),
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
                    ? () {
                        // デバッグ出力（任意）
                        // ignore: avoid_print
                        print(
                          'start quiz: selectedUnitIds=$_selectedUnitIds, '
                          'available=${_collectSelectedCards().length}, '
                          'limit=$_limit',
                        );
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
          ),
        ],
      ),
    );
  }
}
