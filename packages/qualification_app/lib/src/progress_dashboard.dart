part of 'production_app.dart';

Widget _buildProgressDashboard(
  BuildContext context,
  QualificationProductionController controller,
) {
  final progress = controller.progress!;
  final overall = progress.overall;
  final bank = controller.bank!;
  final progressQuestionCount = controller.hasFullUnlock
      ? overall.totalQuestions
      : controller.freeQuestionCount;
  final displayedCompletedQuestions = math.min(
    overall.completedQuestions,
    progressQuestionCount,
  );
  final displayedCompletion = progressQuestionCount == 0
      ? 0.0
      : (displayedCompletedQuestions / progressQuestionCount)
          .clamp(0.0, 1.0)
          .toDouble();
  final percent = (displayedCompletion * 100).round();
  final progressSummary = controller.hasFullUnlock
      ? '$displayedCompletedQuestions / ${overall.totalQuestions}問'
      : '$displayedCompletedQuestions / $progressQuestionCount問 ・ '
          '解放すると全${overall.totalQuestions}問';
  final accuracy =
      overall.accuracy == null ? '—' : '${(overall.accuracy! * 100).round()}%';
  final selectionEngine = PracticeSelectionEngine(
    canAccess: (candidate) =>
        controller.canAccess(bank.cardsById[candidate.questionId]!),
    randomizer: const IdentityQuestionRandomizer(),
  );
  final reviewCount = selectionEngine
      .selectIncorrect(bank.candidates, controller.events)
      .length;
  final bestMock = _bestMockHistory(controller.history);
  final mockBest = bestMock == null
      ? '未受験'
      : '${bestMock.correctCount}/${bestMock.totalCount}';
  final radarData = <_RadarDatum>[
    for (final unit in bank.units)
      _RadarDatum(
        label: unit.title,
        value: (progress.byUnit[unit.id]?.accuracy ?? 0)
            .clamp(0.0, 1.0)
            .toDouble(),
        hasData: progress.byUnit[unit.id]?.accuracy != null,
      ),
  ];

  return Card(
    key: const Key('progress-card'),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '学習進捗',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.auto_graph),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1.0);
              final stackCharts = constraints.maxWidth < 260 || textScale > 1.7;
              final ring = _ProgressRing(
                completion: displayedCompletion,
                percent: percent,
              );
              final radar = _UnitPerformanceChart(data: radarData);
              if (stackCharts) {
                return Column(
                  children: [ring, const SizedBox(height: 16), radar],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: Center(child: ring)),
                  const SizedBox(width: 12),
                  Expanded(child: radar),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          _ProgressMetrics(
            completed: '${overall.completedQuestions}問',
            accuracy: accuracy,
            review: '$reviewCount問',
            mockBest: mockBest,
            onMockBestTap: bestMock == null &&
                    controller.modeEnabled(LearningModeV1.mockExam)
                ? () {
                    if (controller.isMockExamLocked) {
                      unawaited(_showMockExamUnlockSheet(context, controller));
                    } else {
                      unawaited(controller.startMockExam());
                    }
                  }
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            progressSummary,
            key: const Key('overall-progress'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 4),
          Text(
            'これまでに回答した数 ${overall.attemptCount}回',
            key: const Key('overall-attempt-count'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: const Key('show-learning-status'),
              onPressed: () => _showLearningStatus(context, controller),
              icon: const Icon(Icons.insights),
              label: const Text('学習状況を詳しく見る'),
            ),
          ),
        ],
      ),
    ),
  );
}

SessionHistoryV1? _bestMockHistory(List<SessionHistoryV1> history) {
  SessionHistoryV1? best;
  for (final item in history) {
    if (item.mode != LearningModeV1.mockExam) continue;
    if (best == null) {
      best = item;
      continue;
    }
    final itemRate =
        item.totalCount == 0 ? 0.0 : item.correctCount / item.totalCount;
    final bestRate =
        best.totalCount == 0 ? 0.0 : best.correctCount / best.totalCount;
    if (itemRate > bestRate ||
        (itemRate == bestRate && item.correctCount > best.correctCount)) {
      best = item;
    }
  }
  return best;
}

final class _ProgressMetrics extends StatelessWidget {
  const _ProgressMetrics({
    required this.completed,
    required this.accuracy,
    required this.review,
    required this.mockBest,
    this.onMockBestTap,
  });

  final String completed;
  final String accuracy;
  final String review;
  final String mockBest;
  final VoidCallback? onMockBestTap;

  @override
  Widget build(BuildContext context) {
    final metrics = <Widget>[
      _MetricDescriptor(
        keyName: 'progress-metric-completed',
        icon: Icons.check_circle_outline,
        label: '学習済み',
      ).build(completed),
      _MetricDescriptor(
        keyName: 'progress-metric-accuracy',
        icon: Icons.track_changes,
        label: '正答率',
      ).build(accuracy),
      _MetricDescriptor(
        keyName: 'progress-metric-review',
        icon: Icons.replay,
        label: '要復習',
      ).build(review),
      _MetricDescriptor(
        keyName: 'progress-metric-mock-best',
        icon: Icons.fact_check_outlined,
        label: '模試ベスト',
      ).build(mockBest, onTap: onMockBestTap),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1.0);
        final columns = constraints.maxWidth < 280 || textScale > 1.35 ? 2 : 4;
        const spacing = 8.0;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics) SizedBox(width: width, child: metric),
          ],
        );
      },
    );
  }
}

final class _MetricDescriptor {
  const _MetricDescriptor({
    required this.keyName,
    required this.icon,
    required this.label,
  });

  final String keyName;
  final IconData icon;
  final String label;

