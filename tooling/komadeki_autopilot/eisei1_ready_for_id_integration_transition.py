#!/usr/bin/env python3
"""Allocate and integrate the only accepted Eisei1 bootstrap candidates."""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "tooling" / "question_bank"))

from contract import QUESTION_FIELDS  # noqa: E402
from expansion import validate_expansion_batch  # noqa: E402
from transaction import QuestionExpansionTransaction  # noqa: E402

BANK = REPOSITORY_ROOT / "question_banks" / "eisei1"
AUTHORING = BANK / "authoring"
SELECTED_BY_BATCH = {
    "batch_002": (
        "E1-B2-LH-C001",
        "E1-B2-LH-C002",
        "E1-B2-HH-C001",
        "E1-B2-HH-C002",
    ),
    "batch_003": ("E1-B3-LH-C001",),
    "batch_004": ("E1-B4-LH-C002", "E1-B4-LH-C004"),
}
EXPECTED = {
    "E1-B2-HH-C001": "EISEI1-Q-000001",
    "E1-B2-HH-C002": "EISEI1-Q-000002",
    "E1-B2-LH-C001": "EISEI1-Q-000003",
    "E1-B2-LH-C002": "EISEI1-Q-000004",
    "E1-B3-LH-C001": "EISEI1-Q-000005",
    "E1-B4-LH-C002": "EISEI1-Q-000006",
    "E1-B4-LH-C004": "EISEI1-Q-000007",
}
EXCLUDED = {
    "batch_003": ("E1-B3-HH-C001",),
    "batch_004": ("E1-B4-LH-C001", "E1-B4-LH-C003"),
    "batch_006": ("E1-B6-HH-C001",),
}


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def canonical_row(candidate: dict[str, str], question_id: str) -> dict[str, str]:
    """Bind a source-accepted five-choice candidate to the shared schema."""
    row = {field: "" for field in QUESTION_FIELDS}
    row.update(
        {
            "question_id": question_id,
            "question_version": "1",
            "status": "draft",
            "deck_id": "eisei1_exam",
            "unit_id": candidate["unit_id"],
            "question": candidate["question"],
            "choice1": candidate["choice1"],
            "choice2": candidate["choice2"],
            "choice3": candidate["choice3"],
            "choice4": candidate["choice4"],
            "choice5": candidate["choice5"],
            "correct_choice": candidate["proposed_correct"],
            "explanation": candidate["explanation"],
            "source_id": candidate["source_id"],
            "source_locator": candidate["source_locator"],
            "difficulty": "2",
            "importance": "3",
            "is_free": "false",
        }
    )
    return row


def assert_preconditions() -> None:
    metadata = json.loads((AUTHORING / "bank.json").read_text(encoding="utf-8"))
    if metadata.get("question_id_prefix") != "EISEI1" or metadata.get("expected_choice_count") != 5:
        raise SystemExit("Eisei1 bank metadata drift")
    if read_rows(AUTHORING / "questions.csv") or read_rows(AUTHORING / "question_id_registry.csv"):
        raise SystemExit("Eisei1 canonical bank or ID registry must be empty before initial allocation")
    for batch_name, selected in SELECTED_BY_BATCH.items():
        batch = AUTHORING / "batches" / batch_name
        rows = {row["candidate_id"]: row for row in read_rows(batch / "candidates.csv")}
        if any(rows.get(candidate_id, {}).get("state") != "READY_FOR_ID" or rows[candidate_id].get("permanent_question_id") for candidate_id in selected):
            raise SystemExit(f"{batch_name} selected candidate pre-ID state drift")
        packet_ids = {path.stem for path in (batch / "acceptance_packets").glob("*.json")}
        if packet_ids != set(selected):
            raise SystemExit(f"{batch_name} acceptance packet set drift")
    for batch_name, excluded in EXCLUDED.items():
        rows = {row["candidate_id"]: row for row in read_rows(AUTHORING / "batches" / batch_name / "candidates.csv")}
        if any(rows.get(candidate_id, {}).get("state") != "AI_PRE_ACCEPT" or rows[candidate_id].get("permanent_question_id") for candidate_id in excluded):
            raise SystemExit(f"{batch_name} excluded candidate state drift")


