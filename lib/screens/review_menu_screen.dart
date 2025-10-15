// lib/screens/review_menu_screen.dart
import 'package:flutter/material.dart';
import 'review_cards_screen.dart';
import 'review_test_setup_screen.dart';

class ReviewMenuScreen extends StatelessWidget {
  const ReviewMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('復習')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.style),
            title: const Text('見直しモード'),
            subtitle: const Text('誤答カードを1枚ずつめくって復習'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReviewCardsScreen()),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.quiz),
            title: const Text('復習テストモード'),
            subtitle: const Text('誤答の出現頻度上位から 10/20/30/50 を出題'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReviewTestSetupScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