  Widget build(String value, {VoidCallback? onTap}) => KeyedSubtree(
        key: Key(keyName),
        child: onTap == null
            ? _ProgressMetric(icon: icon, value: value, label: label)
            : Semantics(
                button: true,
                label: '$label $value。模擬試験を開く',
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onTap,
                  child:
                      _ProgressMetric(icon: icon, value: value, label: label),
                ),
              ),
      );
}

final class _RadarDatum {
  const _RadarDatum({
    required this.label,
    required this.value,
    required this.hasData,
  });

  final String label;
  final double value;
  final bool hasData;
}

final class _UnitPerformanceChart extends StatelessWidget {
  const _UnitPerformanceChart({required this.data});

  final List<_RadarDatum> data;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final semanticSummary = data
        .map(
          (item) => item.hasData
              ? '${item.label}${(item.value * 100).round()}%'
              : '${item.label}未回答',
        )
        .join('、');
    final supportsRadar = data.length >= 3;
    return Semantics(
      key: const Key('unit-performance-chart'),
      label: '分野別の正答率。$semanticSummary',
      child: ExcludeSemantics(
        child: SizedBox(
          height: 170,
          child: Column(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.secondaryContainer.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  child: Text(
                    '分野別',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colors.onSecondaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: supportsRadar
                    ? CustomPaint(
                        painter: _RadarPainter(
                          data: data,
                          gridColor: colors.outlineVariant,
                          axisColor: colors.outlineVariant,
                          fillColor: colors.primary.withValues(alpha: 0.16),
                          strokeColor: colors.primary,
                          textColor: colors.onSurface,
                        ),
                        child: const SizedBox.expand(),
                      )
                    : _UnitPerformanceFallback(data: data),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _UnitPerformanceFallback extends StatelessWidget {
  const _UnitPerformanceFallback({required this.data});

  final List<_RadarDatum> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('単元データなし'));
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (final item in data)
          Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  _shortRadarLabel(item.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(child: LinearProgressIndicator(value: item.value)),
              const SizedBox(width: 6),
              SizedBox(
                width: 32,
                child: Text(
                  item.hasData ? '${(item.value * 100).round()}%' : '—',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

final class _RadarPainter extends CustomPainter {
  const _RadarPainter({
    required this.data,
    required this.gridColor,
    required this.axisColor,
    required this.fillColor,
    required this.strokeColor,
    required this.textColor,
  });

  final List<_RadarDatum> data;
  final Color gridColor;
  final Color axisColor;
  final Color fillColor;
  final Color strokeColor;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 3) return;
    final center = Offset(size.width / 2, size.height / 2 + 2);
    final radius = math.min(size.width, size.height) * 0.29;
    final count = data.length;
    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = axisColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    Offset pointAt(int index, double scale) {
      final angle = -math.pi / 2 + (math.pi * 2 * index / count);
      return Offset(
        center.dx + math.cos(angle) * radius * scale,
        center.dy + math.sin(angle) * radius * scale,
      );
    }

    for (final level in [0.25, 0.5, 0.75, 1.0]) {
      final first = pointAt(0, level);
      final path = Path()..moveTo(first.dx, first.dy);
      for (var index = 1; index < count; index += 1) {
        final point = pointAt(index, level);
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }

    for (var index = 0; index < count; index += 1) {
      canvas.drawLine(center, pointAt(index, 1), axisPaint);
    }

    final valuePath = Path();
    for (var index = 0; index < count; index += 1) {
      final point = pointAt(index, data[index].value);
      if (index == 0) {
        valuePath.moveTo(point.dx, point.dy);
      } else {
        valuePath.lineTo(point.dx, point.dy);
      }
    }
    valuePath.close();
    canvas.drawPath(
      valuePath,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      valuePath,
      Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    for (var index = 0; index < count; index += 1) {
      final point = pointAt(index, data[index].value);
      canvas.drawCircle(
        point,
        3.5,
        Paint()
          ..color = strokeColor
          ..style = PaintingStyle.fill,
      );
    }

    for (var index = 0; index < count; index += 1) {
      final angle = -math.pi / 2 + (math.pi * 2 * index / count);
      final anchor = Offset(
        center.dx + math.cos(angle) * radius * 1.48,
        center.dy + math.sin(angle) * radius * 1.48,
      );
      final datum = data[index];
      final label = datum.hasData
          ? '${_shortRadarLabel(datum.label)} ${(datum.value * 100).round()}%'
          : '${_shortRadarLabel(datum.label)} —';
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: textColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
      )..layout(maxWidth: 68);
      final rawX = anchor.dx - painter.width / 2;
      final rawY = anchor.dy - painter.height / 2;
      final maxX = math.max(0.0, size.width - painter.width);
      final maxY = math.max(0.0, size.height - painter.height);
      final x = rawX.clamp(0.0, maxX).toDouble();
      final y = rawY.clamp(0.0, maxY).toDouble();
      painter.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => true;
}

String _shortRadarLabel(String label) {
  final trimmed = label.trim();
  if (trimmed.contains('労働生理')) return '生理';
  if (trimmed.contains('労働衛生')) {
    return trimmed.contains('有害業務以外') ? '衛生・一般' : '衛生・有害';
  }
  if (trimmed.contains('関係法令')) {
    return trimmed.contains('有害業務以外') ? '法令・一般' : '法令・有害';
  }
  if (trimmed.contains('リスク')) return 'リスク';
  if (trimmed.contains('規則')) return '規則';
  if (trimmed.contains('システム')) return 'システム';
  if (trimmed.contains('操縦者') || trimmed.contains('運航体制')) {
    return '操縦体制';
  }
  if (trimmed.length <= 6) return trimmed;
  return '${trimmed.substring(0, 6)}…';
}
