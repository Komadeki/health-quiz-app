#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QB_TOOL = ROOT / "tooling" / "question_bank"
sys.path.insert(0, str(QB_TOOL))

from contract import QUESTION_FIELDS, read_csv  # noqa: E402
from transaction import QuestionExpansionTransaction  # noqa: E402

BANK = ROOT / "question_banks" / "drone_second_class"
BATCH = BANK / "authoring" / "batches" / "batch_004"
STATE_PATH = ROOT / "tooling" / "komadeki_autopilot" / "drone_state.json"
EXPECTED_OBJECTIVE = "ALLOCATE_AND_INTEGRATE_B4_OPERATIONS_ACCEPTED_19"
NEXT_OBJECTIVE = "VERIFY_B4_OPERATIONS_CANONICAL_SOURCES_19"
START_MAIN = "843613604165611e512ecb80cd9488dfea7c8836"
ACCEPTED = (
    "B4-OPS-C001", "B4-OPS-C002", "B4-OPS-C003", "B4-OPS-C004",
    "B4-OPS-C005", "B4-OPS-C006", "B4-OPS-C007", "B4-OPS-C008",
    "B4-OPS-C009", "B4-OPS-C010", "B4-OPS-C011", "B4-OPS-C012",
    "B4-OPS-C013", "B4-OPS-C014", "B4-OPS-C015", "B4-OPS-C017",
    "B4-OPS-C018", "B4-OPS-C019", "B4-OPS-C020",
)
EXPECTED_IDS = tuple(f"DRONE-Q-{number:06d}" for number in range(170, 189))


def canonical_row(candidate: dict[str, str], question_id: str) -> dict[str, str]:
    row = {field: "" for field in QUESTION_FIELDS}
    row.update({
        "question_id": question_id,
        "question_version": "1",
        "status": "draft",
        "deck_id": "drone_second_class_exam",
        "unit_id": "drone_operations",
        "question": candidate["question"],
        "choice1": candidate["choice1"],
        "choice2": candidate["choice2"],
        "choice3": candidate["choice3"],
        "choice4": candidate["choice4"],
        "correct_choice": candidate["proposed_correct"],
        "explanation": candidate["explanation"],
        "source_id": candidate["source_id"],
        "source_locator": candidate["source_locator"],
        "difficulty": "2",
        "importance": "2",
        "is_free": "false",
        "last_reviewed_at": "",
        "notes_internal": "",
    })
    return row


def main() -> int:
    state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
    if state.get("next_atomic_objective") != EXPECTED_OBJECTIVE:
        print(f"NOOP: current objective is {state.get('next_atomic_objective')!r}")
        return 0
    if state.get("state_epoch") != 20:
        raise RuntimeError(f"unexpected state_epoch: {state.get('state_epoch')!r}")

    packet_dir = BATCH / "acceptance_packets"
    packet_ids = {path.stem for path in packet_dir.glob("B4-OPS-C*.json")}
    if packet_ids != set(ACCEPTED):
        raise RuntimeError(f"acceptance packet set mismatch: {sorted(packet_ids)}")

    transaction = QuestionExpansionTransaction(
        BANK,
        BATCH,
        ACCEPTED,
        question_factory=canonical_row,
    )
    dry_run = transaction.dry_run()
    expected_mapping = dict(zip(ACCEPTED, EXPECTED_IDS))
    if dry_run != expected_mapping:
        raise RuntimeError(f"unexpected allocation mapping: {dry_run}")
    mapping = transaction.apply()
    if mapping != expected_mapping:
        raise RuntimeError(f"applied mapping differs: {mapping}")

    _, candidates = read_csv(BATCH / "candidates.csv")
    by_candidate = {row["candidate_id"]: row for row in candidates}
    for candidate_id, question_id in expected_mapping.items():
        row = by_candidate[candidate_id]
        if row["state"] != "INTEGRATED" or row["permanent_question_id"] != question_id:
            raise RuntimeError(f"candidate integration mismatch: {candidate_id}")
    rejected = by_candidate["B4-OPS-C016"]
    if rejected["state"] != "AI_PRE_ACCEPT" or rejected["permanent_question_id"]:
        raise RuntimeError("B4-OPS-C016 must remain rejected/unallocated")

    registry_fields, registry = read_csv(BANK / "authoring" / "question_id_registry.csv")
    registry_by_id = {row["question_id"]: row for row in registry}
    for candidate_id, question_id in expected_mapping.items():
        row = registry_by_id.get(question_id)
        if not row or row.get("status") != "used" or row.get("first_used_bank_revision"):
            raise RuntimeError(f"registry mismatch: {question_id}")
        if candidate_id not in row.get("notes", ""):
            raise RuntimeError(f"registry candidate binding mismatch: {question_id}")

    _, questions = read_csv(BANK / "authoring" / "questions.csv")
    if len(questions) != 188:
        raise RuntimeError(f"canonical inventory expected 188, got {len(questions)}")
    questions_by_id = {row["question_id"]: row for row in questions}
    for question_id in EXPECTED_IDS:
        row = questions_by_id.get(question_id)
        if not row:
            raise RuntimeError(f"canonical row missing: {question_id}")
        if row["status"] != "draft" or row["unit_id"] != "drone_operations" or row["is_free"] != "false":
            raise RuntimeError(f"canonical metadata mismatch: {question_id}")
        if row.get("last_reviewed_at") or row.get("notes_internal"):
            raise RuntimeError(f"canonical prerelease fields must remain blank: {question_id}")

    state["observed_main"] = START_MAIN
    state["next_atomic_objective"] = NEXT_OBJECTIVE
    state["state_epoch"] = 21
    STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(mapping, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
