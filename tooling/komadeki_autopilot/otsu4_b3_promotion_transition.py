#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tooling" / "question_bank"))
from ai_governance import promote_ai_governed_candidates
from expansion import validate_expansion_batch

BANK = REPO / "question_banks" / "otsu4"
AUTHORING = BANK / "authoring"
BATCH = AUTHORING / "batches" / "batch_003"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "otsu4_state.json"
ALL = tuple(f"O4-B3-LAW-C{i:03d}" for i in range(1, 25))
REJECTED = ("O4-B3-LAW-C016", "O4-B3-LAW-C017")
ACCEPTED = tuple(cid for cid in ALL if cid not in REJECTED)

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 38 or state.get("next_atomic_objective") != "PROMOTE_OTSU4_BATCH_3_ACCEPTED_22_TO_READY_FOR_ID":
    raise SystemExit(f"unexpected state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}")

with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as h:
    before = {r["candidate_id"]: r for r in csv.DictReader(h)}
if set(before) != set(ALL):
    raise SystemExit("unexpected Otsu4 Batch 3 candidate set")
if any(before[c]["state"] != "AI_PRE_ACCEPT" or before[c]["permanent_question_id"] for c in ALL):
    raise SystemExit("unexpected pre-promotion candidate state")
packets = BATCH / "acceptance_packets"
if {p.stem for p in packets.glob("*.json")} != set(ACCEPTED):
    raise SystemExit("Otsu4 Batch 3 acceptance packet set drift")

promote_ai_governed_candidates(BATCH, ACCEPTED)

with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as h:
    after = {r["candidate_id"]: r for r in csv.DictReader(h)}
if any(after[c]["state"] != "READY_FOR_ID" or after[c]["permanent_question_id"] for c in ACCEPTED):
    raise SystemExit("accepted Otsu4 Batch 3 promotion failed")
if any(after[c]["state"] != "AI_PRE_ACCEPT" or after[c]["permanent_question_id"] for c in REJECTED):
    raise SystemExit("rejected Otsu4 Batch 3 candidate mutated")

with (AUTHORING / "questions.csv").open(encoding="utf-8", newline="") as h:
    questions = list(csv.DictReader(h))
with (AUTHORING / "question_id_registry.csv").open(encoding="utf-8", newline="") as h:
    registry = list(csv.DictReader(h))
verifications = json.loads((AUTHORING / "source_verifications.json").read_text(encoding="utf-8"))["verifications"]
released = json.loads((AUTHORING / "released_questions.json").read_text(encoding="utf-8"))["released_questions"]
if len(questions) != 29 or len(registry) != 29 or len(verifications) != 29 or released:
    raise SystemExit("canonical/release baseline changed during Batch 3 promotion")
meta = json.loads((AUTHORING / "bank.json").read_text(encoding="utf-8"))
runtime = json.loads((BANK / meta["runtime_output"]).read_text(encoding="utf-8"))
runtime_count = sum(len(u.get("cards", [])) for d in runtime.get("decks", []) for u in d.get("units", []))
if runtime_count != 0:
    raise SystemExit("Otsu4 runtime baseline changed during Batch 3 promotion")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "origin/main"], text=True).strip()
state["state_epoch"] = 39
state["next_atomic_objective"] = "ALLOCATE_AND_INTEGRATE_OTSU4_BATCH_3_ACCEPTED_22"
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
errors = validate_expansion_batch(BATCH)
if errors:
    raise SystemExit("Otsu4 Batch 3 expansion validation failed: " + " | ".join(errors))