def assert_postconditions() -> None:
    questions = {row["question_id"]: row for row in read_rows(AUTHORING / "questions.csv")}
    registry = {row["question_id"]: row for row in read_rows(AUTHORING / "question_id_registry.csv")}
    if set(questions) != set(EXPECTED.values()) or set(registry) != set(EXPECTED.values()):
        raise SystemExit("Eisei1 canonical question or registry inventory drift")
    for batch_name, selected in SELECTED_BY_BATCH.items():
        batch = AUTHORING / "batches" / batch_name
        candidates = {row["candidate_id"]: row for row in read_rows(batch / "candidates.csv")}
        if {path.stem for path in (batch / "acceptance_packets").glob("*.json")} != set(selected):
            raise SystemExit(f"{batch_name} acceptance packets changed")
        for candidate_id in selected:
            question_id = EXPECTED[candidate_id]
            candidate, question, registry_row = candidates[candidate_id], questions[question_id], registry[question_id]
            if candidate["state"] != "INTEGRATED" or candidate["permanent_question_id"] != question_id:
                raise SystemExit(f"candidate integration mismatch: {candidate_id}")
            if any(question[field] != candidate[source] for field, source in (("question", "question"), ("choice1", "choice1"), ("choice2", "choice2"), ("choice3", "choice3"), ("choice4", "choice4"), ("choice5", "choice5"), ("correct_choice", "proposed_correct"), ("explanation", "explanation"), ("source_id", "source_id"), ("source_locator", "source_locator"))):
                raise SystemExit(f"canonical content mismatch: {candidate_id}")
            if (question["question_version"], question["status"], question["deck_id"], question["unit_id"], question["difficulty"], question["importance"], question["is_free"], question["valid_from"], question["last_reviewed_at"], question["tags"], question["notes_internal"]) != ("1", "draft", "eisei1_exam", candidate["unit_id"], "2", "3", "false", "", "", "", ""):
                raise SystemExit(f"canonical metadata mismatch: {question_id}")
            if (registry_row["status"], registry_row["first_used_bank_revision"], registry_row["retired_at"], registry_row["notes"]) != ("used", "", "", f"Expansion pre-release allocation: {candidate_id}"):
                raise SystemExit(f"registry mismatch: {question_id}")
    for batch_name, excluded in EXCLUDED.items():
        candidates = {row["candidate_id"]: row for row in read_rows(AUTHORING / "batches" / batch_name / "candidates.csv")}
        if any(candidates[candidate_id]["state"] != "AI_PRE_ACCEPT" or candidates[candidate_id]["permanent_question_id"] for candidate_id in excluded):
            raise SystemExit(f"{batch_name} excluded candidate mutated")
    if json.loads((AUTHORING / "source_verifications.json").read_text(encoding="utf-8"))["verifications"]:
        raise SystemExit("source verification must remain separate from integration")
    if json.loads((AUTHORING / "released_questions.json").read_text(encoding="utf-8"))["released_questions"]:
        raise SystemExit("release snapshot must remain unchanged")
    runtime = json.loads((BANK / "generated" / "eisei1_bank.json").read_text(encoding="utf-8"))
    if runtime.get("decks") != []:
        raise SystemExit("runtime generated output must remain unchanged")


def main() -> None:
    assert_preconditions()
    mapping: dict[str, str] = {}
    for batch_name, selected in SELECTED_BY_BATCH.items():
        transaction = QuestionExpansionTransaction(
            BANK,
            AUTHORING / "batches" / batch_name,
            selected,
            question_factory=canonical_row,
        )
        planned = transaction.plan().mapping
        expected = {candidate_id: EXPECTED[candidate_id] for candidate_id in selected}
        if planned != expected or transaction.apply() != expected:
            raise SystemExit(f"unexpected Eisei1 allocation for {batch_name}: {planned}")
        mapping.update(expected)
    if mapping != EXPECTED:
        raise SystemExit("incomplete Eisei1 allocation")
    assert_postconditions()
    for batch_name in SELECTED_BY_BATCH:
        errors = validate_expansion_batch(AUTHORING / "batches" / batch_name)
        if errors:
            raise SystemExit(f"{batch_name} expansion validation failed: {' | '.join(errors)}")


if __name__ == "__main__":
    main()
