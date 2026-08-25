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
BATCH = AUTHORING / "batches" / "batch_018"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "drone_state.json"
ALL = tuple(f"B18-RULE-C{i:03d}" for i in range(1, 7))
EXPECTED = {cid: f"DRONE-Q-{n:06d}" for cid, n in zip(ALL, range(366, 372))}

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 129 or state.get("next_atomic_objective") != "ALLOCATE_AND_INTEGRATE_B18_ACCEPTED_6":
    raise SystemExit(f"unexpected state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}")
release_cut = json.loads((AUTHORING / "owner_release_cut_371_2026-08-25.json").read_text(encoding="utf-8"))
cut = release_cut.get("release_cut", {})
if release_cut.get("status") != "ACTIVE" or cut.get("final_source_verified_canonical_after_b18") != 371 or cut.get("new_authoring_after_b18") != "CLOSED_FOR_THIS_RELEASE":
    raise SystemExit("371 release-cut contract drift")


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


before = {r["candidate_id"]: r for r in read_csv(BATCH / "candidates.csv")}
if set(before) != set(ALL):
    raise SystemExit("unexpected B18 candidate set")
if any(before[c]["state"] != "READY_FOR_ID" or before[c]["permanent_question_id"] for c in ALL):
    raise SystemExit("B18 pre-ID state mismatch")
packets = BATCH / "acceptance_packets"
if {p.stem for p in packets.glob("*.json")} != set(ALL):
    raise SystemExit("unexpected B18 acceptance packet set")


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
    raise SystemExit(f"unexpected B18 allocation: {tx.plan().mapping}")
if tx.apply() != EXPECTED:
    raise SystemExit("applied B18 mapping drift")

after = {r["candidate_id"]: r for r in read_csv(BATCH / "candidates.csv")}
questions = {r["question_id"]: r for r in read_csv(AUTHORING / "questions.csv")}
registry = {r["question_id"]: r for r in read_csv(AUTHORING / "question_id_registry.csv")}
for cid, qid in EXPECTED.items():
    c, q, reg = after[cid], questions[qid], registry[qid]
    if c["state"] != "INTEGRATED" or c["permanent_question_id"] != qid:
        raise SystemExit(f"candidate integration mismatch: {cid}")
    if q["status"] != "draft" or q["unit_id"] != "drone_rules":
        raise SystemExit(f"canonical draft mismatch: {qid}")
    if q["question"] != c["question"] or q["correct_choice"] != c["proposed_correct"] or q["source_locator"] != c["source_locator"]:
        raise SystemExit(f"canonical content mismatch: {qid}")
    if reg["status"] != "used" or reg["first_used_bank_revision"] or reg["retired_at"]:
        raise SystemExit(f"registry mismatch: {qid}")
if len(questions) != 371:
    raise SystemExit(f"canonical inventory must be 371, got {len(questions)}")

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
state["state_epoch"] = 130
state["next_atomic_objective"] = "VERIFY_B18_CANONICAL_SOURCES_6"
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
errors = validate_expansion_batch(BATCH)
if errors:
    raise SystemExit("B18 expansion validation failed: " + " | ".join(errors))
