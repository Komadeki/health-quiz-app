#!/usr/bin/env python3
"""Verify the three integrated Eisei1 B10 canonical source bindings."""

from __future__ import annotations

import csv
import json
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BANK = REPO / "question_banks/eisei1"
AUTHORING = BANK / "authoring"
BATCH = AUTHORING / "batches/batch_010"
STATE_PATH = REPO / "tooling/komadeki_autopilot/eisei1_state.json"
VERIFICATIONS = {
    "EISEI1-Q-000017": ("E1-LAW-ASR", "current-as-of-2026-08-26"),
    "EISEI1-Q-000018": ("E1-LAW-ASR", "current-as-of-2026-08-26"),
    "EISEI1-Q-000019": ("E1-LAW-ASR", "current-as-of-2026-08-26"),
}


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle, restval=""))


state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 9 or state.get("next_atomic_objective") != "VERIFY_EISEI1_B10_CANONICAL_SOURCES_3":
    raise SystemExit("unexpected Eisei1 state")

candidate_rows = {row["permanent_question_id"]: row for row in read_rows(BATCH / "candidates.csv")}
if set(candidate_rows) != set(VERIFICATIONS):
    raise SystemExit("unexpected B10 canonical binding set")
for question_id, (source_id, source_version) in VERIFICATIONS.items():
    row = candidate_rows[question_id]
    if row["state"] != "INTEGRATED" or row["source_id"] != source_id or row["source_version"] != source_version:
        raise SystemExit(f"B10 source contract mismatch: {question_id}")

source_path = AUTHORING / "source_verifications.json"
source_doc = json.loads(source_path.read_text(encoding="utf-8"))
existing = {row["question_id"] for row in source_doc["verifications"]}
if existing & set(VERIFICATIONS):
    raise SystemExit("partial or duplicate B10 source verification detected")
source_doc["verifications"].extend(
    {
        "question_id": question_id,
        "source_id": source_id,
        "source_version": source_version,
        "verification_state": "author_source_verified",
        "verified_at": "2026-09-02",
    }
    for question_id, (source_id, source_version) in VERIFICATIONS.items()
)
source_doc["verifications"].sort(key=lambda row: row["question_id"])
source_path.write_text(json.dumps(source_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as handle:
    fields = list(csv.DictReader(handle).fieldnames or [])
rows = read_rows(BATCH / "candidates.csv")
for row in rows:
    if row["permanent_question_id"] in VERIFICATIONS:
        row["state"] = "VERIFIED"
with (BATCH / "candidates.csv").open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)

if json.loads((AUTHORING / "released_questions.json").read_text(encoding="utf-8"))["released_questions"] != []:
    raise SystemExit("release snapshot changed")
if json.loads((BANK / "generated/eisei1_bank.json").read_text(encoding="utf-8"))["decks"] != []:
    raise SystemExit("runtime artifact changed")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
state["next_atomic_objective"] = "PLAN_EISEI1_NEXT_COVERAGE_WAVE_002"
state["state_epoch"] = 10
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

