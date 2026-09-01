#!/usr/bin/env python3
"""Integrate the three accepted Eisei1 B9 candidates without release mutation."""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tooling" / "question_bank"))

from expansion import validate_expansion_batch  # noqa: E402
from transaction import QuestionExpansionTransaction  # noqa: E402
from eisei1_ready_for_id_integration_transition import canonical_row  # noqa: E402

BANK = REPO / "question_banks" / "eisei1"
AUTHORING = BANK / "authoring"
BATCH = AUTHORING / "batches" / "batch_009"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "eisei1_state.json"
SELECTED = ("E1-B9-LH-C001", "E1-B9-LH-C002", "E1-B9-LH-C003")
EXPECTED = {
    "E1-B9-LH-C001": "EISEI1-Q-000014",
    "E1-B9-LH-C002": "EISEI1-Q-000015",
    "E1-B9-LH-C003": "EISEI1-Q-000016",
}
EXISTING_IDS = {f"EISEI1-Q-{number:06d}" for number in range(1, 14)}


def rows(path: Path, key: str) -> dict[str, dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return {row[key]: row for row in csv.DictReader(handle)}


def main() -> None:
    state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    if state.get("state_epoch") != 3 or state.get("next_atomic_objective") != "ALLOCATE_AND_INTEGRATE_EISEI1_B9_ACCEPTED_3":
        raise SystemExit("unexpected Eisei1 state")
    questions_before = rows(AUTHORING / "questions.csv", "question_id")
    registry_before = rows(AUTHORING / "question_id_registry.csv", "question_id")
    candidates_before = rows(BATCH / "candidates.csv", "candidate_id")
    if set(questions_before) != EXISTING_IDS or set(registry_before) != EXISTING_IDS:
        raise SystemExit("canonical inventory drift before B9 integration")
    if any(candidates_before.get(candidate_id, {}).get("state") != "READY_FOR_ID" or candidates_before[candidate_id].get("permanent_question_id") for candidate_id in SELECTED):
        raise SystemExit("B9 candidates must be unallocated READY_FOR_ID rows")
    if {path.stem for path in (BATCH / "acceptance_packets").glob("*.json")} != set(SELECTED):
        raise SystemExit("B9 acceptance packet set drift")
    untouched = {path: path.read_bytes() for path in (AUTHORING / "source_verifications.json", AUTHORING / "released_questions.json", BANK / "generated" / "eisei1_bank.json")}
    transaction = QuestionExpansionTransaction(BANK, BATCH, SELECTED, question_factory=canonical_row)
    if transaction.plan().mapping != EXPECTED or transaction.apply() != EXPECTED:
        raise SystemExit("unexpected B9 permanent-ID allocation")
    questions_after = rows(AUTHORING / "questions.csv", "question_id")
    registry_after = rows(AUTHORING / "question_id_registry.csv", "question_id")
    candidates_after = rows(BATCH / "candidates.csv", "candidate_id")
    if any(questions_after[question_id] != questions_before[question_id] for question_id in EXISTING_IDS):
        raise SystemExit("existing canonical rows changed")
    if set(questions_after) != EXISTING_IDS | set(EXPECTED.values()) or set(registry_after) != set(questions_after):
        raise SystemExit("B9 canonical inventory mismatch")
    for candidate_id, question_id in EXPECTED.items():
        if candidates_after[candidate_id]["state"] != "INTEGRATED" or candidates_after[candidate_id]["permanent_question_id"] != question_id:
            raise SystemExit("B9 candidate lifecycle mismatch")
        if registry_after[question_id]["notes"] != f"Expansion pre-release allocation: {candidate_id}":
            raise SystemExit("B9 registry provenance mismatch")
    if any(path.read_bytes() != value for path, value in untouched.items()):
        raise SystemExit("B9 integration mutated out-of-scope artifact")
    if errors := validate_expansion_batch(BATCH):
        raise SystemExit("B9 expansion validation failed: " + " | ".join(errors))
    state["next_atomic_objective"] = "VERIFY_EISEI1_B9_CANONICAL_SOURCES_3"
    state["state_epoch"] = 4
    STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
