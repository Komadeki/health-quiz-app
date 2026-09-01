#!/usr/bin/env python3
"""Materialize Eisei1's second bounded post-bootstrap coverage plan."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
STATE_PATH = REPO / "tooling/komadeki_autopilot/eisei1_state.json"
PLAN_PATH = REPO / "question_banks/eisei1/authoring/next_wave_plan_002.json"

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 10 or state.get("next_atomic_objective") != "PLAN_EISEI1_NEXT_COVERAGE_WAVE_002":
    raise SystemExit("unexpected Eisei1 state")
plan = json.loads(PLAN_PATH.read_text(encoding="utf-8"))
if plan.get("plan_id") != "E1-NEXT-WAVE-002" or plan.get("status") != "READY_FOR_AUTHORING":
    raise SystemExit("B11 plan contract drift")
if [item.get("knowledge_target_id") for item in plan.get("ranges", [])] != ["E1-LH-002", "E1-HH-001"]:
    raise SystemExit("B11 target selection drift")
if len(plan.get("ranges", [])) != 2 or plan.get("candidate_count_is_quota") is not False:
    raise SystemExit("B11 bounded non-quota contract drift")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
state["next_atomic_objective"] = "AUTHOR_EISEI1_COVERAGE_WAVE_002"
state["state_epoch"] = 11
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

