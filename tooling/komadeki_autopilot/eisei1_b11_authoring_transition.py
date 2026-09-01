#!/usr/bin/env python3
"""Record B11 authoring and independent review for E1-LH-002."""

from __future__ import annotations

import csv
import json
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BATCH = REPO / "question_banks/eisei1/authoring/batches/batch_011"
STATE_PATH = REPO / "tooling/komadeki_autopilot/eisei1_state.json"
IDS = {"E1-B11-LH-C001", "E1-B11-LH-C002", "E1-B11-LH-C003", "E1-B11-LH-C004"}

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 11 or state.get("next_atomic_objective") != "AUTHOR_EISEI1_COVERAGE_WAVE_002":
    raise SystemExit("unexpected Eisei1 state")
with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as handle:
    reader = csv.DictReader(handle, restval="")
    rows = list(reader)
if {row["candidate_id"] for row in rows} != IDS:
    raise SystemExit("unexpected B11 candidate set")
if any(row["state"] != "AI_PRE_ACCEPT" or row["permanent_question_id"] for row in rows):
    raise SystemExit("B11 candidates must remain pre-acceptance and pre-ID")
if any(row["knowledge_target_id"] != "E1-LH-002" or row["source_id"] not in {"E1-LAW-ASL", "E1-LAW-ASR"} for row in rows):
    raise SystemExit("B11 coverage/source binding drift")
if any(len({row[f"choice{i}"] for i in range(1, 6)}) != 5 for row in rows):
    raise SystemExit("B11 choices must be distinct")
review = json.loads((BATCH / "independent_review_r1.json").read_text(encoding="utf-8"))
if review.get("summary") != {"reviewed": 4, "accept": 4, "reject": 0, "rework": 0, "hold": 0}:
    raise SystemExit("B11 review summary drift")
if review.get("final_gate") != "READY_FOR_DIRECTOR_ACCEPT_AND_PROMOTE_ACCEPTED_4":
    raise SystemExit("B11 review gate drift")
if review.get("collision_review", {}).get("result") != "PASS":
    raise SystemExit("B11 collision review failed")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
state["next_atomic_objective"] = "ACCEPT_EISEI1_B11_CANDIDATES_4"
state["state_epoch"] = 12
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
