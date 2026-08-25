#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tooling" / "question_bank"))
from ai_governance import ai_acceptance_errors, candidate_fingerprint
from expansion import validate_expansion_batch

BANK = REPO / "question_banks" / "otsu4"
AUTHORING = BANK / "authoring"
BATCH = AUTHORING / "batches" / "batch_002"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "otsu4_state.json"
ALL = tuple(f"O4-B2-LAW-C{i:03d}" for i in range(1, 25))
REJECTED = ("O4-B2-LAW-C016",)
ACCEPTED = tuple(cid for cid in ALL if cid not in REJECTED)
AUTHOR_ID = "otsu4-b2-author-r1"
REVIEWER_ID = "otsu4-b2-independent-reviewer-r1"
DIRECTOR_ID = "otsu4-b2-director-adjudicator-r1"

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 29 or state.get("next_atomic_objective") != "MATERIALIZE_OTSU4_BATCH_2_ACCEPTANCE_PACKETS_23":
    raise SystemExit(f"unexpected state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}")

with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as h:
    rows = {r["candidate_id"]: r for r in csv.DictReader(h)}
if set(rows) != set(ALL):
    raise SystemExit("unexpected Otsu4 Batch 2 candidate set")
if any(rows[c]["state"] != "AI_PRE_ACCEPT" or rows[c]["permanent_question_id"].strip() for c in ALL):
    raise SystemExit("unexpected Otsu4 Batch 2 pre-acceptance state")

review = json.loads((BATCH / "independent_review_r1.json").read_text(encoding="utf-8"))
review_by = {d["candidate_id"]: d for d in review["decisions"]}
if review.get("summary") != {"reviewed": 24, "accept": 23, "reject": 1, "rework": 0, "hold": 0}:
    raise SystemExit("unexpected Otsu4 Batch 2 review summary")
if set(review_by) != set(ALL):
    raise SystemExit("Otsu4 Batch 2 review candidate set drift")
if any(review_by[c].get("decision") != "ACCEPT" for c in ACCEPTED):
    raise SystemExit("Otsu4 Batch 2 accepted review decision drift")
if any(review_by[c].get("decision") != "REJECT" for c in REJECTED):
    raise SystemExit("Otsu4 Batch 2 rejected review decision drift")
if review.get("identity_separation") != "PASS" or review.get("author_identity_checked") != AUTHOR_ID or review.get("reviewer", {}).get("id") != REVIEWER_ID:
    raise SystemExit("Otsu4 Batch 2 review identity drift")

director = json.loads((BATCH / "director_adjudication_r1.json").read_text(encoding="utf-8"))
if director.get("summary") != {"accept": 23, "reject": 1, "rework": 0, "hold": 0}:
    raise SystemExit("unexpected Otsu4 Batch 2 Director summary")
if set(director.get("accepted_candidate_ids", [])) != set(ACCEPTED):
    raise SystemExit("Otsu4 Batch 2 Director accepted set drift")
rejected_by = {item.get("candidate_id"): item for item in director.get("rejected", []) if isinstance(item, dict)}
if set(rejected_by) != set(REJECTED):
    raise SystemExit("Otsu4 Batch 2 Director rejected set drift")
if director.get("identity_separation") != "PASS" or director.get("author", {}).get("id") != AUTHOR_ID or director.get("reviewer", {}).get("id") != REVIEWER_ID or director.get("director", {}).get("id") != DIRECTOR_ID:
    raise SystemExit("Otsu4 Batch 2 Director actor identity drift")
if len({AUTHOR_ID, REVIEWER_ID, DIRECTOR_ID}) != 3:
    raise SystemExit("Otsu4 Batch 2 actor identity collision")
director_rationale = str(director.get("director_rationale", "")).strip()
if not director_rationale:
    raise SystemExit("Otsu4 Batch 2 Director rationale missing")

packets = BATCH / "acceptance_packets"
packets.mkdir(exist_ok=True)
if list(packets.glob("*.json")):
    raise SystemExit("partial Otsu4 Batch 2 acceptance packet state detected")

for cid in ACCEPTED:
    candidate = rows[cid]
    packet = {
        "schema_version": "1.0",
        "candidate_id": cid,
        "candidate_state": "AI_PRE_ACCEPT",
        "candidate_fingerprint": candidate_fingerprint(candidate),
        "actors": {
            "author": {"id": AUTHOR_ID, "role": "AI_AUTHOR"},
            "reviewer": {"id": REVIEWER_ID, "role": "AI_REVIEWER"},
            "director": {"id": DIRECTOR_ID, "role": "AI_DIRECTOR"},
        },
        "evidence": {
            "source": {k: candidate[k] for k in ("source_id", "source_version", "source_locator")},
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
            "rationale": review_by[cid]["rationale"],
        },
        "director_adjudication": {
            "decision": "ACCEPT",
            "rationale": director_rationale,
        },
        "requested_state": "AI_GOVERNED_ACCEPT",
    }
    (packets / f"{cid}.json").write_text(
        json.dumps(packet, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

if {p.stem for p in packets.glob("*.json")} != set(ACCEPTED):
    raise SystemExit("Otsu4 Batch 2 packet set drift")
for cid in ACCEPTED:
    errors = ai_acceptance_errors(BATCH, rows[cid])
    if errors:
        raise SystemExit(f"invalid acceptance packet {cid}: " + " | ".join(errors))
if any((packets / f"{cid}.json").exists() for cid in REJECTED):
    raise SystemExit("rejected Otsu4 Batch 2 candidate received acceptance packet")

with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as h:
    after = {r["candidate_id"]: r for r in csv.DictReader(h)}
if any(after[c]["state"] != "AI_PRE_ACCEPT" or after[c]["permanent_question_id"] for c in ALL):
    raise SystemExit("candidate state changed during acceptance packet materialization")

with (AUTHORING / "questions.csv").open(encoding="utf-8", newline="") as h:
    canonical_questions = list(csv.DictReader(h))
with (AUTHORING / "question_id_registry.csv").open(encoding="utf-8", newline="") as h:
    registry = list(csv.DictReader(h))
verifications = json.loads((AUTHORING / "source_verifications.json").read_text(encoding="utf-8"))["verifications"]
released = json.loads((AUTHORING / "released_questions.json").read_text(encoding="utf-8"))["released_questions"]
if len(canonical_questions) != 6 or len(registry) != 6 or len(verifications) != 6 or released:
    raise SystemExit("Otsu4 canonical/release baseline changed before acceptance")
meta = json.loads((AUTHORING / "bank.json").read_text(encoding="utf-8"))
runtime = json.loads((BANK / meta["runtime_output"]).read_text(encoding="utf-8"))
runtime_count = sum(len(u.get("cards", [])) for d in runtime.get("decks", []) for u in d.get("units", []))
if runtime_count != 0:
    raise SystemExit("Otsu4 runtime baseline changed")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "origin/main"], text=True).strip()
state["state_epoch"] = 30
state["next_atomic_objective"] = "PROMOTE_OTSU4_BATCH_2_ACCEPTED_23_TO_READY_FOR_ID"
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

errors = validate_expansion_batch(BATCH)
if errors:
    raise SystemExit("Otsu4 Batch 2 expansion validation failed: " + " | ".join(errors))
