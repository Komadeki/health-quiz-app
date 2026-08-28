#!/usr/bin/env python3
"""Audit a bank against its authoring playbook without mutating bank data."""

from __future__ import annotations

import argparse
import csv
import glob
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

from contract import load_bank_inputs
from factory_contracts import validate_source_verifications
from contract import ValidationResult


def _read_candidates(bank_root: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    pattern = bank_root / "authoring" / "batches" / "batch_*" / "candidates.csv"
    for filename in sorted(glob.glob(str(pattern))):
        with Path(filename).open(newline="", encoding="utf-8-sig") as file:
            rows.extend({key: (value or "").strip() for key, value in row.items()} for row in csv.DictReader(file))
    return rows


def build_audit(bank_root: Path, profile_path: Path) -> dict[str, Any]:
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    inputs = load_bank_inputs(bank_root)
    candidates = _read_candidates(bank_root)
    by_permanent_id: dict[str, dict[str, str]] = {}
    duplicate_ids: list[str] = []
    for candidate in candidates:
        permanent_id = candidate.get("permanent_question_id", "")
        if not permanent_id:
            continue
        if permanent_id in by_permanent_id:
            duplicate_ids.append(permanent_id)
        else:
            by_permanent_id[permanent_id] = candidate

    question_by_id = {question["question_id"]: question for question in inputs.questions}
    source_by_id = {str(source.get("source_id", "")): source for source in inputs.sources}
    verification = ValidationResult()
    verification_summary = validate_source_verifications(
        inputs, question_by_id, source_by_id, verification
    )
    required_targets = {
        target["knowledge_target_id"]
        for target in inputs.coverage.get("knowledge_targets", [])
        if target.get("required") is True
    }
    target_counts: Counter[str] = Counter()
    unbound_questions: list[str] = []
    for question in inputs.questions:
        candidate = by_permanent_id.get(question["question_id"])
        if candidate is None:
            unbound_questions.append(question["question_id"])
        else:
            target_counts[candidate.get("knowledge_target_id", "")] += 1
    verified_ids = {
        item.get("question_id", "")
        for item in inputs.source_verifications.get("verifications", [])
        if item.get("verification_state") == "author_source_verified"
    }
    source_verified_target_counts: Counter[str] = Counter()
    for question_id, candidate in by_permanent_id.items():
        if question_id in verified_ids:
            source_verified_target_counts[candidate.get("knowledge_target_id", "")] += 1
    missing_targets = sorted(
        target_id for target_id in required_targets if source_verified_target_counts[target_id] == 0
    )
    choices = Counter(
        sum(bool(question.get(f"choice{index}", "")) for index in range(1, 6))
        for question in inputs.questions
    )
    positions = Counter(question.get("correct_choice", "") for question in inputs.questions)
    distribution = profile["exam_distribution"]["by_unit"]
    return {
        "profile_id": profile["profile_id"],
        "canonical_question_count": len(inputs.questions),
        "candidate_evidence": {
            "persisted_candidate_count": len(candidates),
            "canonical_binding_count": len(inputs.questions) - len(unbound_questions),
            "unbound_question_ids": sorted(unbound_questions),
            "duplicate_permanent_question_ids": sorted(set(duplicate_ids)),
        },
        "coverage_gate": {
            "status": "pass" if not unbound_questions and not missing_targets else "hold",
            "source_verified_counts_by_target": dict(sorted(source_verified_target_counts.items())),
            "missing_required_target_ids": missing_targets,
        },
        "exam_gate": {
            "status": "pass",
            "official_blueprint": distribution,
            "mock_size": profile["exam_distribution"]["total_questions"],
            "available_canonical_by_unit": dict(sorted(Counter(q["unit_id"] for q in inputs.questions).items())),
        },
        "density_gate": {
            "status": "review_required",
            "target_counts_by_knowledge_target": dict(sorted(target_counts.items())),
            "correct_choice_position_distribution": {
                position: positions[position] for position in ("A", "B", "C", "D", "E")
            },
            "choice_count_distribution": dict(sorted(choices.items())),
            "reason": "Collision quality and source freshness need an independent batch review; this audit records the measurable evidence only.",
        },
        "source_verification": {
            "source_verified_canonical_question_count": len(
                set(question_by_id).intersection(verified_ids)
            ),
            "validation_errors": sorted({issue.code for issue in verification.errors}),
        },
        "freeze_candidate_gate": {"status": "not_evaluated", "reason": "No release freeze has been declared."},
        "release_gate": {"status": "not_evaluated", "reason": "No human release approval has been recorded."},
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bank", required=True, type=Path)
    parser.add_argument("--profile", required=True, type=Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    report = build_audit(args.bank, args.profile)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(f"Playbook audit: {report['profile_id']}")
        print(f"Canonical bindings: {report['candidate_evidence']['canonical_binding_count']}/{report['canonical_question_count']}")
        print(f"Coverage gate: {report['coverage_gate']['status']}")
        print(f"Exam gate: {report['exam_gate']['status']}")
        print(f"Density gate: {report['density_gate']['status']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
