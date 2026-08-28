#!/usr/bin/env python3
"""Select the next Otsu4 authoring batch from durable, verified evidence.

This is deliberately a planner, not a question generator.  A selected batch
must still pass the existing source-bound candidate, review, integration and
verification gates before it can update the canonical bank.
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from pathlib import Path
from typing import Any


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected object: {path}")
    return value


def build_plan(bank_root: Path) -> dict[str, Any]:
    authoring = bank_root / "authoring"
    config = _read_json(authoring / "autonomous_loop_300q_v1.json")
    minimums = config["knowledge_target_verified_draft_minimums"]
    verified = Counter()
    families: dict[str, set[str]] = {target: set() for target in minimums}
    difficulties = Counter()
    answer_positions = Counter()

    questions: dict[str, dict[str, str]] = {}
    with (authoring / "questions.csv").open(encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            questions[row["question_id"]] = row
            answer_positions[row["correct_choice"]] += 1
            difficulties[row["difficulty"]] += 1
    verification_ids = {
        str(item.get("question_id", ""))
        for item in _read_json(authoring / "source_verifications.json").get("verifications", [])
        if isinstance(item, dict)
        and item.get("verification_state") == "author_source_verified"
    }

    for candidate_path in sorted((authoring / "batches").glob("batch_*/candidates.csv")):
        with candidate_path.open(encoding="utf-8", newline="") as handle:
            for row in csv.DictReader(handle):
                question_id = row.get("permanent_question_id", "")
                target = row.get("knowledge_target_id", "")
                if row.get("state") != "VERIFIED" or not question_id or target not in minimums:
                    continue
                if question_id not in questions:
                    raise ValueError(f"verified candidate is absent from canonical bank: {question_id}")
                if question_id not in verification_ids:
                    raise ValueError(f"verified candidate lacks source-verification evidence: {question_id}")
                verified[target] += 1
                if row.get("family"):
                    families[target].add(row["family"])

    deficits = [
        {
            "knowledge_target_id": target,
            "verified_draft_count": verified[target],
            "minimum": minimum,
            "deficit": max(0, minimum - verified[target]),
            "distinct_families": len(families[target]),
        }
        for target, minimum in minimums.items()
    ]
    deficits.sort(key=lambda item: (-item["deficit"], item["distinct_families"], item["knowledge_target_id"]))
    next_target = deficits[0]
    batch_config = config["batch_size"]
    batch_size = 0 if next_target["deficit"] == 0 else max(
        batch_config["minimum"], min(batch_config["maximum"], next_target["deficit"])
    )
    return {
        "stage_id": config["stage_id"],
        "first_quality_gate_question_count": config["first_quality_gate_question_count"],
        "canonical_draft_count": len(questions),
        "next_batch": {
            "knowledge_target_id": next_target["knowledge_target_id"] if batch_size else None,
            "candidate_ceiling": batch_size,
            "must_be_source_verified_before_integration": config["source_verification_required_before_integration"],
            "filler_prohibited": config["filler_prohibited"],
        },
        "coverage_deficits": deficits,
        "quality_monitoring": {
            "correct_choice_position_counts": dict(sorted(answer_positions.items())),
            "difficulty_counts": dict(sorted(difficulties.items())),
            "near_duplicate_review": "Required in the existing independent-review gate; this planner does not claim semantic equivalence detection.",
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bank", required=True, type=Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    plan = build_plan(args.bank)
    if args.json:
        print(json.dumps(plan, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(json.dumps(plan, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
