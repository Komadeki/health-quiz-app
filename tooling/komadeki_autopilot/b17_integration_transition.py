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
BATCH = AUTHORING / "batches" / "batch_017"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "drone_state.json"
ALL = tuple(f"B17-SYS-C{i:03d}" for i in range(1, 6))
EXPECTED = {cid: f"DRONE-Q-{n:06d}" for cid, n in zip(ALL, range(361, 366))}

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 120 or state.get("next_atomic_objective") != "ALLOCATE_AND_INTEGRATE_B17_ACCEPTED_5":
    raise SystemExit(f"unexpected state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}")


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as h:
        return list(csv.DictReader(h))


before = {r["candidate_id"]: r for r in read_csv(BATCH / "candidates.csv")}
if set(before) != set(ALL):
    raise SystemExit("unexpected B17 candidate set")
if any(before[c]["state"] != "READY_FOR_ID" or before[c]["permanent_question_id"] for c in ALL):
    raise SystemExit("B17 pre-ID state mismatch")
packets = BATCH / "acceptance_packets"
if {p.stem for p in packets.glob("*.json")} != set(ALL):
    raise SystemExit("unexpected B17 acceptance packet set")


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
    raise SystemExit(f"unexpected B17 allocation: {tx.plan().mapping}")
if tx.apply() != EXPECTED:
    raise SystemExit("applied B17 mapping drift")

after = {r["candidate_id"]: r for r in read_csv(BATCH / "candidates.csv")}
questions = {r["question_id"]: r for r in read_csv(AUTHORING / "questions.csv")}
registry = {r["question_id"]: r for r in read_csv(AUTHORING / "question_id_registry.csv")}
for cid, qid in EXPECTED.items():
    c, q, reg = after[cid], questions[qid], registry[qid]
    if c["state"] != "INTEGRATED" or c["permanent_question_id"] != qid:
        raise SystemExit(f"candidate integration mismatch: {cid}")
    if q["status"] != "draft" or q["unit_id"] != "drone_systems":
        raise SystemExit(f"canonical draft mismatch: {qid}")
    if q["question"] != c["question"] or q["correct_choice"] != c["proposed_correct"] or q["source_locator"] != c["source_locator"]:
        raise SystemExit(f"canonical content mismatch: {qid}")
    if reg["status"] != "used" or reg["first_used_bank_revision"] or reg["retired_at"]:
        raise SystemExit(f"registry mismatch: {qid}")
if len(questions) != 365:
    raise SystemExit(f"canonical inventory must be 365, got {len(questions)}")

verified_ids = {r["question_id"] for r in json.loads((AUTHORING / "source_verifications.json").read_text(encoding="utf-8"))["verifications"]}
if any(qid in verified_ids for qid in EXPECTED.values()):
    raise SystemExit("source verification must not occur during integration")
if len(json.loads((AUTHORING / "released_questions.json").read_text(encoding="utf-8"))["released_questions"]) != 188:
    raise SystemExit("released baseline changed")
meta = json.loads((AUTHORING / "bank.json").read_text(encoding="utf-8"))
runtime = json.loads((BANK / meta["runtime_output"]).read_text(encoding="utf-8"))
if sum(len(u.get("cards", [])) for d in runtime.get("decks", []) for u in d.get("units", [])) != 188:
    raise SystemExit("runtime baseline changed")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "origin/main"], text=True).strip()
state["state_epoch"] = 121
state["next_atomic_objective"] = "VERIFY_B17_CANONICAL_SOURCES_5"
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
errors = validate_expansion_batch(BATCH)
if errors:
    raise SystemExit("B17 expansion validation failed: " + " | ".join(errors))
