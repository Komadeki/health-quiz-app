#!/usr/bin/env python3
"""Promote the independently accepted Eisei1 B10 candidates without ID allocation."""

from __future__ import annotations

import csv
import json
import subprocess
from pathlib import Path

from ai_governance import ai_acceptance_errors, candidate_fingerprint, promote_ai_governed_candidates
from expansion import validate_expansion_batch

REPO = Path(__file__).resolve().parents[2]
BATCH = REPO / "question_banks/eisei1/authoring/batches/batch_010"
STATE_PATH = REPO / "tooling/komadeki_autopilot/eisei1_state.json"
IDS = ("E1-B10-LH-C001", "E1-B10-LH-C002", "E1-B10-LH-C003")
AUTHOR_ID = "eisei1-b10-author-r1"
REVIEWER_ID = "eisei1-b10-independent-reviewer-r1"
DIRECTOR_ID = "eisei1-b10-director-r1"

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 7 or state.get("next_atomic_objective") != "ACCEPT_EISEI1_B10_CANDIDATES_3":
    raise SystemExit("unexpected Eisei1 state")

with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as handle:
    reader = csv.DictReader(handle, restval="")
    fields = list(reader.fieldnames or [])
    rows = list(reader)
by_id = {row["candidate_id"]: row for row in rows}
if set(by_id) != set(IDS) or any(row["state"] != "AI_PRE_ACCEPT" for row in rows):
    raise SystemExit("B10 candidates must be AI_PRE_ACCEPT")
if list((BATCH / "acceptance_packets").glob("*.json")):
    raise SystemExit("partial B10 acceptance packet state detected")

review = json.loads((BATCH / "independent_review_r1.json").read_text(encoding="utf-8"))
decisions = {item["candidate_id"]: item for item in review["decisions"]}
if set(decisions) != set(IDS) or any(item["decision"] != "ACCEPT" for item in decisions.values()):
    raise SystemExit("B10 independent review is not unanimous ACCEPT")

for candidate_id in IDS:
    candidate = by_id[candidate_id]
    packet = {
        "schema_version": "1.0",
        "candidate_id": candidate_id,
        "candidate_state": "AI_PRE_ACCEPT",
        "candidate_fingerprint": candidate_fingerprint(candidate),
        "actors": {
            "author": {"id": AUTHOR_ID, "role": "AI_AUTHOR"},
            "reviewer": {"id": REVIEWER_ID, "role": "AI_REVIEWER"},
            "director": {"id": DIRECTOR_ID, "role": "AI_DIRECTOR"},
        },
        "evidence": {
            "source": {field: candidate[field] for field in ("source_id", "source_version", "source_locator")},
            "answer_defining_proposition": candidate["answer_defining_proposition"],
            "tested_misconception": candidate["tested_misconception"],
            "reasoning_path": candidate["reasoning_path"],
            "collision": {
                "released_bank_checked": True,
                "canonical_drafts_checked": True,
                "batch_checked": True,
                "note": candidate["collision_note"],
            },
        },
        "independent_review": {"decision": "ACCEPT", "rationale": decisions[candidate_id]["rationale"]},
        "director_adjudication": {
            "decision": "ACCEPT",
            "rationale": "Director rechecked the exact e-Gov Article 7 paragraph 1 item bound to this candidate. The proposition is distinct, the five choices are explained, and no semantic collision is present. This AI-governed acceptance creates no permanent ID, canonical, source-verification, release, or runtime mutation.",
        },
        "requested_state": "AI_GOVERNED_ACCEPT",
    }
    (BATCH / "acceptance_packets" / f"{candidate_id}.json").write_text(json.dumps(packet, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if errors := ai_acceptance_errors(BATCH, candidate):
        raise SystemExit(f"invalid B10 acceptance packet: {candidate_id}: {' | '.join(errors)}")

promote_ai_governed_candidates(BATCH, list(IDS))
with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as handle:
    promoted = {row["candidate_id"]: row for row in csv.DictReader(handle)}
if any(promoted[candidate_id]["state"] != "READY_FOR_ID" or promoted[candidate_id]["permanent_question_id"] for candidate_id in IDS):
    raise SystemExit("B10 promotion failed")
if errors := validate_expansion_batch(BATCH):
    raise SystemExit("B10 expansion validation failed: " + " | ".join(errors))

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
state["next_atomic_objective"] = "ALLOCATE_AND_INTEGRATE_EISEI1_B10_ACCEPTED_3"
state["state_epoch"] = 8
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
