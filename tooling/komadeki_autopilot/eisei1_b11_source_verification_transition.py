#!/usr/bin/env python3
"""Verify B11's four integrated canonical source bindings."""

from __future__ import annotations

import csv
import json
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BANK = REPO / "question_banks/eisei1"
AUTHORING = BANK / "authoring"
BATCH = AUTHORING / "batches/batch_011"
STATE_PATH = REPO / "tooling/komadeki_autopilot/eisei1_state.json"
VERIFICATIONS = {f"EISEI1-Q-{number:06d}": ("E1-LAW-ASL" if number in {20, 21} else "E1-LAW-ASR", "current-as-of-2026-08-26") for number in range(20, 24)}

def rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle, restval=""))

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 14 or state.get("next_atomic_objective") != "VERIFY_EISEI1_B11_CANONICAL_SOURCES_4":
    raise SystemExit("unexpected Eisei1 state")
candidate_rows = {row["permanent_question_id"]: row for row in rows(BATCH / "candidates.csv")}
if set(candidate_rows) != set(VERIFICATIONS) or any(candidate_rows[qid]["state"] != "INTEGRATED" for qid in VERIFICATIONS):
    raise SystemExit("B11 canonical binding state drift")
source_path = AUTHORING / "source_verifications.json"
source_doc = json.loads(source_path.read_text(encoding="utf-8"))
existing = {item["question_id"] for item in source_doc["verifications"]}
if existing & set(VERIFICATIONS):
    raise SystemExit("duplicate B11 source verification")
source_doc["verifications"].extend({"question_id": qid, "source_id": source_id, "source_version": version, "verification_state": "author_source_verified", "verified_at": "2026-09-02"} for qid, (source_id, version) in VERIFICATIONS.items())
source_doc["verifications"].sort(key=lambda item: item["question_id"])
source_path.write_text(json.dumps(source_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as handle:
    fieldnames = list(csv.DictReader(handle).fieldnames or [])
candidate_rows_list = rows(BATCH / "candidates.csv")
for item in candidate_rows_list:
    if item["permanent_question_id"] in VERIFICATIONS:
        item["state"] = "VERIFIED"
with (BATCH / "candidates.csv").open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader()
    writer.writerows(candidate_rows_list)
if json.loads((AUTHORING / "released_questions.json").read_text(encoding="utf-8"))["released_questions"] != []:
    raise SystemExit("release snapshot changed")
if json.loads((BANK / "generated/eisei1_bank.json").read_text(encoding="utf-8"))["decks"] != []:
    raise SystemExit("runtime artifact changed")
state["observed_main"] = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
state["next_atomic_objective"] = "PLAN_EISEI1_NEXT_COVERAGE_WAVE_003"
state["state_epoch"] = 15
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
