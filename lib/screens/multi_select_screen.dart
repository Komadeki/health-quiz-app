import 'package:flutter/material.dart';
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

  bool get hasSelection =>
      selected.values.any((set) => set.isNotEmpty);

  /// 現在の選択から出題カードを作る（購入状況も考慮）
  List<QuizCard> _buildCards() {
    final List<QuizCard> out = [];
    for (final deck in widget.decks) {
      final unitIds = selected[deck.id] ?? {};
      if (unitIds.isEmpty) continue;

      final units = deck.units.where((u) => unitIds.contains(u.id));
      for (final u in units) {
        out.addAll(
          deck.isPurchased
              ? u.cards
              : u.cards.where((c) => !c.isPremium),
        );
      }
    }
    out.shuffle();
    return out;
  }

  void _toggleDeckAll(Deck deck, bool value) {
    setState(() {
      final set = selected.putIfAbsent(deck.id, () => <String>{});
      set.clear();
      if (value) {
        set.addAll(deck.units.map((e) => e.id));
      }
    });
  }

  void _toggleUnit(Deck deck, Unit unit, bool value) {
    setState(() {
      final set = selected.putIfAbsent(deck.id, () => <String>{});
      if (value) {
        set.add(unit.id);
      } else {
        set.remove(unit.id);
      }
    });
  }

  int _selectedUnitCount(Deck deck) =>
      (selected[deck.id] ?? {}).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('ミックス練習')),
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
                    child: Text(deck.title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  if (deck.isPurchased)
                    Chip(
                      label: const Text('購入済み'),
                      visualDensity: VisualDensity.compact,
                    )
                  else
                    Chip(
                      label: const Text('一部無料'),
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
                  final checked =
                      selected[deck.id]?.contains(u.id) ?? false;

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
        child: FilledButton(
          onPressed: !hasSelection
              ? null
              : () {
                  final cards = _buildCards();
                  if (cards.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('選択範囲に出題可能な問題がありません')),
                    );
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
                          isPurchased: true, // 仮の親（出題自体はoverrideCardsで制御）
                        ),
                        overrideCards: cards,
                      ),
                    ),
                  );
                },
          child: Text(
            hasSelection
                ? 'この選択で開始（${_buildCards().length}問）'
                : 'ユニットを選択してください',
          ),
        ),
      ),
    );
  }
}
