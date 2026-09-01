#!/usr/bin/env python3
"""Record B12 authoring and independent review."""
from __future__ import annotations
import csv,json,subprocess
from pathlib import Path
REPO=Path(__file__).resolve().parents[2]
BATCH=REPO/"question_banks/eisei1/authoring/batches/batch_012"
STATE=REPO/"tooling/komadeki_autopilot/eisei1_state.json"
EXPECTED={"E1-B12-LH-C001","E1-B12-LH-C002","E1-B12-LH-C003","E1-B12-LH-C004"}
state=json.loads(STATE.read_text(encoding="utf-8"))
if state.get("state_epoch")!=16 or state.get("next_atomic_objective")!="AUTHOR_EISEI1_COVERAGE_WAVE_003": raise SystemExit("unexpected Eisei1 state")
with (BATCH/"candidates.csv").open(encoding="utf-8",newline="") as h: rows=list(csv.DictReader(h,restval=""))
if {r["candidate_id"] for r in rows}!=EXPECTED or any(r["state"]!="AI_PRE_ACCEPT" or r["permanent_question_id"] for r in rows): raise SystemExit("B12 candidate state drift")
if any(r["knowledge_target_id"] not in {"E1-LH-003","E1-LH-004"} for r in rows): raise SystemExit("B12 target drift")
review=json.loads((BATCH/"independent_review_r1.json").read_text(encoding="utf-8"))
if review.get("summary")!={"reviewed":4,"accept":4,"reject":0,"rework":0,"hold":0} or review.get("final_gate")!="READY_FOR_DIRECTOR_ACCEPT_AND_PROMOTE_ACCEPTED_4": raise SystemExit("B12 review drift")
state["observed_main"]=subprocess.check_output(["git","rev-parse","HEAD"],text=True).strip()
state["next_atomic_objective"]="ACCEPT_EISEI1_B12_CANDIDATES_4"
state["state_epoch"]=17
STATE.write_text(json.dumps(state,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
