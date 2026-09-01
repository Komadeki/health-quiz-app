#!/usr/bin/env python3
"""Integrate accepted B11 candidates into the canonical Eisei1 draft bank."""

from __future__ import annotations

import csv
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tooling/question_bank"))
from expansion import validate_expansion_batch  # noqa: E402
from transaction import QuestionExpansionTransaction  # noqa: E402
from eisei1_ready_for_id_integration_transition import canonical_row  # noqa: E402

BANK = REPO / "question_banks/eisei1"
AUTHORING = BANK / "authoring"
BATCH = AUTHORING / "batches/batch_011"
STATE_PATH = REPO / "tooling/komadeki_autopilot/eisei1_state.json"
SELECTED = ("E1-B11-LH-C001", "E1-B11-LH-C002", "E1-B11-LH-C003", "E1-B11-LH-C004")
EXPECTED = {candidate: f"EISEI1-Q-{number:06d}" for candidate, number in zip(SELECTED, range(20, 24))}


def read_rows(path: Path, key: str) -> dict[str, dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return {row[key]: row for row in csv.DictReader(handle, restval="")}


state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 13 or state.get("next_atomic_objective") != "ALLOCATE_AND_INTEGRATE_EISEI1_B11_ACCEPTED_4":
    raise SystemExit("unexpected Eisei1 state")
questions_before = read_rows(AUTHORING / "questions.csv", "question_id")
registry_before = read_rows(AUTHORING / "question_id_registry.csv", "question_id")
candidates = read_rows(BATCH / "candidates.csv", "candidate_id")
if set(questions_before) != {f"EISEI1-Q-{number:06d}" for number in range(1, 20)}:
    raise SystemExit("canonical inventory drift before B11 integration")
if set(registry_before) != set(questions_before):
    raise SystemExit("registry drift before B11 integration")
if any(candidates[candidate]["state"] != "READY_FOR_ID" or candidates[candidate].get("permanent_question_id") for candidate in SELECTED):
    raise SystemExit("B11 candidates must be READY_FOR_ID with no permanent ID")
if {path.stem for path in (BATCH / "acceptance_packets").glob("*.json")} != set(SELECTED):
    raise SystemExit("B11 packet set drift")
untouched = {path: path.read_bytes() for path in (AUTHORING / "source_verifications.json", AUTHORING / "released_questions.json", BANK / "generated/eisei1_bank.json")}
transaction = QuestionExpansionTransaction(BANK, BATCH, SELECTED, question_factory=canonical_row)
if transaction.plan().mapping != EXPECTED or transaction.apply() != EXPECTED:
    raise SystemExit("unexpected B11 permanent-ID allocation")
questions_after = read_rows(AUTHORING / "questions.csv", "question_id")
registry_after = read_rows(AUTHORING / "question_id_registry.csv", "question_id")
if set(questions_after) != set(questions_before) | set(EXPECTED.values()) or set(registry_after) != set(questions_after):
    raise SystemExit("B11 canonical inventory mismatch")
for candidate_id, question_id in EXPECTED.items():
    if registry_after[question_id]["notes"] != f"Expansion pre-release allocation: {candidate_id}":
        raise SystemExit("B11 registry provenance mismatch")
    if questions_after[question_id]["status"] != "draft":
        raise SystemExit("B11 canonical row status mismatch")
if any(path.read_bytes() != before for path, before in untouched.items()):
    raise SystemExit("B11 integration mutated out-of-scope artifact")
if errors := validate_expansion_batch(BATCH):
    raise SystemExit("B11 expansion validation failed: " + " | ".join(errors))
state["observed_main"] = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
state["next_atomic_objective"] = "VERIFY_EISEI1_B11_CANONICAL_SOURCES_4"
state["state_epoch"] = 14
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
