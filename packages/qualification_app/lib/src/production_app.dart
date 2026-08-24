import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quiz_engine/quiz_engine.dart';
import 'package:url_launcher/url_launcher.dart';

import 'production_bank.dart';
import 'production_controller.dart';
import 'production_persistence.dart';
import 'production_purchase.dart';

typedef QualificationExternalUrlLauncher = Future<bool> Function(Uri url);

final class QualificationProductionBootstrap extends StatefulWidget {
  const QualificationProductionBootstrap({
    required this.definition,
    this.bankLoader,
    this.sessionStore,
    this.learningRepository,
    this.purchaseGateway,
    this.entitlementCache,
    this.now,
    this.randomizer,
    this.urlLauncher,
    super.key,
  });

  final QualificationAppDefinition definition;
  final QualificationBankLoader? bankLoader;
  final QualificationSessionStore? sessionStore;
  final LearningRepository? learningRepository;
  final LifecyclePurchaseGateway? purchaseGateway;
  final EntitlementCache? entitlementCache;
  final DateTime Function()? now;
  final QuestionRandomizer? randomizer;
  final QualificationExternalUrlLauncher? urlLauncher;

  @override
  State<QualificationProductionBootstrap> createState() =>
      _QualificationProductionBootstrapState();
}

final class _QualificationProductionBootstrapState
    extends State<QualificationProductionBootstrap> with WidgetsBindingObserver {
  late final QualificationProductionController controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final definition = widget.definition;
    final productId =
        definition.monetization.productCatalog.fullUnlockProductId;
    if (productId == null) {
      throw StateError('Factory v1 requires a full-unlock product.');
    }
    controller = QualificationProductionController(
      definition: definition,
      bankLoader: widget.bankLoader ??
          AssetQualificationBankLoader(
            definition: definition,
            assetBundle: rootBundle,
          ),
      sessionStore: widget.sessionStore ??
          SharedPreferencesQualificationSessionStore(appKey: definition.appKey),
      learningRepository: widget.learningRepository ??
          JsonLinesLearningRepository(appKey: definition.appKey),
      purchaseGateway: widget.purchaseGateway ?? StorePurchaseGateway(),
      entitlementCache: widget.entitlementCache ??
          SharedPreferencesFullUnlockEntitlementCache(
            appKey: definition.appKey,
            productId: productId,
          ),
      now: widget.now,
      randomizer: widget.randomizer,
    )..initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(controller.completeExpiredMockExamIfNeeded());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => QualificationProductionApp(
        definition: widget.definition,
        controller: controller,
        urlLauncher: widget.urlLauncher,
      );
}

final class QualificationProductionApp extends StatelessWidget {
  const QualificationProductionApp({
    required this.definition,
    required this.controller,
    this.urlLauncher,
    super.key,
  });

  final QualificationAppDefinition definition;
  final QualificationProductionController controller;
  final QualificationExternalUrlLauncher? urlLauncher;

  @override
  Widget build(BuildContext context) {
    final seedHex = definition.branding.seedColorHex.substring(1);
    final seedColor = Color(int.parse('FF$seedHex', radix: 16));
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: definition.displayName,
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
            return _ProductionFailure(
              definition: definition,
              message: controller.fatalError!,
            );
          }
          return switch (controller.view) {
            QualificationProductionView.home => QualificationHome(
              controller: controller,
              urlLauncher: urlLauncher ?? _launchExternalUrl,
            ),
            QualificationProductionView.quiz => QualificationQuizPage(
              key: ValueKey(controller.activeSession?.currentQuestionId),
              controller: controller,
            ),
            QualificationProductionView.result => QualificationResultPage(
              controller: controller,
            ),
          };
        },
      ),
    );
  }
}

final class QualificationHome extends StatelessWidget {
  const QualificationHome({
    required this.controller,
    required this.urlLauncher,
    super.key,
  });

  final QualificationProductionController controller;
  final QualificationExternalUrlLauncher urlLauncher;

