#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tooling" / "question_bank"))
from expansion import validate_expansion_batch

BANK = REPO / "question_banks" / "otsu4"
AUTHORING = BANK / "authoring"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "otsu4_state.json"
WAVE_PATH = AUTHORING / "waves" / "wave_001.json"
REVIEWER_ID = "otsu4-wave1-independent-reviewer-r1"
BATCHES = {
    "B4": {
        "dir": AUTHORING / "batches" / "batch_004",
        "prefix": "O4-B4-FIR-C",
        "count": 24,
        "author": "otsu4-b4-author-r1",
        "summary": {"reviewed": 24, "accept": 22, "reject": 0, "rework": 2, "hold": 0},
    },
    "B5": {
        "dir": AUTHORING / "batches" / "batch_005",
        "prefix": "O4-B5-PHY-C",
        "count": 20,
        "author": "otsu4-b5-author-r1",
        "summary": {"reviewed": 20, "accept": 20, "reject": 0, "rework": 0, "hold": 0},
    },
    "B6": {
        "dir": AUTHORING / "batches" / "batch_006",
        "prefix": "O4-B6-LAW-C",
        "count": 20,
        "author": "otsu4-b6-author-r1",
        "summary": {"reviewed": 20, "accept": 20, "reject": 0, "rework": 0, "hold": 0},
    },
}
EXPECTED_REWORK = {"O4-B4-FIR-C019", "O4-B4-FIR-C020"}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 45 or state.get("next_atomic_objective") != "INDEPENDENT_AI_REVIEW_OTSU4_WAVE_1_B4_B5_B6_64":
    raise SystemExit(
        f"unexpected Otsu4 state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}"
    )
if state.get("human_blocker") is not None:
    raise SystemExit("Otsu4 human blocker must remain null")

all_candidate_ids: set[str] = set()
accepted_ids: set[str] = set()
rework_ids: set[str] = set()
for batch_id, contract in BATCHES.items():
    batch_dir: Path = contract["dir"]
    rows = read_csv(batch_dir / "candidates.csv")
    expected_ids = {
        f"{contract['prefix']}{index:03d}" for index in range(1, int(contract["count"]) + 1)
    }
    actual_ids = {row["candidate_id"] for row in rows}
    if actual_ids != expected_ids:
        raise SystemExit(f"{batch_id} candidate set drift")
    if any(row["state"] != "AI_PRE_ACCEPT" for row in rows):
        raise SystemExit(f"{batch_id} candidate state drift")
    if any(row.get("permanent_question_id", "").strip() for row in rows):
        raise SystemExit(f"{batch_id} received Permanent IDs before review")
    all_candidate_ids |= actual_ids

    review_path = batch_dir / "independent_review_r1.json"
    review = json.loads(review_path.read_text(encoding="utf-8"))
    if review.get("summary") != contract["summary"]:
        raise SystemExit(f"{batch_id} review summary drift")
    if review.get("identity_separation") != "PASS":
        raise SystemExit(f"{batch_id} review identity separation failed")
    if review.get("author_identity_checked") != contract["author"]:
        raise SystemExit(f"{batch_id} author identity drift")
    if review.get("reviewer", {}).get("id") != REVIEWER_ID:
        raise SystemExit(f"{batch_id} reviewer identity drift")
    decisions = review.get("decisions", [])
    if len(decisions) != int(contract["count"]):
        raise SystemExit(f"{batch_id} review decision count drift")
    decision_by = {item.get("candidate_id"): item for item in decisions if isinstance(item, dict)}
    if set(decision_by) != expected_ids:
        raise SystemExit(f"{batch_id} review candidate set drift")
    for candidate_id, decision in decision_by.items():
        value = decision.get("decision")
        if value == "ACCEPT":
            accepted_ids.add(candidate_id)
        elif value == "REWORK":
            if not str(decision.get("rationale", "")).strip() or not str(decision.get("resume_condition", "")).strip():
                raise SystemExit(f"{candidate_id} REWORK evidence incomplete")
            rework_ids.add(candidate_id)
        else:
            raise SystemExit(f"unexpected Wave 1 review decision for {candidate_id}: {value}")

    errors = validate_expansion_batch(batch_dir)
    if errors:
        raise SystemExit(f"{batch_id} expansion validation failed: " + " | ".join(errors))

if len(all_candidate_ids) != 64 or len(accepted_ids) != 62 or rework_ids != EXPECTED_REWORK:
    raise SystemExit(
        f"Wave 1 aggregate drift: candidates={len(all_candidate_ids)} accept={len(accepted_ids)} rework={sorted(rework_ids)}"
    )

wave_review_path = AUTHORING / "waves" / "wave_001_independent_review_r1.json"
wave_review = json.loads(wave_review_path.read_text(encoding="utf-8"))
if wave_review.get("summary") != {"reviewed": 64, "accept": 62, "reject": 0, "rework": 2, "hold": 0}:
    raise SystemExit("Wave 1 aggregate review summary drift")
if wave_review.get("identity_separation") != "PASS" or wave_review.get("reviewer", {}).get("id") != REVIEWER_ID:
    raise SystemExit("Wave 1 aggregate review identity drift")
wave_accepted = {
    candidate_id
    for values in wave_review.get("accepted_candidate_sets", {}).values()
    for candidate_id in values
}
wave_rework = {item.get("candidate_id") for item in wave_review.get("rework", []) if isinstance(item, dict)}
if wave_accepted != accepted_ids or wave_rework != rework_ids:
    raise SystemExit("Wave 1 aggregate accepted/rework set drift")

canonical = read_csv(AUTHORING / "questions.csv")
registry = read_csv(AUTHORING / "question_id_registry.csv")
verifications = json.loads((AUTHORING / "source_verifications.json").read_text(encoding="utf-8"))["verifications"]
released = json.loads((AUTHORING / "released_questions.json").read_text(encoding="utf-8"))["released_questions"]
if len(canonical) != 51 or len(registry) != 51 or len(verifications) != 51 or released:
    raise SystemExit("Otsu4 canonical/source-verification/release baseline drift during Wave review")
meta = json.loads((AUTHORING / "bank.json").read_text(encoding="utf-8"))
runtime = json.loads((BANK / meta["runtime_output"]).read_text(encoding="utf-8"))
runtime_count = sum(
    len(unit.get("cards", []))
    for deck in runtime.get("decks", [])
    for unit in deck.get("units", [])
)
if runtime_count != 0:
    raise SystemExit("Otsu4 runtime changed during Wave review")

wave = json.loads(WAVE_PATH.read_text(encoding="utf-8"))
if wave.get("wave_id") != "W1" or wave.get("actual_candidate_counts") != {"B4": 24, "B5": 20, "B6": 20, "total": 64}:
    raise SystemExit("Wave 1 count metadata drift")
wave["status"] = "INDEPENDENT_AI_REVIEWED"
wave["reviewed_at"] = "2026-08-25"
wave["review_summary"] = {"reviewed": 64, "accept": 62, "reject": 0, "rework": 2, "hold": 0}
wave["reviewer"] = {"id": REVIEWER_ID, "role": "AI_REVIEWER"}
wave["identity_separation"] = "PASS"
wave["reviewed_state_epoch"] = 46
wave["next_gate"] = "DIRECTOR_ACCEPT_AND_PROMOTE_W1_REVIEW_ACCEPTED_62"
WAVE_PATH.write_text(json.dumps(wave, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "origin/main"], text=True).strip()
state["state_epoch"] = 46
state["next_atomic_objective"] = "DIRECTOR_ACCEPT_AND_PROMOTE_OTSU4_WAVE_1_REVIEW_ACCEPTED_62"
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
