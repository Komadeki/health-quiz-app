import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import '../generated/app_manifest.g.dart';

/// Drone is a Reference Product composition, not a separate learning runtime.
final class DroneProductionBootstrap extends StatefulWidget {
  const DroneProductionBootstrap({super.key});

  @override
  State<DroneProductionBootstrap> createState() =>
      _DroneProductionBootstrapState();
}

final class _DroneProductionBootstrapState extends State<DroneProductionBootstrap>
    with WidgetsBindingObserver {
  late final QualificationProductionController controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final definition = GeneratedAppManifest.definition;
    final productId =
        definition.monetization.productCatalog.fullUnlockProductId;
    if (productId == null) {
      throw StateError('Drone production requires a full-unlock product.');
    }
    controller = QualificationProductionController(
      definition: definition,
      bankLoader: AssetQualificationBankLoader(
        definition: definition,
        assetBundle: rootBundle,
      ),
      sessionStore: SharedPreferencesQualificationSessionStore(
        appKey: definition.appKey,
      ),
      learningRepository: JsonLinesLearningRepository(appKey: definition.appKey),
      purchaseGateway: StorePurchaseGateway(),
      entitlementCache: SharedPreferencesFullUnlockEntitlementCache(
        appKey: definition.appKey,
        productId: productId,
      ),
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
  Widget build(BuildContext context) => DroneProductionApp(
        controller: controller,
      );
}

/// Uses the shared Qualification Factory everywhere except the live mock-exam
/// interaction surface, where Drone supports pre-submission review/navigation.
final class DroneProductionApp extends StatelessWidget {
  const DroneProductionApp({required this.controller, super.key});

  final QualificationProductionController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final session = controller.activeSession;
        final showDroneMock = !controller.isLoading &&
            controller.fatalError == null &&
            controller.view == QualificationProductionView.quiz &&
            session?.mode == LearningModeV1.mockExam;
        if (!showDroneMock) {
          return QualificationProductionApp(
            definition: controller.definition,
            controller: controller,
            homeSupplementBuilder: buildDroneHomeSupplement,
          );
        }
        final seedHex = controller.definition.branding.seedColorHex.substring(1);
        final seedColor = Color(int.parse('FF$seedHex', radix: 16));
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: controller.definition.displayName,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
            scaffoldBackgroundColor: const Color(0xFFF7FAFC),
          ),
          home: _DroneMockExamPage(
            key: ValueKey(session!.currentQuestionId),
            controller: controller,
          ),
        );
      },
    );
  }
}

Widget buildDroneHomeSupplement(
  BuildContext context,
  QualificationProductionController controller,
) {
  return DroneHomeSupplement(controller: controller);
}

final class DroneHomeSupplement extends StatelessWidget {
  const DroneHomeSupplement({
    required this.controller,
    super.key,
  });

  final QualificationProductionController controller;

  @override
  Widget build(BuildContext context) {
    final definition = controller.definition;
    final profile = definition.examProfile;
    late final String examSummary;
    if (profile == null) {
      examSummary = '単元別・復習で理解を固めます。';
    } else if (profile.timeLimitMinutes == null) {
      examSummary =
          '単元別・復習で確認した後、このアプリの模擬試験（${profile.questionCount}問）で仕上げます。';
    } else {
      examSummary =
          '単元別・復習で確認した後、このアプリの模擬試験（${profile.questionCount}問・${profile.timeLimitMinutes}分）で仕上げます。';
    }

    return Card(
      key: const Key('drone-study-guide'),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const Key('drone-study-guide-toggle'),
        initiallyExpanded: false,
        leading: const Icon(Icons.menu_book_outlined),
        title: const Text('二等学科の学習ガイド'),
        subtitle: const Text('必要なときに開いて確認'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '基準資料: ${definition.learningProduct.sourceLabel}',
            key: const Key('drone-study-guide-source'),
          ),
          const SizedBox(height: 8),
          Text(
            examSummary,
            key: const Key('drone-study-guide-path'),
          ),
        ],
      ),
    );
  }
}

final class _DroneMockExamPage extends StatefulWidget {
  const _DroneMockExamPage({required this.controller, super.key});

  final QualificationProductionController controller;

  @override
  State<_DroneMockExamPage> createState() => _DroneMockExamPageState();
}

final class _DroneMockExamPageState extends State<_DroneMockExamPage>
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
    if (controller.activeSession == null) return;
    final timedMock = controller.hasTimedMockExam;
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
    final committedChoice = controller.currentResponse;
    final committed = committedChoice != null;
    final pendingChange =
        committed && selectedChoice != null && selectedChoice != committedChoice;
    final remaining = controller.remainingMockExamDuration;
    final timeLimit = controller.definition.examProfile?.timeLimitMinutes;
    final isLast = session.currentIndex == session.questionIds.length - 1;

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
                  groupValue: selectedChoice,
                  onChanged: (value) => setState(() => selectedChoice = value),
                  child: Column(
                    children: [
                      for (final choiceIndex in controller.currentChoiceOrder)
                        Card(
                          child: RadioListTile<int>(
                            key: Key('choice-$choiceIndex'),
                            value: choiceIndex,
                            enabled: true,
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
                  )
                else ...[
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
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (session.currentIndex > 0) ...[
                        Expanded(
                          child: OutlinedButton.icon(
                            key: const Key('previous-question'),
                            onPressed: pendingChange
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
                          key: Key(isLast ? 'submit-mock-exam' : 'next-question'),
                          onPressed: pendingChange
                              ? null
                              : isLast
                                  ? _submitMockExam
                                  : controller.advance,
                          icon: Icon(
                            isLast ? Icons.fact_check_outlined : Icons.arrow_forward,
                          ),
                          label: Text(isLast ? '提出して採点' : '次へ'),
                        ),
                      ),
                    ],
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

String _remainingTimeLabel(Duration remaining) {
  final seconds = remaining.isNegative ? 0 : remaining.inSeconds;
  final minutes = seconds ~/ 60;
  final secondsPart = seconds % 60;
  return '残り $minutes:${secondsPart.toString().padLeft(2, '0')}';
}
