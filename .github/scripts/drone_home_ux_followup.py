from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected 1 replacement, found {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


app = "packages/qualification_app/lib/src/production_app.dart"
dashboard = "packages/qualification_app/lib/src/progress_dashboard.dart"
widget_test = "packages/qualification_app/test/production_widget_test.dart"
primary_test = "packages/qualification_app/test/home_primary_action_test.dart"

replace_once(
    app,
    """  if (controller.activeSession != null) {
    return _PrimaryActionSpec(
      key: 'resume-session',
      label: '続きから',
      description: '中断した学習をそのまま再開します。',
      icon: Icons.play_arrow,
      onPressed: () => unawaited(controller.resume()),
    );
  }
""",
    """  final resumableSession = controller.activeSession;
  if (resumableSession != null) {
    final resumeUnit = resumableSession.unitId == null
        ? null
        : controller.bank!.unitById(resumableSession.unitId!);
    final resumeContext = resumeUnit?.title ?? _modeLabel(resumableSession.mode);
    return _PrimaryActionSpec(
      key: 'resume-session',
      label: '続きから',
      description:
          '$resumeContext・${resumableSession.currentIndex + 1}/'
          '${resumableSession.questionIds.length}問目から再開します。',
      icon: Icons.play_arrow,
      onPressed: () => unawaited(controller.resume()),
    );
  }
""",
)

replace_once(
    app,
    """final class _WeaknessCard extends StatelessWidget {
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
    final canOpen = unit != null && controller.accessibleCardsFor(unit).isNotEmpty;
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: const Key('weakness-summary'),
      color: canOpen ? colors.primaryContainer : colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.insights),
        title: const Text('苦手な単元'),
        subtitle: weakest == null
            ? const Text('回答履歴がたまると単元別の傾向を確認できます。')
            : Text(
                '${unit?.title ?? weakest.key} ・ '
                '直近正答率${((score ?? 0) * 100).round()}% ・ '
                '${weakest.value.attemptCount}回答',
              ),
        trailing: canOpen ? const Icon(Icons.chevron_right) : null,
        onTap: canOpen ? () => unawaited(controller.startUnit(unit.id)) : null,
      ),
    );
  }
}
""",
    """const _weaknessConfidenceAttemptThreshold = 5;

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
    final hasEnoughEvidence = weakest != null &&
        attemptCount >= _weaknessConfidenceAttemptThreshold;
    final canOpen = unit != null && controller.accessibleCardsFor(unit).isNotEmpty;
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
""",
)

replace_once(
    app,
    """    final profile = controller.definition.examProfile;
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
""",
    """    final profile = controller.definition.examProfile;
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
            onPressed: controller.startMockExam,
            child: Text(
              profile == null
                  ? '模擬試験'
                  : '模擬試験（${profile.questionCount}問）',
            ),
          ),
        );
      }
    }
""",
)

replace_once(
    app,
    "final class _RecommendationCard extends StatelessWidget {\n",
    """Future<void> _showMockExamUnlockSheet(
  BuildContext context,
  QualificationProductionController controller,
) {
  final price = controller.fullUnlockProduct?.price;
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
            const Text('模擬試験は全問解放後に利用できます。'),
            const SizedBox(height: 8),
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
              child: const Text('全問を解放'),
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

final class _RecommendationCard extends StatelessWidget {
""",
)

replace_once(
    dashboard,
    """  final mockBest = bestMock == null
      ? '—'
      : '${bestMock.correctCount}/${bestMock.totalCount}';
""",
    """  final mockBest = bestMock == null
      ? '未受験'
      : '${bestMock.correctCount}/${bestMock.totalCount}';
""",
)

replace_once(
    dashboard,
    """            },
          ),
          const SizedBox(height: 20),
          _ProgressMetrics(
""",
    """            },
          ),
          const SizedBox(height: 10),
          _UnitPerformanceLegend(data: radarData),
          const SizedBox(height: 20),
          _ProgressMetrics(
""",
)

replace_once(
    dashboard,
    "final class _UnitPerformanceFallback extends StatelessWidget {\n",
    """final class _UnitPerformanceLegend extends StatelessWidget {
  const _UnitPerformanceLegend({required this.data});

  final List<_RadarDatum> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final columns = constraints.maxWidth < 430 || textScale > 1.35 ? 1 : 2;
        const spacing = 8.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: 4,
          children: [
            for (final item in data)
              SizedBox(
                width: width,
                child: Text(
                  '${_shortRadarLabel(item.label)}：${item.label}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
          ],
        );
      },
    );
  }
}

final class _UnitPerformanceFallback extends StatelessWidget {
""",
)

replace_once(
    dashboard,
    """String _shortRadarLabel(String label) {
  final trimmed = label.trim();
  if (trimmed.length <= 6) return trimmed;
  return '${trimmed.substring(0, 6)}…';
}
""",
    """String _shortRadarLabel(String label) {
  final trimmed = label.trim();
  if (trimmed.contains('リスク')) return 'リスク';
  if (trimmed.contains('規則')) return '規則';
  if (trimmed.contains('システム')) return 'システム';
  if (trimmed.contains('操縦者') || trimmed.contains('運航体制')) {
    return '操縦体制';
  }
  if (trimmed.length <= 6) return trimmed;
  return '${trimmed.substring(0, 6)}…';
}
""",
)

replace_once(
    widget_test,
    """    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('start-mock-exam')))
          .onPressed,
      isNull,
    );

    for (final unsupported in ['合格可能性', 'AI合否', '本番力']) {
""",
    """    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('start-mock-exam')))
          .onPressed,
      isNotNull,
    );
    final mockBest = find.byKey(const Key('progress-metric-mock-best'));
    expect(
      find.descendant(of: mockBest, matching: find.text('未受験')),
      findsOneWidget,
    );

    final lockedMock = find.byKey(const Key('start-mock-exam'));
    await tester.scrollUntilVisible(lockedMock, 160);
    await tester.tap(lockedMock);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mock-exam-unlock-sheet')), findsOneWidget);
    expect(find.text('全問解放で利用可能'), findsOneWidget);
    expect(find.text('買い切り Fixture'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    for (final unsupported in ['合格可能性', 'AI合否', '本番力']) {
""",
)

replace_once(
    widget_test,
    """    final weakness = find.byKey(const Key('weakness-summary'));
    await tester.scrollUntilVisible(weakness, 160);
    await tester.tap(weakness);
""",
    """    final weakness = find.byKey(const Key('weakness-summary'));
    await tester.scrollUntilVisible(weakness, 160);
    expect(find.text('要確認の単元'), findsOneWidget);
    expect(
      find.textContaining('まだ回答数が少ないため確認がおすすめ'),
      findsOneWidget,
    );
    await tester.tap(weakness);
""",
)

replace_once(
    primary_test,
    """    expect(find.byKey(const Key('resume-session')), findsOneWidget);
    expect(find.byKey(const Key('primary-action-incorrect')), findsNothing);
    expect(find.text('続きから'), findsOneWidget);
""",
    """    expect(find.byKey(const Key('resume-session')), findsOneWidget);
    expect(find.byKey(const Key('primary-action-incorrect')), findsNothing);
    expect(find.text('続きから'), findsOneWidget);
    expect(find.textContaining('1/1問目から再開します。'), findsOneWidget);
""",
)
