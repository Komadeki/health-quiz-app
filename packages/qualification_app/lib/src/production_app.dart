import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quiz_engine/quiz_engine.dart';
import 'package:url_launcher/url_launcher.dart';

import 'production_bank.dart';
import 'production_controller.dart';
import 'production_persistence.dart';
import 'production_purchase.dart';

part 'progress_dashboard.dart';

typedef QualificationExternalUrlLauncher = Future<bool> Function(Uri url);
typedef QualificationHomeSupplementBuilder = Widget Function(
  BuildContext context,
  QualificationProductionController controller,
);

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
    this.homeSupplementBuilder,
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
  final QualificationHomeSupplementBuilder? homeSupplementBuilder;

  @override
  State<QualificationProductionBootstrap> createState() =>
      _QualificationProductionBootstrapState();
}

final class _QualificationProductionBootstrapState
    extends State<QualificationProductionBootstrap>
    with WidgetsBindingObserver {
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
        homeSupplementBuilder: widget.homeSupplementBuilder,
      );
}

final class QualificationProductionApp extends StatelessWidget {
  const QualificationProductionApp({
    required this.definition,
    required this.controller,
    this.urlLauncher,
    this.homeSupplementBuilder,
    super.key,
  });

  final QualificationAppDefinition definition;
  final QualificationProductionController controller;
  final QualificationExternalUrlLauncher? urlLauncher;
  final QualificationHomeSupplementBuilder? homeSupplementBuilder;

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
            return _ProductionLoading(definition: definition);
          }
          if (controller.fatalError != null) {
            return _ProductionFailure(
              definition: definition,
              urlLauncher: urlLauncher ?? _launchExternalUrl,
            );
          }
          return switch (controller.view) {
            QualificationProductionView.home => QualificationHome(
                controller: controller,
                urlLauncher: urlLauncher ?? _launchExternalUrl,
                homeSupplementBuilder: homeSupplementBuilder,
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

final class QualificationHome extends StatefulWidget {
  const QualificationHome({
    required this.controller,
    required this.urlLauncher,
    this.homeSupplementBuilder,
    super.key,
  });

  final QualificationProductionController controller;
  final QualificationExternalUrlLauncher urlLauncher;
  final QualificationHomeSupplementBuilder? homeSupplementBuilder;

  @override
  State<QualificationHome> createState() => _QualificationHomeState();
}

final class _QualificationHomeState extends State<QualificationHome> {
  String? _dismissedNotice;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final definition = controller.definition;
    final bank = controller.bank!;
    final notice = controller.storeMessage == _dismissedNotice
        ? null
        : controller.storeMessage;
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _HomeHero(
                  controller: controller,
                  totalQuestions: bank.cards.length,
                ),
                const SizedBox(height: 16),
                _PrimaryLearningAction(controller: controller),
                if (notice != null) ...[
                  const SizedBox(height: 16),
                  _NonfatalStatus(
                    message: _learnerFacingStatus(notice),
                    onDismiss: () => setState(() {
                      _dismissedNotice = notice;
                    }),
                  ),
                ],
                if (definition.learningProduct.progressEnabled) ...[
                  const SizedBox(height: 16),
                  _ProgressCard(controller: controller),
                ],
                if (widget.homeSupplementBuilder != null) ...[
                  const SizedBox(height: 16),
                  Builder(
                    key: const Key('home-supplement'),
                    builder: (context) =>
                        widget.homeSupplementBuilder!(context, controller),
                  ),
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
                  urlLauncher: widget.urlLauncher,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _HomeHero extends StatelessWidget {
  const _HomeHero({required this.controller, required this.totalQuestions});

  final QualificationProductionController controller;
  final int totalQuestions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final definition = controller.definition;
    final availableText = controller.hasFullUnlock
        ? '全$totalQuestions問を利用できます'
        : '${controller.freeQuestionCount}問を無料で体験';
    return Semantics(
      container: true,
      header: true,
      label:
          '${definition.displayName}。${definition.learningProduct.homeHeadline}。$availableText',
      child: Container(
        key: const Key('home-hero'),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.primary, colors.tertiary],
          ),
          boxShadow: [
            BoxShadow(
              color: colors.primary.withValues(alpha: 0.24),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.onPrimary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.flight_takeoff,
                      size: 18,
                      color: colors.onPrimary,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '学科試験対策',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              definition.displayName,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: colors.onPrimary,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              definition.learningProduct.homeHeadline,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '合格に必要な知識を、問題演習で一歩ずつ。',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.onPrimary.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Icon(
                  Icons.verified_outlined,
                  size: 20,
                  color: colors.onPrimary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    availableText,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: colors.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
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
  final resumableSession = controller.activeSession;
  if (resumableSession != null) {
    final resumeUnit = resumableSession.unitId == null
        ? null
        : controller.bank!.unitById(resumableSession.unitId!);
    final resumeContext =
        resumeUnit?.title ?? _modeLabel(resumableSession.mode);
    return _PrimaryActionSpec(
      key: 'resume-session',
      label: '続きから',
      description: '$resumeContext・${resumableSession.currentIndex + 1}/'
          '${resumableSession.questionIds.length}問目から再開します。',
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

final class _NonfatalStatus extends StatelessWidget {
  const _NonfatalStatus({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: message,
      child: Card(
        key: const Key('nonfatal-status'),
        child: ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('お知らせ'),
          subtitle: Text(message, key: const Key('nonfatal-status-message')),
          trailing: IconButton(
            key: const Key('dismiss-nonfatal-status'),
            tooltip: 'お知らせを閉じる',
            onPressed: onDismiss,
            icon: const Icon(Icons.close),
          ),
        ),
      ),
    );
  }
}

const _weaknessConfidenceAttemptThreshold = 5;

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
    final attemptCount = weakest?.value.attemptCount ?? 0;
    final hasEnoughEvidence =
        weakest != null && attemptCount >= _weaknessConfidenceAttemptThreshold;
    final canOpen =
        unit != null && controller.accessibleCardsFor(unit).isNotEmpty;
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: const Key('weakness-summary'),
      color: canOpen ? colors.primaryContainer : colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.insights),
        title: Text(hasEnoughEvidence ? '苦手な単元' : '要確認の単元'),
        subtitle: weakest == null
            ? const Text('回答履歴がたまると単元別の傾向を確認できます。')
            : hasEnoughEvidence
                ? Text(
                    '${unit?.title ?? weakest.key} ・ '
                    '直近正答率${((score ?? 0) * 100).round()}% ・ '
                    '$attemptCount回答\n'
                    '直近正答率が最も低い単元',
                  )
                : Text(
                    '${unit?.title ?? weakest.key} ・ $attemptCount回答\n'
                    'まだ回答数が少ないため確認がおすすめ',
                  ),
        trailing: canOpen ? const Icon(Icons.chevron_right) : null,
        onTap: canOpen ? () => unawaited(controller.startUnit(unit.id)) : null,
      ),
    );
  }
}

final class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.controller});

  final QualificationProductionController controller;

  @override
  Widget build(BuildContext context) =>
      _buildProgressDashboard(context, controller);
}

final class _ProgressRing extends StatelessWidget {
  const _ProgressRing({required this.completion, required this.percent});

  final double completion;
  final int percent;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 112,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.square(
            dimension: 104,
            child: CircularProgressIndicator(
              key: const Key('overall-progress-ring'),
              value: completion,
              strokeWidth: 10,
              strokeCap: StrokeCap.round,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$percent%',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text('完了', style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ],
      ),
    );
  }
}

