#!/usr/bin/env python3
"""Materialize the next bounded Eisei1 coverage wave plan."""

from __future__ import annotations

import csv
import json
import subprocess
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BANK = REPO / "question_banks" / "eisei1"
AUTHORING = BANK / "authoring"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "eisei1_state.json"
PLAN_PATH = AUTHORING / "next_wave_plan.json"

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 5 or state.get("next_atomic_objective") != "PLAN_EISEI1_NEXT_COVERAGE_WAVE":
    raise SystemExit("unexpected Eisei1 state")

rows: list[dict[str, str]] = []
for path in sorted((AUTHORING / "batches").glob("batch_*/candidates.csv")):
    with path.open(encoding="utf-8", newline="") as handle:
        rows.extend(csv.DictReader(handle))
covered = {row["knowledge_target_id"] for row in rows if row["state"] in {"INTEGRATED", "VERIFIED"}}
if {"E1-LH-001", "E1-HH-003"} & covered:
    raise SystemExit("next-wave targets are already covered")

plan = {
    "schema_version": "1.0",
    "product": "eisei1",
    "plan_id": "E1-NEXT-WAVE-001",
    "status": "READY_FOR_AUTHORING",
    "created_at": "2026-09-02",
    "max_parallel_ranges": 2,
    "candidate_count_is_quota": False,
    "selection_basis": [
        "uncovered required knowledge target",
        "exam relevance and hazardous-work applicability",
        "current authoritative source path",
        "materially distinct propositions from canonical and persisted candidates",
    ],
    "ranges": [
        {
            "lane": "law_hazardous",
            "knowledge_target_id": "E1-LH-001",
            "title": "有害業務を伴う衛生管理体制",
            "source_ids": ["E1-LAW-ASR", "E1-LAW-ASEO"],
            "authoring_contract": "Select exact current e-Gov article/paragraph before candidate creation; test a hazardous-work condition that changes the appointment conclusion.",
            "candidate_ceiling": 3,
        },
        {
            "lane": "hygiene_hazardous",
            "knowledge_target_id": "E1-HH-003",
            "title": "有機溶剤の健康影響",
            "source_ids": ["E1-MHLW-OH", "E1-LAW-ORGANIC"],
            "authoring_contract": "Select a current MHLW locator for the health proposition; use the Organic Solvent Ordinance only when the tested conclusion is a legal duty.",
            "candidate_ceiling": 3,
        },
    ],
    "global_collision_scope": [
        "all canonical Eisei1 questions",
        "all persisted candidates in batches 002-009",
        "all candidates in the new wave",
    ],
    "quality_constraints": [
        "exactly five choices",
        "one unambiguous answer",
        "four plausible same-domain distractors",
        "A-E explanation coverage",
        "precise source locator before acceptance",
        "no wording-only or choice-order duplicate",
    ],
    "answer_position_note": "Do not alter the correct proposition for balance; inspect the batch distribution after authoring and reorder choices only when meaning is preserved.",
}
PLAN_PATH.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
state["next_atomic_objective"] = "AUTHOR_EISEI1_NEXT_COVERAGE_WAVE"
state["state_epoch"] = 6
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

