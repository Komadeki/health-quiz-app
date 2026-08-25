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

BANK = REPO / "question_banks" / "otsu4"
AUTHORING = BANK / "authoring"
BATCH = AUTHORING / "batches" / "batch_003"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "otsu4_state.json"
ALL = tuple(f"O4-B3-LAW-C{i:03d}" for i in range(1, 25))
REJECTED = ("O4-B3-LAW-C016", "O4-B3-LAW-C017")
ACCEPTED = tuple(cid for cid in ALL if cid not in REJECTED)
EXPECTED = {cid: f"OTSU4-Q-{n:06d}" for cid, n in zip(ACCEPTED, range(30, 52))}

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 39 or state.get("next_atomic_objective") != "ALLOCATE_AND_INTEGRATE_OTSU4_BATCH_3_ACCEPTED_22":
    raise SystemExit(f"unexpected state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}")

with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as h:
    before = {r["candidate_id"]: r for r in csv.DictReader(h)}
if set(before) != set(ALL):
    raise SystemExit("unexpected Otsu4 Batch 3 candidate set")
if any(before[c]["state"] != "READY_FOR_ID" or before[c]["permanent_question_id"] for c in ACCEPTED):
    raise SystemExit("accepted Otsu4 Batch 3 pre-ID state mismatch")
if any(before[c]["state"] != "AI_PRE_ACCEPT" or before[c]["permanent_question_id"] for c in REJECTED):
    raise SystemExit("rejected Otsu4 Batch 3 state mismatch")
if {p.stem for p in (BATCH / "acceptance_packets").glob("*.json")} != set(ACCEPTED):
    raise SystemExit("Otsu4 Batch 3 acceptance packet set drift")

def canonical_row(candidate: dict[str, str], question_id: str) -> dict[str, str]:
    return {
        "question_id": question_id,
        "question_version": "1",
        "status": "draft",
        "deck_id": "otsu4_law",
        "unit_id": "otsu4_law",
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
        "importance": "3",
        "is_free": "false",
        "valid_from": "",
        "valid_until": "",
        "last_reviewed_at": "",
        "supersedes_id": "",
        "tags": "",
        "notes_internal": "",
    }

transaction = QuestionExpansionTransaction(BANK, BATCH, ACCEPTED, question_factory=canonical_row)
plan = transaction.plan()
if plan.mapping != EXPECTED:
    raise SystemExit(f"unexpected Otsu4 Batch 3 allocation: {plan.mapping}")
if transaction.apply() != EXPECTED:
    raise SystemExit("Otsu4 Batch 3 applied mapping drift")

with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as h:
    after = {r["candidate_id"]: r for r in csv.DictReader(h)}
with (AUTHORING / "questions.csv").open(encoding="utf-8", newline="") as h:
    questions = {r["question_id"]: r for r in csv.DictReader(h)}
with (AUTHORING / "question_id_registry.csv").open(encoding="utf-8", newline="") as h:
    registry = {r["question_id"]: r for r in csv.DictReader(h)}
for cid, qid in EXPECTED.items():
    c = after[cid]
    q = questions[qid]
    reg = registry[qid]
    if c["state"] != "INTEGRATED" or c["permanent_question_id"] != qid:
        raise SystemExit(f"candidate integration mismatch: {cid}")
    if q["status"] != "draft" or q["unit_id"] != "otsu4_law" or q["deck_id"] != "otsu4_law":
        raise SystemExit(f"canonical draft mismatch: {qid}")
    if q["question"] != c["question"] or q["correct_choice"] != c["proposed_correct"] or q["source_id"] != c["source_id"] or q["source_locator"] != c["source_locator"]:
        raise SystemExit(f"canonical content mismatch: {qid}")
    if reg["status"] != "used" or reg["first_used_bank_revision"] or reg["retired_at"]:
        raise SystemExit(f"registry mismatch: {qid}")
if any(after[c]["state"] != "AI_PRE_ACCEPT" or after[c]["permanent_question_id"] for c in REJECTED):
    raise SystemExit("rejected Otsu4 Batch 3 candidate mutated")
if len(questions) != 51 or len(registry) != 51:
    raise SystemExit(f"Otsu4 canonical/registry inventory mismatch: {len(questions)} / {len(registry)}")

verifications = json.loads((AUTHORING / "source_verifications.json").read_text(encoding="utf-8"))["verifications"]
verified_ids = {r["question_id"] for r in verifications}
if len(verifications) != 29 or any(qid in verified_ids for qid in EXPECTED.values()):
    raise SystemExit("source verification must remain separate from Batch 3 integration")
released = json.loads((AUTHORING / "released_questions.json").read_text(encoding="utf-8"))["released_questions"]
if released:
    raise SystemExit("Otsu4 released baseline changed")
meta = json.loads((AUTHORING / "bank.json").read_text(encoding="utf-8"))
runtime = json.loads((BANK / meta["runtime_output"]).read_text(encoding="utf-8"))
runtime_count = sum(len(u.get("cards", [])) for d in runtime.get("decks", []) for u in d.get("units", []))
if runtime_count != 0:
    raise SystemExit("Otsu4 runtime baseline changed")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "origin/main"], text=True).strip()
state["state_epoch"] = 40
state["next_atomic_objective"] = "VERIFY_OTSU4_BATCH_3_CANONICAL_SOURCES_22"
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
errors = validate_expansion_batch(BATCH)
if errors:
    raise SystemExit("Otsu4 Batch 3 expansion validation failed: " + " | ".join(errors))