final class _ProgressMetric extends StatelessWidget {
  const _ProgressMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.onSecondaryContainer),
          const SizedBox(height: 6),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(label, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

Future<void> _showLearningStatus(
  BuildContext context,
  QualificationProductionController controller,
) {
  final overall = controller.progress!.overall;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.78,
        child: ListView(
          key: const Key('learning-status-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text('学習状況', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '${overall.completedQuestions}/${overall.totalQuestions}問を学習済み。'
              '単元ごとの進み具合を確認できます。',
            ),
            const SizedBox(height: 20),
            for (final unit in controller.bank!.units) ...[
              Builder(
                builder: (context) {
                  final metric = controller.progress!.byUnit[unit.id];
                  final completed = metric?.completedQuestions ?? 0;
                  final total = metric?.totalQuestions ?? unit.cards.length;
                  final completion = metric?.completion ?? 0;
                  final accuracy = metric?.accuracy;
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            unit.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          LinearProgressIndicator(value: completion),
                          const SizedBox(height: 8),
                          Text(
                            '$completed/$total問を学習済み'
                            '${accuracy == null ? '' : ' ・ 正答率${(accuracy * 100).round()}%'}',
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    ),
  );
}

final class _UnitCard extends StatelessWidget {
  const _UnitCard({required this.controller, required this.unit});

  final QualificationProductionController controller;
  final Unit unit;

  @override
  Widget build(BuildContext context) {
    final accessible = controller.accessibleCardsFor(unit).length;
    final metric = controller.progress?.byUnit[unit.id];
    final accessLabel = controller.hasFullUnlock
        ? '全${unit.cards.length}問を利用可能'
        : '利用可能 $accessible問 / 全${unit.cards.length}問';
    return Card(
      child: ListTile(
        key: Key('unit-${unit.id}'),
        title: Text(unit.title),
        subtitle: Text(
          '$accessLabel'
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
    final unansweredCount = selectionEngine
        .selectUnanswered(bank.candidates, controller.events)
        .length;
    final incorrectCount = selectionEngine
        .selectIncorrect(bank.candidates, controller.events)
        .length;
    final randomCount = math.min(
      controller.definition.learningProduct.practiceQuestionCount,
      controller.accessibleQuestionCount,
    );
    final buttons = <Widget>[];

    void add(
      LearningModeV1 mode,
      String key,
      String label,
      VoidCallback? start, {
      String? unavailableReason,
    }) {
      if (!controller.modeEnabled(mode)) return;
      buttons.add(
        OutlinedButton(
          key: Key(key),
          onPressed: start,
          child: Text(label),
        ),
      );
      if (start == null && unavailableReason != null) {
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
      'ランダム演習（$randomCount問）',
      hasAccessibleQuestions ? () => unawaited(controller.startRandom()) : null,
      unavailableReason: '利用できる問題がありません。',
    );
    add(
      LearningModeV1.unansweredPractice,
      'start-unanswered',
      '未回答から出題',
      unansweredCount > 0
          ? () => unawaited(
                _showPracticeCountSheet(
                  context,
                  title: '未回答から出題',
                  keyPrefix: 'unanswered',
                  availableCount: unansweredCount,
                  start: (count) => controller.startUnanswered(count: count),
                ),
              )
          : null,
      unavailableReason: '未回答の問題はありません。',
    );
    add(
      LearningModeV1.incorrectPractice,
      'start-incorrect',
      '直近で間違えた問題',
      incorrectCount > 0
          ? () => unawaited(
                _showPracticeCountSheet(
                  context,
                  title: '直近で間違えた問題',
                  keyPrefix: 'incorrect',
                  availableCount: incorrectCount,
                  start: (count) => controller.startIncorrect(count: count),
                ),
              )
          : null,
      unavailableReason: '直近で間違えた問題はありません。',
    );
    final profile = controller.definition.examProfile;
    if (controller.modeEnabled(LearningModeV1.mockExam)) {
      final locked = controller.isMockExamLocked;
      if (locked) {
        buttons.add(
          OutlinedButton.icon(
            key: const Key('start-mock-exam'),
            onPressed: () => unawaited(
              _showMockExamUnlockSheet(context, controller),
            ),
            icon: const Icon(Icons.lock_outline),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('模擬試験'),
                Text(
                  '全問解放で利用可能',
                  key: const Key('mock-exam-locked'),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        );
      } else {
        buttons.add(
          OutlinedButton(
            key: const Key('start-mock-exam'),
            onPressed: () => unawaited(
              _showMockExamStartSheet(context, controller),
            ),
            child: Text(
              profile == null ? '模擬試験' : '模擬試験（${profile.questionCount}問）',
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

Future<void> _showMockExamStartSheet(
  BuildContext context,
  QualificationProductionController controller,
) async {
  final profile = controller.definition.examProfile;
  if (profile == null) return;
  final input = TextEditingController(
    text: '${profile.timeLimitMinutes ?? 60}',
  );
  var errorText = '';
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            key: const Key('mock-exam-start-sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('模擬試験の時間設定', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 8),
              Text(
                  '${profile.questionCount}問。公式設定は${profile.timeLimitMinutes ?? '時間制限なし'}です。'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in <int>{
                    30,
                    60,
                    90,
                    profile.timeLimitMinutes ?? 180
                  })
                    ChoiceChip(
                      label: Text('$minutes分'),
                      selected: input.text == '$minutes',
                      onSelected: (_) => setSheetState(() {
                        input.text = '$minutes';
                        errorText = '';
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('mock-exam-time-input'),
                controller: input,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: '制限時間（分）',
                  helperText: '1〜720分で指定できます。',
                  errorText: errorText.isEmpty ? null : errorText,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('confirm-start-mock-exam'),
                onPressed: () async {
                  final minutes = int.tryParse(input.text);
                  if (minutes == null || minutes < 1 || minutes > 720) {
                    setSheetState(() => errorText = '1〜720分で入力してください。');
                    return;
                  }
                  if (await controller.startMockExam(
                          timeLimitMinutes: minutes) &&
                      sheetContext.mounted) {
                    Navigator.of(sheetContext).pop();
                  }
                },
                child: const Text('この設定で開始'),
              ),
            ],
          ),
        ),
      ),
    );
  } finally {
    await WidgetsBinding.instance.endOfFrame;
    input.dispose();
  }
}

const _practiceCountOptions = [5, 10, 20, 30, 50, 100, 150, 200];

Future<void> _showPracticeCountSheet(
  BuildContext context, {
  required String title,
  required String keyPrefix,
  required int availableCount,
  required Future<bool> Function(int? count) start,
}) {
  final numericOptions = _practiceCountOptions
      .where((count) => count < availableCount)
      .toList(growable: false);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        key: Key('practice-count-sheet-$keyPrefix'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text('対象 $availableCount問から、出題数を選んでください。'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final count in numericOptions)
                  OutlinedButton(
                    key: Key('practice-count-$keyPrefix-$count'),
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                      unawaited(start(count));
                    },
                    child: Text('$count問'),
                  ),
                FilledButton(
                  key: Key('practice-count-$keyPrefix-all'),
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(start(null));
                  },
                  child: Text('全部（$availableCount問）'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showMockExamUnlockSheet(
  BuildContext context,
  QualificationProductionController controller,
) {
  final price = controller.fullUnlockProduct?.price;
  final total = controller.bank!.cards.length;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        key: const Key('mock-exam-unlock-sheet'),
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '模擬試験を解放',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            const Text('本番を想定した模擬試験は全問解放後に利用できます。'),
            const SizedBox(height: 14),
            _UnlockBenefitRow(label: '全$total問すべて利用可能'),
            const SizedBox(height: 6),
            const _UnlockBenefitRow(label: '各単元の全問題'),
            const SizedBox(height: 6),
            _UnlockBenefitRow(label: _mockExamUnlockLabel(controller)),
            const SizedBox(height: 14),
            Text(price == null ? '価格を確認できません' : '買い切り $price'),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('mock-exam-unlock-purchase'),
              onPressed: controller.purchasePending || price == null
                  ? null
                  : () {
                      Navigator.of(sheetContext).pop();
                      unawaited(controller.purchaseFullUnlock());
                    },
              child: Text('全$total問を解放する'),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(),
              child: const Text('あとで'),
            ),
          ],
        ),
      ),
    ),
  );
}

String _mockExamUnlockLabel(QualificationProductionController controller) {
  final profile = controller.definition.examProfile;
  if (profile == null) return '模擬試験';
  final minutes = profile.timeLimitMinutes;
  if (minutes == null) return '模擬試験（${profile.questionCount}問）';
  return '模擬試験（${profile.questionCount}問・$minutes分）';
}

final class _UnlockBenefitRow extends StatelessWidget {
  const _UnlockBenefitRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      );
}

final class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.controller});

  final QualificationProductionController controller;

  @override
  Widget build(BuildContext context) {
    final recommendation = controller.recommendation;
    if (recommendation == null) return const SizedBox.shrink();
    final unit = controller.bank!.unitById(recommendation.unitId);
    final canOpen =
        unit != null && controller.accessibleCardsFor(unit).isNotEmpty;
    final reason = recommendation.reasonCode == 'unanswered_unit'
        ? 'まだ回答履歴がないため'
        : '直近の正答率が最も低いため';
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: const Key('recommendation'),
      color: canOpen ? colors.primaryContainer : colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.route),
        title: Text('次のおすすめ: ${unit?.title ?? recommendation.unitId}'),
        subtitle: Text(reason),
        trailing: canOpen ? const Icon(Icons.chevron_right) : null,
        onTap: canOpen ? () => unawaited(controller.startUnit(unit.id)) : null,
      ),
    );
  }
}

final class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.controller});

  final QualificationProductionController controller;

  @override
  Widget build(BuildContext context) {
    final history = controller.history;
    final latest = history.firstOrNull;
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: const Key('session-history'),
      color:
          latest == null ? colors.surfaceContainerLow : colors.primaryContainer,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        key: const Key('show-session-history'),
        leading: const Icon(Icons.history),
        title: const Text('学習履歴'),
        subtitle: Text(
          latest == null
              ? '完了した学習はまだありません。'
              : '${history.length}回完了 ・ 直近 ${latest.correctCount}/${latest.totalCount}問正解',
        ),
        trailing: latest == null ? null : const Icon(Icons.chevron_right),
        onTap: latest == null
            ? null
            : () => _showSessionHistory(context, controller),
      ),
    );
  }
}