  @override
  Widget build(BuildContext context) {
    final definition = controller.definition;
    final bank = controller.bank!;
    return Scaffold(
      appBar: AppBar(title: Text(definition.displayName)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  definition.learningProduct.homeHeadline,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  controller.hasFullUnlock
                      ? '全${bank.cards.length}問を利用できます'
                      : '${controller.freeQuestionCount}問を無料で利用できます',
                ),
                const SizedBox(height: 16),
                _PrimaryLearningAction(controller: controller),
                if (definition.learningProduct.progressEnabled) ...[
                  const SizedBox(height: 16),
                  _ProgressCard(controller: controller),
                ],
                const SizedBox(height: 16),
                Text('単元別学習', style: Theme.of(context).textTheme.titleLarge),
                for (final unit in bank.units)
                  _UnitCard(controller: controller, unit: unit),
                const SizedBox(height: 16),
                _PracticeModes(controller: controller),
                if (definition.learningProduct.weaknessEnabled) ...[
                  const SizedBox(height: 16),
                  _WeaknessCard(controller: controller),
                ],
                if (definition.learningProduct.recommendationEnabled) ...[
                  const SizedBox(height: 16),
                  _RecommendationCard(controller: controller),
                ],
                if (definition.learningProduct.historyEnabled) ...[
                  const SizedBox(height: 16),
                  _HistoryCard(controller: controller),
                ],
                const SizedBox(height: 16),
                _UnlockCard(controller: controller),
                const SizedBox(height: 20),
                Text(
                  definition.learningProduct.sourceLabel,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  definition.legalese,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                _InformationLinks(
                  urls: definition.urls,
                  urlLauncher: urlLauncher,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _PrimaryLearningAction extends StatelessWidget {
  const _PrimaryLearningAction({required this.controller});

  final QualificationProductionController controller;

  @override
  Widget build(BuildContext context) {
    final action = _resolvePrimaryAction(controller);
    return Card(
      key: const Key('primary-learning-action'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('次にやること', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(action.description),
            const SizedBox(height: 12),
            FilledButton.icon(
              key: Key(action.key),
              onPressed: action.onPressed,
              icon: Icon(action.icon),
              label: Text(action.label),
            ),
          ],
        ),
      ),
    );
  }
}

final class _PrimaryActionSpec {
  const _PrimaryActionSpec({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.onPressed,
  });

  final String key;
  final String label;
  final String description;
  final IconData icon;
  final VoidCallback? onPressed;
}

_PrimaryActionSpec _resolvePrimaryAction(
  QualificationProductionController controller,
) {
  if (controller.activeSession != null) {
    return _PrimaryActionSpec(
      key: 'resume-session',
      label: '続きから',
      description: '中断した学習をそのまま再開します。',
      icon: Icons.play_arrow,
      onPressed: () => unawaited(controller.resume()),
    );
  }

  final bank = controller.bank!;
  final selectionEngine = PracticeSelectionEngine(
    canAccess: (candidate) =>
        controller.canAccess(bank.cardsById[candidate.questionId]!),
    randomizer: const IdentityQuestionRandomizer(),
  );

  if (controller.modeEnabled(LearningModeV1.incorrectPractice)) {
    final incorrect =
        selectionEngine.selectIncorrect(bank.candidates, controller.events);
    if (incorrect.isNotEmpty) {
      return _PrimaryActionSpec(
        key: 'primary-action-incorrect',
        label: '間違えた問題を復習',
        description: '直近で間違えた${incorrect.length}問を優先して確認します。',
        icon: Icons.replay,
        onPressed: () => unawaited(controller.startIncorrect()),
      );
    }
  }

  if (controller.definition.learningProduct.recommendationEnabled) {
    final recommendation = controller.recommendation;
    final unit = recommendation == null
        ? null
        : controller.bank!.unitById(recommendation.unitId);
    if (recommendation != null &&
        unit != null &&
        controller.accessibleCardsFor(unit).isNotEmpty) {
      final reason = recommendation.reasonCode == 'unanswered_unit'
          ? 'まだ回答していない単元から始めます。'
          : '直近の学習状況から、この単元を優先します。';
      return _PrimaryActionSpec(
        key: 'primary-action-recommendation',
        label: 'おすすめ: ${unit.title}',
        description: reason,
        icon: Icons.route,
        onPressed: () => unawaited(controller.startUnit(unit.id)),
      );
    }
  }

  if (controller.modeEnabled(LearningModeV1.unansweredPractice)) {
    final unanswered =
        selectionEngine.selectUnanswered(bank.candidates, controller.events);
    if (unanswered.isNotEmpty) {
      return _PrimaryActionSpec(
        key: 'primary-action-unanswered',
        label: '未回答から始める',
        description: 'まだ解いていない${unanswered.length}問から学習します。',
        icon: Icons.fiber_new,
        onPressed: () => unawaited(controller.startUnanswered()),
      );
    }
  }

  Unit? firstAccessibleUnit;
  if (controller.modeEnabled(LearningModeV1.unitPractice)) {
    for (final unit in bank.units) {
      if (controller.accessibleCardsFor(unit).isNotEmpty) {
        firstAccessibleUnit = unit;
        break;
      }
    }
  }
  if (firstAccessibleUnit != null) {
    return _PrimaryActionSpec(
      key: 'primary-action-start',
      label: '${firstAccessibleUnit.title}から始める',
      description: '利用できる単元から学習を始めます。',
      icon: Icons.school,
      onPressed: () => unawaited(controller.startUnit(firstAccessibleUnit!.id)),
    );
  }

  if (controller.modeEnabled(LearningModeV1.randomPractice) &&
      controller.accessibleQuestionCount > 0) {
    return _PrimaryActionSpec(
      key: 'primary-action-start',
      label: '学習を始める',
      description: '利用できる問題から学習を始めます。',
      icon: Icons.school,
      onPressed: () => unawaited(controller.startRandom()),
    );
  }

  return const _PrimaryActionSpec(
    key: 'primary-action-unavailable',
    label: '利用できる学習がありません',
    description: '現在利用できる問題を確認してください。',
    icon: Icons.info_outline,
    onPressed: null,
  );
}

final class _WeaknessCard extends StatelessWidget {
  const _WeaknessCard({required this.controller});

  final QualificationProductionController controller;

  @override
  Widget build(BuildContext context) {
    final entries = controller.weakness!.byUnit.entries.toList()
      ..sort((left, right) {
        final leftScore =
            left.value.recentCorrectness ?? left.value.correctness ?? 0;
        final rightScore =
            right.value.recentCorrectness ?? right.value.correctness ?? 0;
        final order = leftScore.compareTo(rightScore);
        return order != 0 ? order : left.key.compareTo(right.key);
      });
    final weakest = entries.isEmpty ? null : entries.first;
    final unit =
        weakest == null ? null : controller.bank!.unitById(weakest.key);
    final score =
        weakest?.value.recentCorrectness ?? weakest?.value.correctness;
    return Card(
      key: const Key('weakness-summary'),
      child: ListTile(
        leading: const Icon(Icons.insights),
        title: const Text('学習状況の確認'),
        subtitle: weakest == null
            ? const Text('回答履歴がたまると単元別の傾向を確認できます。')
            : Text(
                '${unit?.title ?? weakest.key} ・ '
                '直近正答率${((score ?? 0) * 100).round()}% ・ '
                '${weakest.value.attemptCount}回答',
              ),
      ),
    );
  }
}

final class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.controller});

  final QualificationProductionController controller;

  @override
  Widget build(BuildContext context) {
    final progress = controller.progress!.overall;
    final percent = (progress.completion * 100).round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('学習進捗', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress.completion),
            const SizedBox(height: 8),
            Text(
              '$percent% ・ ${progress.completedQuestions} / '
              '${progress.totalQuestions}問 ・ ${progress.attemptCount}回答',
              key: const Key('overall-progress'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _UnitCard extends StatelessWidget {
  const _UnitCard({required this.controller, required this.unit});

  final QualificationProductionController controller;
  final Unit unit;

  @override
  Widget build(BuildContext context) {
    final accessible = controller.accessibleCardsFor(unit).length;
    final metric = controller.progress?.byUnit[unit.id];
    return Card(
      child: ListTile(
        key: Key('unit-${unit.id}'),
        title: Text(unit.title),
        subtitle: Text(
          '$accessible / ${unit.cards.length}問を利用可能'
          '${metric == null ? '' : ' ・ 学習済み${metric.completedQuestions}問'}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: accessible == 0 ? null : () => controller.startUnit(unit.id),
      ),
    );
  }
}

final class _PracticeModes extends StatelessWidget {
  const _PracticeModes({required this.controller});

  final QualificationProductionController controller;

  @override
  Widget build(BuildContext context) {
    final bank = controller.bank!;
    final selectionEngine = PracticeSelectionEngine(
      canAccess: (candidate) =>
          controller.canAccess(bank.cardsById[candidate.questionId]!),
      randomizer: const IdentityQuestionRandomizer(),
    );
    final hasAccessibleQuestions = controller.accessibleQuestionCount > 0;
    final hasUnansweredQuestions = selectionEngine
        .selectUnanswered(bank.candidates, controller.events)
        .isNotEmpty;
    final hasIncorrectQuestions = selectionEngine
        .selectIncorrect(bank.candidates, controller.events)
        .isNotEmpty;
    final buttons = <Widget>[];

    void add(
      LearningModeV1 mode,
      String key,
      String label,
      Future<bool> Function() start, {
      required bool available,
      String? unavailableReason,
    }) {
      if (!controller.modeEnabled(mode)) return;
      buttons.add(
        OutlinedButton(
          key: Key(key),
          onPressed: available ? start : null,
          child: Text(label),
        ),
      );
      if (!available && unavailableReason != null) {
        buttons.add(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              unavailableReason,
              key: Key('$key-unavailable'),
            ),
          ),
        );
      }
    }

    add(
      LearningModeV1.randomPractice,
      'start-random',
      'ランダム演習',
      controller.startRandom,
      available: hasAccessibleQuestions,
      unavailableReason: '利用できる問題がありません。',
    );
    add(
      LearningModeV1.unansweredPractice,
      'start-unanswered',
      '未回答から出題',
      controller.startUnanswered,
      available: hasUnansweredQuestions,
      unavailableReason: '未回答の問題はありません。',
    );
    add(
      LearningModeV1.incorrectPractice,
      'start-incorrect',
      '直近で間違えた問題',
      controller.startIncorrect,
      available: hasIncorrectQuestions,
      unavailableReason: '直近で間違えた問題はありません。',
    );
    final profile = controller.definition.examProfile;
    if (controller.modeEnabled(LearningModeV1.mockExam)) {
      final locked = controller.isMockExamLocked;
      buttons.add(
        OutlinedButton(
          key: const Key('start-mock-exam'),
          onPressed: locked ? null : controller.startMockExam,
          child: Text(
            locked
                ? '模擬試験（全問解放後に利用可能）'
                : profile == null
                ? '模擬試験'
                : '模擬試験（${profile.questionCount}問）',
          ),
        ),
      );
      if (locked) {
        buttons.add(
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              '模擬試験はFull Unlockで全問を解放すると利用できます。',
              key: Key('mock-exam-locked'),
            ),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('標準演習', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        ...buttons,
      ],
    );
  }
}

final class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.controller});

  final QualificationProductionController controller;

  @override
  Widget build(BuildContext context) {
    final recommendation = controller.recommendation;
    if (recommendation == null) return const SizedBox.shrink();
    final unit = controller.bank!.unitById(recommendation.unitId);
    final reason = recommendation.reasonCode == 'unanswered_unit'
        ? 'まだ回答履歴がないため'
        : '直近の正答率が最も低いため';
    return Card(
      key: const Key('recommendation'),
      child: ListTile(
        leading: const Icon(Icons.route),
        title: Text('次のおすすめ: ${unit?.title ?? recommendation.unitId}'),
        subtitle: Text(reason),
        onTap: unit == null ? null : () => controller.startUnit(unit.id),
      ),
    );
  }
}

final class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.controller});

  final QualificationProductionController controller;

  @override
  Widget build(BuildContext context) {
    final history = controller.history.take(5).toList(growable: false);
    return Card(
      key: const Key('session-history'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('学習履歴', style: Theme.of(context).textTheme.titleMedium),
            if (history.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('完了した学習はまだありません。'),
              )
            else
              for (final item in history)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_modeLabel(item.mode)),
                  subtitle: Text(
                    '${item.correctCount} / ${item.totalCount} 正解',
                  ),
                  trailing: item.passed == null
                      ? null
                      : Text(item.passed! ? '合格' : '不合格'),
                ),
          ],
        ),
      ),
    );
  }
}

