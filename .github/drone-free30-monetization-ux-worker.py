#!/usr/bin/env python3
from __future__ import annotations

import csv
import io
import json
import math
import re
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
QUESTIONS = ROOT / "question_banks/drone_second_class/authoring/questions.csv"
BANK = ROOT / "question_banks/drone_second_class/authoring/bank.json"
README = ROOT / "question_banks/drone_second_class/README.md"
PRODUCTION = ROOT / "packages/qualification_app/lib/src/production_app.dart"
PROGRESS = ROOT / "packages/qualification_app/lib/src/progress_dashboard.dart"
SHARED_TEST = ROOT / "packages/qualification_app/test/production_widget_test.dart"
DRONE_TEST = ROOT / "apps/drone_second_class/test/production_widget_test.dart"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one anchor, found {count}")
    return text.replace(old, new, 1)


def replace_regex_once(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise RuntimeError(f"{label}: expected exactly one regex match, found {count}")
    return updated


def expand_free_tier() -> list[str]:
    with QUESTIONS.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames
        rows = list(reader)
    if fieldnames is None:
        raise RuntimeError("questions.csv has no header")

    active = [row for row in rows if row["status"] == "active"]
    existing_free = [row for row in active if row["is_free"] == "true"]
    if len(active) != 188 or len(existing_free) != 20:
        raise RuntimeError(
            f"unexpected baseline: active={len(active)} free={len(existing_free)}"
        )

    totals = Counter(row["unit_id"] for row in active)
    free_by_unit = Counter(row["unit_id"] for row in existing_free)
    target_total = 30
    raw = {unit: target_total * total / len(active) for unit, total in totals.items()}
    targets = {
        unit: max(free_by_unit[unit], math.floor(raw[unit])) for unit in totals
    }
    while sum(targets.values()) < target_total:
        candidates = [unit for unit in totals if targets[unit] < totals[unit]]
        unit = max(
            candidates,
            key=lambda value: (
                raw[value] - math.floor(raw[value]), totals[value], value
            ),
        )
        targets[unit] += 1
    while sum(targets.values()) > target_total:
        candidates = [unit for unit in totals if targets[unit] > free_by_unit[unit]]
        unit = min(candidates, key=lambda value: (raw[value] - targets[value], value))
        targets[unit] -= 1

    premium = defaultdict(list)
    for row in active:
        if row["is_free"] != "true":
            premium[row["unit_id"]].append(row)
    for rows_for_unit in premium.values():
        rows_for_unit.sort(key=lambda row: row["question_id"])

    selected: list[str] = []
    for unit in sorted(totals):
        needed = targets[unit] - free_by_unit[unit]
        if needed < 0:
            raise RuntimeError(f"target would remove existing free questions for {unit}")
        for row in premium[unit][:needed]:
            row["is_free"] = "true"
            row["question_version"] = str(int(row["question_version"]) + 1)
            selected.append(row["question_id"])

    final_free = [row for row in active if row["is_free"] == "true"]
    final_counts = Counter(row["unit_id"] for row in final_free)
    if len(final_free) != 30 or final_counts != Counter(targets):
        raise RuntimeError(f"free tier allocation failed: {final_counts} targets={targets}")

    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    QUESTIONS.write_text(output.getvalue(), encoding="utf-8")

    print("free targets:", dict(sorted(targets.items())))
    print("newly free:", ", ".join(selected))
    return selected


def update_bank_and_docs(selected: list[str]) -> None:
    bank = json.loads(BANK.read_text(encoding="utf-8"))
    if bank["bank_revision"] != "drone-second-class-v2-release-2026-08-24":
        raise RuntimeError(f"unexpected bank revision: {bank['bank_revision']}")
    bank["bank_revision"] = "drone-second-class-v3-release-2026-08-25"
    BANK.write_text(json.dumps(bank, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    readme = README.read_text(encoding="utf-8")
    readme = replace_once(
        readme,
        "Production release v2 activates the complete 188-question canonical bank without changing\nquestion content or permanent identities.",
        "Production release v3 keeps the complete 188-question canonical bank and expands the\nfree tier from 20 to 30 questions without changing question content or permanent identities.",
        "README release paragraph",
    )
    readme = replace_once(
        readme,
        "- Production bank revision: `drone-second-class-v2-release-2026-08-24`.",
        "- Production bank revision: `drone-second-class-v3-release-2026-08-25`.",
        "README revision",
    )
    readme = replace_once(
        readme,
        "- Production runtime: 188 active questions, 20 free, and 168 premium.",
        "- Production runtime: 188 active questions, 30 free, and 158 premium.",
        "README counts",
    )
    old_free_line = "- Free selection remains the original 20 permanent IDs; the 88 expansion questions remain premium."
    new_free_line = (
        "- Free selection preserves the original 20 and adds 10 already-released questions, "
        "distributed across all four units.\n"
        "- Added free IDs for v3: " + ", ".join(selected) + "."
    )
    readme = replace_once(readme, old_free_line, new_free_line, "README free selection")
    README.write_text(readme, encoding="utf-8")


def update_paywall_ui() -> None:
    text = PRODUCTION.read_text(encoding="utf-8")

    mock_pattern = r"Future<void> _showMockExamUnlockSheet\(.*?\n\}\n\nfinal class _RecommendationCard"
    mock_replacement = '''Future<void> _showMockExamUnlockSheet(
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

final class _RecommendationCard'''
    text = replace_regex_once(text, mock_pattern, mock_replacement, "mock unlock sheet")

    unlock_pattern = r"final class _UnlockCard extends StatelessWidget \{.*?\n\}\n\nfinal class _InformationLinks"
    unlock_replacement = '''final class _UnlockCard extends StatelessWidget {
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

final class _InformationLinks'''
    text = replace_regex_once(text, unlock_pattern, unlock_replacement, "unlock card")
    PRODUCTION.write_text(text, encoding="utf-8")


def update_progress_ui() -> None:
    text = PROGRESS.read_text(encoding="utf-8")
    text = replace_once(
        text,
        """          _ProgressMetrics(
            completed: '${overall.completedQuestions}問',
            accuracy: accuracy,
            review: '$reviewCount問',
            mockBest: mockBest,
          ),""",
        """          _ProgressMetrics(
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
          ),""",
        "progress metrics call",
    )
    text = replace_once(
        text,
        """    required this.review,
    required this.mockBest,
  });

  final String completed;
  final String accuracy;
  final String review;
  final String mockBest;""",
        """    required this.review,
    required this.mockBest,
    this.onMockBestTap,
  });

  final String completed;
  final String accuracy;
  final String review;
  final String mockBest;
  final VoidCallback? onMockBestTap;""",
        "progress metrics fields",
    )
    text = replace_once(
        text,
        """      _MetricDescriptor(
        keyName: 'progress-metric-mock-best',
        icon: Icons.fact_check_outlined,
        label: '模試ベスト',
      ).build(mockBest),""",
        """      _MetricDescriptor(
        keyName: 'progress-metric-mock-best',
        icon: Icons.fact_check_outlined,
        label: '模試ベスト',
      ).build(mockBest, onTap: onMockBestTap),""",
        "mock metric callback",
    )
    text = replace_once(
        text,
        """  Widget build(String value) => KeyedSubtree(
    key: Key(keyName),
    child: _ProgressMetric(icon: icon, value: value, label: label),
  );""",
        """  Widget build(String value, {VoidCallback? onTap}) => KeyedSubtree(
    key: Key(keyName),
    child: onTap == null
        ? _ProgressMetric(icon: icon, value: value, label: label)
        : Semantics(
            button: true,
            label: '$label $value。模擬試験を開く',
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: _ProgressMetric(icon: icon, value: value, label: label),
            ),
          ),
  );""",
        "metric builder",
    )
    text = replace_once(
        text,
        "final columns = constraints.maxWidth < 430 || textScale > 1.35 ? 1 : 2;",
        "final columns = constraints.maxWidth < 300 || textScale > 1.35 ? 1 : 2;",
        "radar legend layout",
    )
    PROGRESS.write_text(text, encoding="utf-8")


def update_tests() -> None:
    text = SHARED_TEST.read_text(encoding="utf-8")
    text = replace_once(
        text,
        """    expect(
      find.descendant(of: mockBest, matching: find.text('未受験')),
      findsOneWidget,
    );

    final lockedMock = find.byKey(const Key('start-mock-exam'));""",
        """    expect(
      find.descendant(of: mockBest, matching: find.text('未受験')),
      findsOneWidget,
    );
    await tester.tap(mockBest);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mock-exam-unlock-sheet')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final lockedMock = find.byKey(const Key('start-mock-exam'));""",
        "mock metric test",
    )
    text = replace_once(
        text,
        """    expect(
      find.descendant(of: unlockSheet, matching: find.text('買い切り Fixture')),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();""",
        """    expect(
      find.descendant(of: unlockSheet, matching: find.text('買い切り Fixture')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: unlockSheet,
        matching: find.text('全${controller.bank!.cards.length}問を解放する'),
      ),
      findsOneWidget,
    );
    await tester.binding.handlePopRoute();""",
        "mock sheet CTA test",
    )
    text = replace_once(
        text,
        """    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    for (final unsupported in ['合格可能性', 'AI合否', '本番力']) {""",
        """    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    final purchase = find.byKey(const Key('purchase-full-unlock'));
    await tester.scrollUntilVisible(purchase, 160);
    expect(find.byKey(const Key('free-tier-progress')), findsOneWidget);
    expect(find.text('各単元の全問題'), findsOneWidget);
    expect(
      find.text('全${controller.bank!.cards.length}問を解放する'),
      findsOneWidget,
    );

    for (final unsupported in ['合格可能性', 'AI合否', '本番力']) {""",
        "purchase card test",
    )
    SHARED_TEST.write_text(text, encoding="utf-8")

    drone = DRONE_TEST.read_text(encoding="utf-8")
    if not drone.endswith("}\n"):
        raise RuntimeError("unexpected Drone test file ending")
    added = '''

  test('Drone free tier supports a 20-question random session', () async {
    final controller = createProductionController();
    await controller.initialize();
    addTearDown(controller.dispose);

    expect(controller.freeQuestionCount, 30);
    expect(controller.accessibleQuestionCount, 30);
    final started = await controller.startRandom();
    expect(started, isTrue);
    expect(controller.activeSession?.questionIds.length, 20);
  });
'''
    drone = drone[:-2] + added + "\n}\n"
    DRONE_TEST.write_text(drone, encoding="utf-8")


def main() -> None:
    selected = expand_free_tier()
    if len(selected) != 10:
        raise RuntimeError(f"expected 10 newly free questions, got {len(selected)}")
    update_bank_and_docs(selected)
    update_paywall_ui()
    update_progress_ui()
    update_tests()


if __name__ == "__main__":
    main()
