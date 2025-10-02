// lib/screens/unit_select_screen.dart
import 'package:flutter/material.dart';
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
  final Set<String> selected = {};

  @override
  Widget build(BuildContext context) {
    final units = widget.deck.units;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.deck.title} のユニット選択')),
      body: Column(
        children: [
          const SizedBox(height: 8),
          const Text('出題したいユニットを選択してください（複数可）'),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: units.length,
              itemBuilder: (_, i) {
                final Unit u = units[i];
                final checked = selected.contains(u.id);
                return CheckboxListTile(
                  title: Text(u.title),
                  value: checked,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        selected.add(u.id);
                      } else {
                        selected.remove(u.id);
                      }
                    });
                  },
                );
              },
            ),
          ),
          SafeArea(
            minimum: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: selected.isEmpty
                    ? null
                    : () {
                        // 出題カード生成：購入状況でフィルタ
                        final List<QuizCard> raw =
                            widget.deck.cardsFromUnits(selected);

                        final available = widget.deck.isPurchased
                            ? raw
                            : raw.where((c) => !(c.isPremium)).toList();

                        if (available.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content:
                                    Text('選択範囲に出題可能な問題がありません（無料分なし）')),
                          );
                          return;
                        }

                        available.shuffle();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => QuizScreen(
                              deck: widget.deck,
                              overrideCards: available,
                            ),
                          ),
                        );
                      },
                child: const Text('この選択で開始'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
