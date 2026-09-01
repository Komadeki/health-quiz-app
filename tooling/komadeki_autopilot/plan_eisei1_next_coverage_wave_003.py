#!/usr/bin/env python3
"""Materialize Eisei1's third bounded post-bootstrap coverage plan."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
STATE_PATH = REPO / "tooling/komadeki_autopilot/eisei1_state.json"
PLAN_PATH = REPO / "question_banks/eisei1/authoring/next_wave_plan_003.json"

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 15 or state.get("next_atomic_objective") != "PLAN_EISEI1_NEXT_COVERAGE_WAVE_003":
    raise SystemExit("unexpected Eisei1 state")
plan = json.loads(PLAN_PATH.read_text(encoding="utf-8"))
if plan.get("plan_id") != "E1-NEXT-WAVE-003" or plan.get("status") != "READY_FOR_AUTHORING":
    raise SystemExit("B12 plan contract drift")
if [item.get("knowledge_target_id") for item in plan.get("ranges", [])] != ["E1-LH-003", "E1-LH-004"]:
    raise SystemExit("B12 target selection drift")
if len(plan.get("ranges", [])) != 2 or plan.get("candidate_count_is_quota") is not False:
    raise SystemExit("B12 bounded non-quota contract drift")
state["observed_main"] = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
state["next_atomic_objective"] = "AUTHOR_EISEI1_COVERAGE_WAVE_003"
state["state_epoch"] = 16
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