final class _UnlockCard extends StatelessWidget {
  const _UnlockCard({required this.controller});

  final QualificationProductionController controller;

  @override
  Widget build(BuildContext context) {
    final total = controller.bank!.cards.length;
    if (controller.hasFullUnlock) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.lock_open),
          title: Text('全$total問 解放済み'),
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
            Text('全$total問を解放', style: Theme.of(context).textTheme.titleMedium),
            Text(price == null ? '価格を確認できません' : '買い切り $price'),
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

final class _InformationLinks extends StatelessWidget {
  const _InformationLinks({required this.urls, required this.urlLauncher});

  final QualificationUrls urls;
  final QualificationExternalUrlLauncher urlLauncher;

  @override
  Widget build(BuildContext context) {
    final links = <Widget>[];
    if (_hasUrl(urls.support)) {
      links.add(
        TextButton(
          key: const Key('support-link'),
          onPressed: () => _openExternalUrl(urls.support!, urlLauncher),
          child: const Text('サポート'),
        ),
      );
    }
    if (_hasUrl(urls.privacy)) {
      links.add(
        TextButton(
          key: const Key('privacy-link'),
          onPressed: () => _openExternalUrl(urls.privacy!, urlLauncher),
          child: const Text('プライバシーポリシー'),
        ),
      );
    }
    if (links.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(alignment: WrapAlignment.center, children: links),
    );
  }
}

final class QualificationQuizPage extends StatefulWidget {
  const QualificationQuizPage({required this.controller, super.key});

