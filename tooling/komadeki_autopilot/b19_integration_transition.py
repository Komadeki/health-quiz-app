#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tooling" / "question_bank"))
from expansion import validate_expansion_batch
from transaction import QuestionExpansionTransaction

BANK = REPO / "question_banks" / "drone_second_class"
AUTHORING = BANK / "authoring"
BATCH = AUTHORING / "batches" / "batch_019"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "drone_state.json"
ALL = tuple(f"B19-RULE-C{i:03d}" for i in range(1, 16))
EXPECTED = {cid: f"DRONE-Q-{n:06d}" for cid, n in zip(ALL, range(372, 387))}

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 139 or state.get("next_atomic_objective") != "ALLOCATE_AND_INTEGRATE_B19_ACCEPTED_15":
    raise SystemExit(f"unexpected state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}")

policy = json.loads((AUTHORING / "owner_dynamic_release_inclusion_2026-08-26.json").read_text(encoding="utf-8"))
release_policy = policy.get("release_policy", {})
current_facts = policy.get("current_facts", {})
if (
    policy.get("status") != "ACTIVE"
    or release_policy.get("fixed_release_question_count") is not None
    or release_policy.get("release_progression_blocked_by_400_target") is not False
    or "B19" not in release_policy.get("in_flight_batch_rule", "")
    or current_facts.get("b20_before_current_release") != "PROHIBITED"
):
    raise SystemExit("dynamic release policy drift")


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


before = {row["candidate_id"]: row for row in read_csv(BATCH / "candidates.csv")}
if set(before) != set(ALL):
    raise SystemExit("unexpected B19 candidate set")
if any(before[c]["state"] != "READY_FOR_ID" or before[c]["permanent_question_id"] for c in ALL):
    raise SystemExit("B19 pre-ID state mismatch")
packets = BATCH / "acceptance_packets"
if {path.stem for path in packets.glob("*.json")} != set(ALL):
    raise SystemExit("unexpected B19 acceptance packet set")


def canonical_row(candidate: dict[str, str], question_id: str) -> dict[str, str]:
    return {
        "question_id": question_id,
        "question_version": "1",
        "status": "draft",
        "deck_id": "drone_second_class_exam",
        "unit_id": candidate["unit_id"],
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
        "valid_from": "",
        "valid_until": "",
        "last_reviewed_at": "",
        "supersedes_id": "",
        "tags": "",
        "notes_internal": "",
    }


tx = QuestionExpansionTransaction(BANK, BATCH, ALL, question_factory=canonical_row)
if tx.plan().mapping != EXPECTED:
    raise SystemExit(f"unexpected B19 allocation: {tx.plan().mapping}")
if tx.apply() != EXPECTED:
    raise SystemExit("applied B19 mapping drift")

after = {row["candidate_id"]: row for row in read_csv(BATCH / "candidates.csv")}
questions = {row["question_id"]: row for row in read_csv(AUTHORING / "questions.csv")}
registry = {row["question_id"]: row for row in read_csv(AUTHORING / "question_id_registry.csv")}
for cid, qid in EXPECTED.items():
    candidate = after[cid]
    question = questions[qid]
    reg = registry[qid]
    if candidate["state"] != "INTEGRATED" or candidate["permanent_question_id"] != qid:
        raise SystemExit(f"candidate integration mismatch: {cid}")
    if question["status"] != "draft" or question["unit_id"] != "drone_rules":
        raise SystemExit(f"canonical draft mismatch: {qid}")
    if (
        question["question"] != candidate["question"]
        or question["correct_choice"] != candidate["proposed_correct"]
        or question["source_locator"] != candidate["source_locator"]
    ):
        raise SystemExit(f"canonical content mismatch: {qid}")
    if reg["status"] != "used" or reg["first_used_bank_revision"] or reg["retired_at"]:
        raise SystemExit(f"registry mismatch: {qid}")
if len(questions) != 386:
    raise SystemExit(f"canonical inventory must be 386, got {len(questions)}")

verified_ids = {
    row["question_id"]
    for row in json.loads((AUTHORING / "source_verifications.json").read_text(encoding="utf-8"))["verifications"]
}
if any(qid in verified_ids for qid in EXPECTED.values()):
    raise SystemExit("source verification must not occur during B19 integration")
if len(json.loads((AUTHORING / "released_questions.json").read_text(encoding="utf-8"))["released_questions"]) != 188:
    raise SystemExit("released baseline changed")
meta = json.loads((AUTHORING / "bank.json").read_text(encoding="utf-8"))
runtime = json.loads((BANK / meta["runtime_output"]).read_text(encoding="utf-8"))
if sum(len(unit.get("cards", [])) for deck in runtime.get("decks", []) for unit in deck.get("units", [])) != 188:
    raise SystemExit("runtime baseline changed")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "origin/main"], text=True).strip()
state["state_epoch"] = 140
state["next_atomic_objective"] = "VERIFY_B19_CANONICAL_SOURCES_15"
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

errors = validate_expansion_batch(BATCH)
if errors:
    raise SystemExit("B19 expansion validation failed: " + " | ".join(errors))
