#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tooling" / "question_bank"))
from ai_governance import candidate_fingerprint, promote_ai_governed_candidates
from expansion import validate_expansion_batch

BANK = REPO / "question_banks" / "drone_second_class"
AUTHORING = BANK / "authoring"
BATCH = AUTHORING / "batches" / "batch_019"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "drone_state.json"
ALL = tuple(f"B19-RULE-C{i:03d}" for i in range(1, 16))
AUTHOR_ID = "chatgpt-b19-rules-author-r1"
REVIEWER_ID = "chatgpt-b19-independent-reviewer-r1"
DIRECTOR_ID = "chatgpt-primary-director-b19-r1"

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 138 or state.get("next_atomic_objective") != "MATERIALIZE_B19_ACCEPTANCE_PACKETS_15":
    raise SystemExit(f"unexpected state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}")

policy = json.loads((AUTHORING / "owner_dynamic_release_inclusion_2026-08-26.json").read_text(encoding="utf-8"))
release_policy = policy.get("release_policy", {})
current_facts = policy.get("current_facts", {})
if (
    policy.get("status") != "ACTIVE"
    or release_policy.get("fixed_release_question_count") is not None
    or release_policy.get("release_progression_blocked_by_400_target") is not False
    or "B19" not in release_policy.get("in_flight_batch_rule", "")
    or current_facts.get("b20_before_current_release") != "PROHIBITED"
):
    raise SystemExit("dynamic release policy drift")

with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as handle:
    rows = {row["candidate_id"]: row for row in csv.DictReader(handle)}
if set(rows) != set(ALL):
    raise SystemExit("unexpected B19 candidate set")
if any(rows[c]["state"] != "AI_PRE_ACCEPT" or rows[c]["permanent_question_id"].strip() for c in ALL):
    raise SystemExit("unexpected B19 candidate state")

review = json.loads((BATCH / "independent_review_r1.json").read_text(encoding="utf-8"))
review_by = {decision["candidate_id"]: decision for decision in review["decisions"]}
if review.get("summary") != {"reviewed": 15, "accept": 15, "reject": 0, "rework": 0, "hold": 0}:
    raise SystemExit("B19 review summary drift")
if set(review_by) != set(ALL) or any(review_by[c].get("decision") != "ACCEPT" for c in ALL):
    raise SystemExit("B19 review decision drift")
if (
    review.get("identity_separation") != "PASS"
    or review.get("author_identity_checked") != AUTHOR_ID
    or review.get("reviewer", {}).get("id") != REVIEWER_ID
    or review.get("controlled_variant_gate", {}).get("numeric_quota_used") is not False
):
    raise SystemExit("B19 review identity/governance drift")

director = json.loads((BATCH / "director_adjudication_r1.json").read_text(encoding="utf-8"))
if director.get("summary") != {"accept": 15, "reject": 0, "rework": 0, "hold": 0}:
    raise SystemExit("B19 Director summary drift")
if set(director.get("accepted_candidate_ids", [])) != set(ALL) or director.get("rejected_candidate_ids", []):
    raise SystemExit("B19 Director decision drift")
if (
    director.get("identity_separation_checked") is not True
    or director.get("author_identity") != AUTHOR_ID
    or director.get("reviewer_identity") != REVIEWER_ID
    or director.get("director", {}).get("id") != DIRECTOR_ID
    or len({AUTHOR_ID, REVIEWER_ID, DIRECTOR_ID}) != 3
):
    raise SystemExit("B19 Director identity drift")
director_rationale = " ".join(str(x).strip() for x in director.get("director_findings", []) if str(x).strip())
if not director_rationale:
    raise SystemExit("B19 Director rationale missing")

packets = BATCH / "acceptance_packets"
packets.mkdir(exist_ok=True)
if list(packets.glob("*.json")):
    raise SystemExit("partial B19 acceptance packet state detected")

for candidate_id in ALL:
    candidate = rows[candidate_id]
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
            "source": {key: candidate[key] for key in ("source_id", "source_version", "source_locator")},
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
        "independent_review": {
            "decision": "ACCEPT",
            "rationale": review_by[candidate_id]["rationale"],
        },
        "director_adjudication": {
            "decision": "ACCEPT",
            "rationale": director_rationale,
        },
        "requested_state": "AI_GOVERNED_ACCEPT",
    }
    (packets / f"{candidate_id}.json").write_text(
        json.dumps(packet, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

promote_ai_governed_candidates(BATCH, ALL)
with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as handle:
    after = {row["candidate_id"]: row for row in csv.DictReader(handle)}
if any(after[c]["state"] != "READY_FOR_ID" or after[c]["permanent_question_id"] for c in ALL):
    raise SystemExit("B19 promotion drift")
if {path.stem for path in packets.glob("*.json")} != set(ALL):
    raise SystemExit("B19 packet set drift")

with (AUTHORING / "questions.csv").open(encoding="utf-8", newline="") as handle:
    if sum(1 for _ in csv.DictReader(handle)) != 371:
        raise SystemExit("canonical baseline changed")
if len(json.loads((AUTHORING / "released_questions.json").read_text(encoding="utf-8"))["released_questions"]) != 188:
    raise SystemExit("released baseline changed")
meta = json.loads((AUTHORING / "bank.json").read_text(encoding="utf-8"))
runtime = json.loads((BANK / meta["runtime_output"]).read_text(encoding="utf-8"))
if sum(len(unit.get("cards", [])) for deck in runtime.get("decks", []) for unit in deck.get("units", [])) != 188:
    raise SystemExit("runtime baseline changed")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "origin/main"], text=True).strip()
state["state_epoch"] = 139
state["next_atomic_objective"] = "ALLOCATE_AND_INTEGRATE_B19_ACCEPTED_15"
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

errors = validate_expansion_batch(BATCH)
if errors:
    raise SystemExit("B19 expansion validation failed: " + " | ".join(errors))