  final QualificationProductionController controller;

  @override
  State<QualificationQuizPage> createState() => _QualificationQuizPageState();
}

final class _QualificationQuizPageState extends State<QualificationQuizPage>
    with WidgetsBindingObserver {
  int? selectedChoice;
  Timer? _clockTicker;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    selectedChoice = widget.controller.currentResponse;
    if (widget.controller.hasTimedMockExam) {
      _clockTicker = Timer.periodic(
        const Duration(seconds: 1),
        (_) => _refreshMockExamClock(),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshMockExamClock();
  }

  void _refreshMockExamClock() {
    unawaited(widget.controller.completeExpiredMockExamIfNeeded());
    if (mounted) setState(() {});
  }

  Future<void> _leaveSession() async {
    final controller = widget.controller;
    final session = controller.activeSession;
    if (session == null) return;
    final timedMock = session.mode == LearningModeV1.mockExam &&
        controller.hasTimedMockExam;
    if (timedMock) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('模擬試験を中断しますか？'),
          content: const Text(
            'ホームに戻っても制限時間は止まりません。後で「続きから」再開できます。',
          ),
          actions: [
            TextButton(
              key: const Key('stay-in-session'),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('続ける'),
            ),
            FilledButton(
              key: const Key('confirm-leave-session'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ホームへ戻る'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    controller.returnHome();
  }

  @override
  void dispose() {
    _clockTicker?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final session = controller.activeSession!;
    final card = controller.currentCard!;
    final committedChoice = controller.currentResponse;
    final committed = committedChoice != null;
    final isMockExam = session.mode == LearningModeV1.mockExam;
    final correct = committed && committedChoice == card.answerIndex;
    final timeLimit = isMockExam
        ? controller.definition.examProfile?.timeLimitMinutes
        : null;
    final remaining = controller.remainingMockExamDuration;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          key: const Key('leave-session'),
          tooltip: 'ホームへ戻る',
          onPressed: _leaveSession,
          icon: const Icon(Icons.close),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '${session.currentIndex + 1} / ${session.questionIds.length}'
                '${timeLimit == null ? '' : ' ・ 制限$timeLimit分'}',
              ),
            ),
            if (remaining != null)
              Text(
                _remainingTimeLabel(remaining),
                key: const Key('mock-exam-remaining'),
              ),
          ],
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  card.question,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                RadioGroup<int>(
                  groupValue: committed ? committedChoice : selectedChoice,
                  onChanged: (value) {
                    if (!committed) setState(() => selectedChoice = value);
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
                  if (isMockExam)
                    Semantics(
                      liveRegion: true,
                      child: const Text(
                        '回答を記録しました',
                        key: Key('mock-answer-committed'),
                      ),
                    )
                  else ...[
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
                    Text(
                      'あなたの回答: ${card.choices[committedChoice]}',
                      key: const Key('selected-answer-text'),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '正答: ${card.choices[card.answerIndex]}',
                      key: const Key('correct-answer-text'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '解説（Explanation）',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(card.explanation ?? ''),
                  ],
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

final class QualificationResultPage extends StatelessWidget {
  const QualificationResultPage({required this.controller, super.key});

  final QualificationProductionController controller;

  @override
  Widget build(BuildContext context) {
    final result = controller.result!;
    final pass = result.mockExamResult?.passed;
    return Scaffold(
      appBar: AppBar(title: const Text('結果')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${result.correctCount} / ${result.totalCount} 正解',
                key: const Key('session-result'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (pass != null) ...[
                const SizedBox(height: 8),
                Text(pass ? '合格' : '不合格'),
              ],
              if (result.mode == LearningModeV1.mockExam && pass == null) ...[
                const SizedBox(height: 8),
                const Text('参考得点です。合否判定は行いません。', key: Key('mock-no-pass-rule')),
              ],
              if (controller.modeEnabled(LearningModeV1.retry) &&
                  result.incorrectQuestionIds.isNotEmpty) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  key: const Key('retry-session'),
                  onPressed: controller.startRetry,
                  child: const Text('間違えた問題を再挑戦'),
                ),
              ],
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

bool _hasUrl(String? value) => value?.trim().isNotEmpty ?? false;

Future<bool> _launchExternalUrl(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);

Future<void> _openExternalUrl(
  String rawUrl,
  QualificationExternalUrlLauncher urlLauncher,
) async {
  try {
    final url = Uri.tryParse(rawUrl);
    if (url == null) return;
    await urlLauncher(url);
  } on Object {
    // An unavailable browser must not disrupt local learning state.
  }
}

String _remainingTimeLabel(Duration remaining) {
  final seconds = remaining.isNegative ? 0 : remaining.inSeconds;
  final minutes = seconds ~/ 60;
  final secondsPart = seconds % 60;
  return '残り $minutes:${secondsPart.toString().padLeft(2, '0')}';
}

final class _ProductionFailure extends StatelessWidget {
  const _ProductionFailure({required this.definition, required this.message});

  final QualificationAppDefinition definition;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(definition.displayName)),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('問題データを読み込めませんでした。\n$message'),
      ),
    );
  }
}

String _modeLabel(LearningModeV1 mode) => switch (mode) {
      LearningModeV1.unitPractice => '単元別学習',
      LearningModeV1.randomPractice => 'ランダム演習',
      LearningModeV1.unansweredPractice => '未回答演習',
      LearningModeV1.incorrectPractice => '間違い演習',
      LearningModeV1.retry => '再挑戦',
      LearningModeV1.mockExam => '模擬試験',
    };
