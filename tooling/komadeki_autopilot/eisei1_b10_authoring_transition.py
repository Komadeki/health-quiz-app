#!/usr/bin/env python3
"""Record the bounded Eisei1 B10 authoring and independent-review transition."""

from __future__ import annotations

import csv
import json
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BATCH = REPO / "question_banks/eisei1/authoring/batches/batch_010"
STATE_PATH = REPO / "tooling/komadeki_autopilot/eisei1_state.json"
EXPECTED = {"E1-B10-LH-C001", "E1-B10-LH-C002", "E1-B10-LH-C003"}

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 6 or state.get("next_atomic_objective") != "AUTHOR_EISEI1_NEXT_COVERAGE_WAVE":
    raise SystemExit("unexpected Eisei1 state")

with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as handle:
    rows = list(csv.DictReader(handle))
if {row["candidate_id"] for row in rows} != EXPECTED:
    raise SystemExit("unexpected B10 candidate set")
if any(row["state"] != "AI_PRE_ACCEPT" or row["permanent_question_id"] for row in rows):
    raise SystemExit("B10 candidates must remain pre-acceptance and pre-ID")
if any(row["knowledge_target_id"] != "E1-LH-001" or row["source_id"] != "E1-LAW-ASR" for row in rows):
    raise SystemExit("B10 coverage/source binding drift")
if any(len({row[f"choice{i}"] for i in range(1, 6)}) != 5 for row in rows):
    raise SystemExit("B10 choices must be distinct")
if {path.stem for path in (BATCH / "acceptance_packets").glob("*.json")}:
    raise SystemExit("B10 acceptance packets must not exist before promotion")

review = json.loads((BATCH / "independent_review_r1.json").read_text(encoding="utf-8"))
if review.get("summary") != {"reviewed": 3, "accept": 3, "reject": 0, "rework": 0, "hold": 0}:
    raise SystemExit("B10 review summary drift")
if review.get("final_gate") != "READY_FOR_DIRECTOR_ACCEPT_AND_PROMOTE_ACCEPTED_3":
    raise SystemExit("B10 review gate drift")
if review.get("collision_review", {}).get("result") != "PASS":
    raise SystemExit("B10 collision review failed")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
state["next_atomic_objective"] = "ACCEPT_EISEI1_B10_CANDIDATES_3"
state["state_epoch"] = 7
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

