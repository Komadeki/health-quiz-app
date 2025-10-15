import 'package:flutter/material.dart';

class ReviewTestSetupScreen extends StatelessWidget {
  const ReviewTestSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('復習テスト（準備中）')),
      body: const Center(child: Text('PR②で有効化されます')),
    );
  }
}
