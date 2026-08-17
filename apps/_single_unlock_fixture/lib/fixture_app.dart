import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'fixture_bank.dart';
import 'fixture_shell_controller.dart';
import 'generated/app_manifest.g.dart';

class FixtureApp extends StatefulWidget {
  const FixtureApp({super.key});

  @override
  State<FixtureApp> createState() => _FixtureAppState();
}

class _FixtureAppState extends State<FixtureApp> {
  late final FixtureShellController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FixtureShellController(
      bankLoader: FixtureBankLoader(assetBundle: rootBundle),
    )..load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seedHex = GeneratedAppManifest.seedColor.substring(1);
    final seedColor = Color(int.parse('FF$seedHex', radix: 16));
    return MaterialApp(
      title: GeneratedAppManifest.displayName,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
      ),
      home: FixtureHome(controller: _controller),
    );
  }
}

class FixtureHome extends StatelessWidget {
  const FixtureHome({required this.controller, super.key});

  final FixtureShellController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text(GeneratedAppManifest.displayName)),
          body: _body(context),
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null) {
      return Center(child: Text('読み込みエラー: ${controller.error}'));
    }
    final bank = controller.bank!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${bank.cards.length} active questions',
          key: const Key('active-question-count'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        for (final deck in bank.decks)
          for (final card in deck.cards)
            _QuestionTile(
              card: card,
              accessible: controller.canAccess(deck.id, card),
            ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('fixture-full-unlock'),
          onPressed: controller.purchaseFullUnlock,
          child: const Text('Fixture full unlock'),
        ),
      ],
    );
  }
}

class _QuestionTile extends StatelessWidget {
  const _QuestionTile({required this.card, required this.accessible});

  final QuizCard card;
  final bool accessible;

  @override
  Widget build(BuildContext context) {
    final accessLabel = accessible ? '利用可能' : 'ロック中';
    final tierLabel = card.isPremium ? 'premium' : 'free';
    return Card(
      child: ListTile(
        title: Text(card.question),
        subtitle: Text('$tierLabel / $accessLabel'),
        trailing: Icon(accessible ? Icons.lock_open : Icons.lock),
      ),
    );
  }
}
