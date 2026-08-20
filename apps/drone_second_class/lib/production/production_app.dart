import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quiz_engine/quiz_engine.dart' show Unit;

import '../generated/app_manifest.g.dart';
import 'production_bank.dart';
import 'production_controller.dart';
import 'production_persistence.dart';
import 'production_purchase.dart';

class DroneProductionBootstrap extends StatefulWidget {
  const DroneProductionBootstrap({super.key});

  @override
  State<DroneProductionBootstrap> createState() =>
      _DroneProductionBootstrapState();
}

class _DroneProductionBootstrapState extends State<DroneProductionBootstrap> {
  late final DroneProductionController _controller = DroneProductionController(
    bankLoader: AssetDroneBankLoader(assetBundle: rootBundle),
    sessionStore: const SharedPreferencesDroneSessionStore(),
    purchaseGateway: StoreDronePurchaseGateway(),
  )..initialize();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      DroneProductionApp(controller: _controller);
}

class DroneProductionApp extends StatelessWidget {
  const DroneProductionApp({required this.controller, super.key});

  final DroneProductionController controller;

  @override
  Widget build(BuildContext context) {
    final seedHex = GeneratedAppManifest.seedColor.substring(1);
    final seedColor = Color(int.parse('FF$seedHex', radix: 16));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: GeneratedAppManifest.displayName,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
        scaffoldBackgroundColor: const Color(0xFFF7FAFC),
      ),
      home: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (controller.isLoading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (controller.fatalError != null) {
            return _ProductionFailure(message: controller.fatalError!);
          }
          return switch (controller.view) {
            DroneProductionView.home => ProductionHome(controller: controller),
            DroneProductionView.quiz => ProductionQuizPage(
                key: ValueKey(controller.activeSession?.currentQuestionId),
                controller: controller,
              ),
            DroneProductionView.result => ProductionResultPage(
                controller: controller,
              ),
          };
        },
      ),
    );
  }
}

class ProductionHome extends StatelessWidget {
  const ProductionHome({required this.controller, super.key});

  static const _unitOrder = [
    'drone_rules',
    'drone_systems',
    'drone_operations',
    'drone_risk_management',
  ];

  final DroneProductionController controller;

  @override
  Widget build(BuildContext context) {
    final bank = controller.bank!;
    final units = [for (final id in _unitOrder) bank.unitById(id)!];
    return Scaffold(
      appBar: AppBar(title: const Text(GeneratedAppManifest.displayName)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '教則第5版を基にした全100問',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  controller.hasFullUnlock
                      ? '全100問を利用できます'
                      : '無料版では各単元5問・合計20問を利用できます',
                ),
                if (controller.activeSession != null) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    key: const Key('resume-session'),
                    onPressed: controller.resume,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('続きから'),
                  ),
                ],
                const SizedBox(height: 16),
                for (final unit in units)
                  _UnitCard(controller: controller, unit: unit),
                const SizedBox(height: 8),
                _UnlockCard(controller: controller),
                const SizedBox(height: 20),
                Text(
                  GeneratedAppManifest.legalese,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnitCard extends StatelessWidget {
  const _UnitCard({required this.controller, required this.unit});

  final DroneProductionController controller;
  final Unit unit;

  @override
  Widget build(BuildContext context) {
    final accessible = controller.accessibleCardsFor(unit).length;
    return Card(
      child: ListTile(
        key: Key('unit-${unit.id}'),
        title: Text(unit.title),
        subtitle: Text('$accessible / ${unit.cards.length}問を利用可能'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => controller.startUnit(unit.id),
      ),
    );
  }
}

class _UnlockCard extends StatelessWidget {
  const _UnlockCard({required this.controller});

  final DroneProductionController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.hasFullUnlock) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.lock_open),
          title: Text('全100問 解放済み'),
        ),
      );
    }
    final price = controller.fullUnlockProduct?.price;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('全100問を解放', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(price == null ? '価格を取得できません' : '買い切り $price'),
            if (controller.storeMessage != null) ...[
              const SizedBox(height: 8),
              Text(controller.storeMessage!),
            ],
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('purchase-full-unlock'),
              onPressed: controller.purchasePending || price == null
                  ? null
                  : controller.purchaseFullUnlock,
              child: Text(controller.purchasePending ? '確認中…' : '購入する'),
            ),
            TextButton(
              key: const Key('restore-purchases'),
              onPressed: controller.purchasePending
                  ? null
                  : controller.restorePurchases,
              child: const Text('購入を復元'),
            ),
          ],
        ),
      ),
    );
  }
}

class ProductionQuizPage extends StatefulWidget {
  const ProductionQuizPage({required this.controller, super.key});

  final DroneProductionController controller;

  @override
  State<ProductionQuizPage> createState() => _ProductionQuizPageState();
}

class _ProductionQuizPageState extends State<ProductionQuizPage> {
  int? selectedChoice;

  @override
  void initState() {
    super.initState();
    selectedChoice = widget.controller.currentResponse;
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final session = controller.activeSession!;
    final card = controller.currentCard!;
    final committedChoice = controller.currentResponse;
    final committed = committedChoice != null;
    final correct = committed && committedChoice == card.answerIndex;
    return Scaffold(
      appBar: AppBar(
        title:
            Text('${session.currentIndex + 1} / ${session.questionIds.length}'),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(card.question,
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                RadioGroup<int>(
                  groupValue: committed ? committedChoice : selectedChoice,
                  onChanged: (value) {
                    if (!committed) {
                      setState(() => selectedChoice = value);
                    }
                  },
                  child: Column(
                    children: [
                      for (var index = 0;
                          index < card.choices.length;
                          index += 1)
                        Card(
                          child: RadioListTile<int>(
                            key: Key('choice-$index'),
                            value: index,
                            enabled: !committed,
                            title: Text(card.choices[index]),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (!committed)
                  FilledButton(
                    key: const Key('commit-answer'),
                    onPressed: selectedChoice == null
                        ? null
                        : () => controller.commitAnswer(selectedChoice!),
                    child: const Text('回答確定'),
                  ),
                if (committed) ...[
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      correct ? '正解' : '不正解',
                      key: const Key('answer-feedback'),
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: correct
                                    ? Colors.green.shade800
                                    : Theme.of(context).colorScheme.error,
                              ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('解説（Explanation）',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(card.explanation ?? ''),
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('next-question'),
                    onPressed: controller.advance,
                    child: const Text('次へ'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProductionResultPage extends StatelessWidget {
  const ProductionResultPage({required this.controller, super.key});

  final DroneProductionController controller;

  @override
  Widget build(BuildContext context) {
    final result = controller.result!;
    return Scaffold(
      appBar: AppBar(title: const Text('結果')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${result.correct} / ${result.total} 正解',
                key: const Key('session-result'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 24),
              FilledButton(
                key: const Key('return-home'),
                onPressed: controller.returnHome,
                child: const Text('ホームへ戻る'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductionFailure extends StatelessWidget {
  const _ProductionFailure({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(GeneratedAppManifest.displayName)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('問題データを読み込めませんでした。\n$message'),
      ),
    );
  }
}
