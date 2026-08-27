#!/usr/bin/env python3
"""Integrate only the accepted Eisei1 B6 candidate into the canonical draft bank."""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "tooling" / "question_bank"))

from expansion import validate_expansion_batch  # noqa: E402
from transaction import QuestionExpansionTransaction  # noqa: E402
from eisei1_ready_for_id_integration_transition import canonical_row  # noqa: E402

BANK = REPOSITORY_ROOT / "question_banks" / "eisei1"
AUTHORING = BANK / "authoring"
BATCH = AUTHORING / "batches" / "batch_006"
CANDIDATE_ID = "E1-B6-HH-C001"
EXPECTED_ID = "EISEI1-Q-000008"
EXISTING_IDS = {f"EISEI1-Q-{number:06d}" for number in range(1, 8)}


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def indexed(path: Path, key: str) -> dict[str, dict[str, str]]:
    return {row[key]: row for row in read_rows(path)}


def main() -> None:
    metadata = json.loads((AUTHORING / "bank.json").read_text(encoding="utf-8"))
    if metadata.get("question_id_prefix") != "EISEI1" or metadata.get("expected_choice_count") != 5:
        raise SystemExit("Eisei1 bank metadata drift")

    questions_before = indexed(AUTHORING / "questions.csv", "question_id")
    registry_before = indexed(AUTHORING / "question_id_registry.csv", "question_id")
    candidates_before = indexed(BATCH / "candidates.csv", "candidate_id")
    candidate = candidates_before.get(CANDIDATE_ID, {})
    if set(questions_before) != EXISTING_IDS or set(registry_before) != EXISTING_IDS:
        raise SystemExit("Eisei1 canonical Q1-Q7 inventory drift")
    if candidate.get("state") != "READY_FOR_ID" or candidate.get("permanent_question_id"):
        raise SystemExit("B6 must be READY_FOR_ID with no permanent ID")
    if {path.stem for path in (BATCH / "acceptance_packets").glob("*.json")} != {CANDIDATE_ID}:
        raise SystemExit("B6 acceptance packet set drift")

    untouched = {
        path: path.read_bytes()
        for path in (
            AUTHORING / "source_verifications.json",
            AUTHORING / "released_questions.json",
            BANK / "generated" / "eisei1_bank.json",
            AUTHORING / "bank.json",
            AUTHORING / "batches" / "batch_007" / "candidates.csv",
        )
    }
    transaction = QuestionExpansionTransaction(BANK, BATCH, (CANDIDATE_ID,), question_factory=canonical_row)
    if transaction.plan().mapping != {CANDIDATE_ID: EXPECTED_ID}:
        raise SystemExit("shared transaction did not allocate the next Eisei1 ID")
    if transaction.apply() != {CANDIDATE_ID: EXPECTED_ID}:
        raise SystemExit("B6 integration allocation mismatch")

    questions_after = indexed(AUTHORING / "questions.csv", "question_id")
    registry_after = indexed(AUTHORING / "question_id_registry.csv", "question_id")
    candidate_after = indexed(BATCH / "candidates.csv", "candidate_id")[CANDIDATE_ID]
    if any(questions_after[question_id] != questions_before[question_id] for question_id in EXISTING_IDS):
        raise SystemExit("existing canonical Eisei1 drafts changed")
    if set(questions_after) != EXISTING_IDS | {EXPECTED_ID} or set(registry_after) != EXISTING_IDS | {EXPECTED_ID}:
        raise SystemExit("B6 canonical inventory mismatch")
    if candidate_after.get("state") != "INTEGRATED" or candidate_after.get("permanent_question_id") != EXPECTED_ID:
        raise SystemExit("B6 candidate integration state mismatch")
    question = questions_after[EXPECTED_ID]
    for field, source in (("question", "question"), ("choice1", "choice1"), ("choice2", "choice2"), ("choice3", "choice3"), ("choice4", "choice4"), ("choice5", "choice5"), ("correct_choice", "proposed_correct"), ("explanation", "explanation"), ("source_id", "source_id"), ("source_locator", "source_locator")):
        if question[field] != candidate_after[source]:
            raise SystemExit(f"B6 canonical content mismatch: {field}")
    if registry_after[EXPECTED_ID].get("notes") != f"Expansion pre-release allocation: {CANDIDATE_ID}":
        raise SystemExit("B6 registry provenance mismatch")
    if any(path.read_bytes() != before for path, before in untouched.items()):
        raise SystemExit("out-of-scope Eisei1 artifact changed")
    if errors := validate_expansion_batch(BATCH):
        raise SystemExit(f"B6 expansion validation failed: {' | '.join(errors)}")


if __name__ == "__main__":
    main()