Future<void> _showSessionHistory(
  BuildContext context,
  QualificationProductionController controller,
) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.78,
        child: ListView(
          key: const Key('session-history-sheet'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Text('学習履歴', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('${controller.history.length}回の完了記録'),
            const SizedBox(height: 16),
            for (final item in controller.history)
              Card(
                child: ListTile(
                  title: Text(_historyTitle(item, controller)),
                  subtitle: Text(
                    '${item.correctCount}/${item.totalCount}問正解 ・ '
                    '${_historyDateLabel(item.completedAt)}',
                  ),
                  trailing: item.passed == null
                      ? null
                      : Text(item.passed! ? '合格' : '不合格'),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

String _historyTitle(
  SessionHistoryV1 history,
  QualificationProductionController controller,
) {
  final unitId = history.unitId;
  if (unitId == null) return _modeLabel(history.mode);
  final unit = controller.bank!.unitById(unitId);
  return '${_modeLabel(history.mode)}：${unit?.title ?? unitId}';
}

String _historyDateLabel(DateTime completedAt) {
  final local = completedAt.toLocal();
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${local.year}/${twoDigits(local.month)}/${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
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
    final completedFree = math.min(
      controller.progress?.overall.completedQuestions ?? 0,
      controller.freeQuestionCount,
    );
    return Card(
      key: const Key('full-unlock-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('全問解放', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '無料問題 $completedFree / ${controller.freeQuestionCount}問 学習済み',
              key: const Key('free-tier-progress'),
            ),
            const SizedBox(height: 14),
            _UnlockBenefitRow(label: '全$total問すべて利用可能'),
            const SizedBox(height: 6),
            const _UnlockBenefitRow(label: '各単元の全問題'),
            const SizedBox(height: 6),
            _UnlockBenefitRow(label: _mockExamUnlockLabel(controller)),
            const SizedBox(height: 12),
            Text(price == null ? '価格を確認できません' : '買い切り $price'),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('purchase-full-unlock'),
              onPressed: controller.purchasePending || price == null
                  ? null
                  : controller.purchaseFullUnlock,
              child: Text(
                controller.purchasePending ? '確認中…' : '全$total問を解放する',
              ),
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
    final timedMock =
        session.mode == LearningModeV1.mockExam && controller.hasTimedMockExam;
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

  Future<void> _commitSelected() async {
    final choice = selectedChoice;
    if (choice == null) return;
    await widget.controller.commitAnswer(choice);
    if (mounted) setState(() {});
  }

  Future<void> _submitMockExam() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('模擬試験を提出しますか？'),
        content: const Text(
          '提出すると採点され、回答は変更できません。見直す場合は「見直す」を選んでください。',
        ),
        actions: [
          TextButton(
            key: const Key('review-before-submit'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('見直す'),
          ),
          FilledButton(
            key: const Key('confirm-submit-mock-exam'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('提出して採点'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await widget.controller.advance();
    }
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
    final choiceOrder = controller.currentChoiceOrder;
    final committedChoice = controller.currentResponse;
    final committed = committedChoice != null;
    final isMockExam = session.mode == LearningModeV1.mockExam;
    final correct = committed && committedChoice == card.answerIndex;
    final pendingChange = isMockExam &&
        committed &&
        selectedChoice != null &&
        selectedChoice != committedChoice;
    final hasUnsavedInitialChoice =
        isMockExam && !committed && selectedChoice != null;
    final navigationBlocked = pendingChange || hasUnsavedInitialChoice;
    final isLast = session.currentIndex == session.questionIds.length - 1;
    final timeLimit =
        isMockExam ? controller.definition.examProfile?.timeLimitMinutes : null;
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
                  groupValue: isMockExam
                      ? selectedChoice
                      : committed
                          ? committedChoice
                          : selectedChoice,
                  onChanged: (value) {
                    if (isMockExam || !committed) {
                      setState(() => selectedChoice = value);
                    }
                  },
                  child: Column(
                    children: [
                      for (final choiceIndex in choiceOrder)
                        Card(
                          child: RadioListTile<int>(
                            key: Key('choice-$choiceIndex'),
                            value: choiceIndex,
                            enabled: isMockExam || !committed,
                            title: Text(card.choices[choiceIndex]),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (!committed)
                  FilledButton(
                    key: const Key('commit-answer'),
                    onPressed: selectedChoice == null ? null : _commitSelected,
                    child: const Text('回答確定'),
                  ),
                if (isMockExam) ...[
                  if (committed) ...[
                    Semantics(
                      liveRegion: true,
                      child: const Text(
                        '回答済みです。提出前なら変更できます。',
                        key: Key('mock-answer-committed'),
                      ),
                    ),
                    if (pendingChange) ...[
                      const SizedBox(height: 12),
                      FilledButton(
                        key: const Key('revise-answer'),
                        onPressed: _commitSelected,
                        child: const Text('回答を変更'),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '回答を変更してから問題を移動してください。',
                        key: Key('pending-answer-change'),
                      ),
                    ],
                  ],
                  if (hasUnsavedInitialChoice) ...[
                    const SizedBox(height: 6),
                    const Text(
                      '回答を確定してから問題を移動してください。',
                      key: Key('pending-initial-answer'),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (session.currentIndex > 0) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('previous-question'),
                            onPressed: navigationBlocked
                                ? null
                                : controller.moveToPreviousMockQuestion,
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('前へ'),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: FilledButton.icon(
                          key: Key(
                              isLast ? 'submit-mock-exam' : 'next-question'),
                          onPressed: !committed || navigationBlocked
                              ? null
                              : isLast
                                  ? _submitMockExam
                                  : controller.advance,
                          icon: Icon(
                            isLast
                                ? Icons.fact_check_outlined
                                : Icons.arrow_forward,
                          ),
                          label: Text(isLast ? '提出して採点' : '次へ'),
                        ),
                      ),
                    ],
                  ),
                ] else if (committed) ...[
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
                    key: const Key('selected-answer-feedback'),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '正解: ${card.choices[card.answerIndex]}',
                    key: const Key('correct-answer-feedback'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '解説（Explanation）',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(card.explanation ?? ''),
                  _QuestionSourceProvenance(card: card),
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

final class _QuestionSourceProvenance extends StatelessWidget {
  const _QuestionSourceProvenance({required this.card});

  final QuizCard card;

  @override
  Widget build(BuildContext context) {
    String? normalized(String? value) {
      final result = value?.trim();
      return result == null || result.isEmpty ? null : result;
    }

    final title = normalized(card.sourceTitle);
    final version = normalized(card.sourceVersion);
    final section = normalized(card.sourceSection);
    if (title == null && version == null && section == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        key: const Key('question-source-provenance'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('出典', style: Theme.of(context).textTheme.titleMedium),
              if (title != null) ...[
                const SizedBox(height: 4),
                Text(title, key: const Key('question-source-title')),
              ],
              if (version != null) ...[
                const SizedBox(height: 4),
                Text(
                  '版: $version',
                  key: const Key('question-source-version'),
                ),
              ],
              if (section != null) ...[
                const SizedBox(height: 4),
                Text(
                  '箇所: $section',
                  key: const Key('question-source-section'),
                ),
              ],
            ],
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
    final matchingHistory = controller.history
        .where((item) => item.sessionId == result.sessionId)
        .toList(growable: false);
    final completedHistory =
        matchingHistory.isEmpty ? null : matchingHistory.first;
    return Scaffold(
      appBar: AppBar(title: const Text('結果')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  '${result.correctCount} / ${result.totalCount} 正解',
                  key: const Key('session-result'),
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                if (pass != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    pass ? '合格' : '不合格',
                    textAlign: TextAlign.center,
                  ),
                ],
                if (result.mode == LearningModeV1.mockExam && pass == null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    '参考得点です。合否判定は行いません。',
                    key: Key('mock-no-pass-rule'),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (result.mode == LearningModeV1.mockExam &&
                    completedHistory != null) ...[
                  const SizedBox(height: 16),
                  _MockExamReview(
                    controller: controller,
                    history: completedHistory,
                  ),
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
      ),
    );
  }
}

final class _MockExamReview extends StatelessWidget {
  const _MockExamReview({
    required this.controller,
    required this.history,
  });

  final QualificationProductionController controller;
  final SessionHistoryV1 history;

  @override
  Widget build(BuildContext context) {
    final bank = controller.bank!;
    final eventsByQuestionId = <String, LearningEventV1>{
      for (final event in controller.events)
        if (event.sessionId == history.sessionId) event.questionId: event,
    };
    final reviewItems = <Widget>[];
    for (var index = 0; index < history.questionIds.length; index += 1) {
      final questionId = history.questionIds[index];
      final card = bank.cardsById[questionId];
      if (card == null) continue;
      reviewItems.add(
        _MockExamReviewItem(
          index: index,
          card: card,
          event: eventsByQuestionId[questionId],
        ),
      );
    }

    return Card(
      key: const Key('mock-review'),
      child: ExpansionTile(
        key: const Key('mock-review-toggle'),
        title: const Text('模擬試験を復習'),
        subtitle: const Text('回答・正答・解説・出典を確認できます。'),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: reviewItems,
      ),
    );
  }
}

final class _MockExamReviewItem extends StatelessWidget {
  const _MockExamReviewItem({
    required this.index,
    required this.card,
    required this.event,
  });

  final int index;
  final QuizCard card;
  final LearningEventV1? event;

  @override
  Widget build(BuildContext context) {
    final selectedChoice = event?.selectedChoice;
    final selectedText =
        selectedChoice == null ? '未回答' : card.choices[selectedChoice];
    final status = selectedChoice == null
        ? '未回答'
        : selectedChoice == card.answerIndex
            ? '正解'
            : '不正解';
    final statusColor = selectedChoice == null
        ? null
        : selectedChoice == card.answerIndex
            ? Colors.blue.shade700
            : Colors.red.shade300;
    final explanation = card.explanation?.trim();
    final titleStyle = Theme.of(context).textTheme.titleMedium;

    return Card(
      key: Key('mock-review-item-$index'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text.rich(
              TextSpan(
                style: titleStyle,
                children: [
                  TextSpan(text: '第${index + 1}問 ・ '),
                  TextSpan(
                    text: status,
                    style: titleStyle?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              key: Key('mock-review-status-$index'),
            ),
            const SizedBox(height: 8),
            Text(card.question),
            const SizedBox(height: 12),
            Text(
              'あなたの回答: $selectedText',
              key: Key('mock-review-selected-$index'),
            ),
            const SizedBox(height: 4),
            Text(
              '正解: ${card.choices[card.answerIndex]}',
              key: Key('mock-review-correct-$index'),
            ),
            if (explanation != null && explanation.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('解説', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(explanation),
            ],
            _QuestionSourceProvenance(card: card),
          ],
        ),
      ),
    );
  }
}

final class _ProductionLoading extends StatelessWidget {
  const _ProductionLoading({required this.definition});

  final QualificationAppDefinition definition;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(definition.displayName)),
      body: Center(
        child: Semantics(
          key: const Key('production-loading'),
          liveRegion: true,
          label: '問題データを読み込んでいます',
          child: const ExcludeSemantics(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('問題データを読み込んでいます'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _ProductionFailure extends StatelessWidget {
  const _ProductionFailure({
    required this.definition,
    required this.urlLauncher,
  });

  final QualificationAppDefinition definition;
  final QualificationExternalUrlLauncher urlLauncher;

  @override
  Widget build(BuildContext context) {
    final support = definition.urls.support;
    return Scaffold(
      key: const Key('production-failure'),
      appBar: AppBar(title: Text(definition.displayName)),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 16),
                Text(
                  '問題データを読み込めませんでした',
                  style: Theme.of(context).textTheme.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'アプリを再度開いても解消しない場合は、サポートをご確認ください。',
                  textAlign: TextAlign.center,
                ),
                if (_hasUrl(support)) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    key: const Key('failure-support-link'),
                    onPressed: () => _openExternalUrl(support!, urlLauncher),
                    child: const Text('サポートを開く'),
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

String _learnerFacingStatus(String rawMessage) {
  const knownMessages = {
    '購入情報を確認できませんでした。無料問題は利用できます。',
    'ストア商品を取得できません。無料問題は利用できます。',
    'ストア情報の一部を取得できませんでした。',
    'ストアに接続できません。無料問題は利用できます。',
    '模擬試験は全問解放後に利用できます。',
    '購入商品を利用できません。無料問題は引き続き利用できます。',
    '購入を開始できませんでした。',
    '購入の復元に失敗しました。',
    '購入処理を確認しています。',
    '購入はキャンセルされました。',
    '購入を完了できませんでした。',
    '購入情報を保存できませんでした。',
  };
  if (knownMessages.contains(rawMessage) ||
      RegExp(r'^全\d+問を利用できます。$').hasMatch(rawMessage)) {
    return rawMessage;
  }
  return '操作を完了できませんでした。もう一度お試しください。';
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

String _modeLabel(LearningModeV1 mode) => switch (mode) {
      LearningModeV1.unitPractice => '単元別学習',
      LearningModeV1.randomPractice => 'ランダム演習',
      LearningModeV1.unansweredPractice => '未回答演習',
      LearningModeV1.incorrectPractice => '間違い演習',
      LearningModeV1.retry => '再挑戦',
      LearningModeV1.mockExam => '模擬試験',
    };
