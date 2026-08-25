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
BATCH = AUTHORING / "batches" / "batch_014"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "drone_state.json"
ALL = tuple(f"B14-RULE-C{i:03d}" for i in range(1, 10))
ACCEPTED = ALL
REJECTED = ()
AUTHOR_ID = "chatgpt-b14-rules-author-r1"
REVIEWER_ID = "autopilot-b14-rules-reviewer-r1"
DIRECTOR_ID = "chatgpt-primary-director-b14-r1"

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 98 or state.get("next_atomic_objective") != "MATERIALIZE_B14_ACCEPTANCE_PACKETS_9":
    raise SystemExit(f"unexpected state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}")

with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as h:
    rows = {r["candidate_id"]: r for r in csv.DictReader(h)}
if set(rows) != set(ALL):
    raise SystemExit("unexpected B14 candidate set")
if any(rows[c]["state"] != "AI_PRE_ACCEPT" or rows[c]["permanent_question_id"].strip() for c in ALL):
    raise SystemExit("unexpected B14 pre-acceptance state")

review = json.loads((BATCH / "independent_review_r1.json").read_text(encoding="utf-8"))
review_by = {d["candidate_id"]: d for d in review["decisions"]}
if review.get("summary") != {"reviewed":9,"accept":9,"reject":0,"rework":0,"hold":0}:
    raise SystemExit("unexpected B14 review summary")
if set(review_by) != set(ALL) or any(review_by[c].get("decision") != "ACCEPT" for c in ACCEPTED):
    raise SystemExit("B14 review decision set drift")
if review.get("identity_separation") != "PASS" or review.get("author_identity_checked") != AUTHOR_ID or review.get("reviewer", {}).get("id") != REVIEWER_ID:
    raise SystemExit("B14 review identity drift")

director = json.loads((BATCH / "director_adjudication_r1.json").read_text(encoding="utf-8"))
if director.get("summary") != {"accept":9,"reject":0,"rework":0,"hold":0}:
    raise SystemExit("unexpected B14 Director summary")
if set(director.get("accepted_candidate_ids", [])) != set(ACCEPTED) or director.get("rejected_candidate_ids", []) != []:
    raise SystemExit("B14 Director decision set drift")
if director.get("identity_separation_checked") is not True or director.get("author_identity") != AUTHOR_ID or director.get("reviewer_identity") != REVIEWER_ID or director.get("director", {}).get("id") != DIRECTOR_ID:
    raise SystemExit("B14 Director actor identity drift")
if len({AUTHOR_ID, REVIEWER_ID, DIRECTOR_ID}) != 3:
    raise SystemExit("B14 actor identity collision")
director_rationale = " ".join(str(x).strip() for x in director.get("director_findings", []) if str(x).strip())
if not director_rationale:
    raise SystemExit("B14 Director rationale missing")

packets = BATCH / "acceptance_packets"
packets.mkdir(exist_ok=True)
if list(packets.glob("*.json")):
    raise SystemExit("partial B14 acceptance packet state detected")

for cid in ACCEPTED:
    candidate = rows[cid]
    packet = {
        "schema_version":"1.0",
        "candidate_id":cid,
        "candidate_state":"AI_PRE_ACCEPT",
        "candidate_fingerprint":candidate_fingerprint(candidate),
        "actors":{"author":{"id":AUTHOR_ID,"role":"AI_AUTHOR"},"reviewer":{"id":REVIEWER_ID,"role":"AI_REVIEWER"},"director":{"id":DIRECTOR_ID,"role":"AI_DIRECTOR"}},
        "evidence":{"source":{k:candidate[k] for k in ("source_id","source_version","source_locator")},"answer_defining_proposition":candidate["answer_defining_proposition"],"tested_misconception":candidate["tested_misconception"],"reasoning_path":candidate["reasoning_path"],"collision":{"released_bank_checked":True,"canonical_drafts_checked":True,"batch_checked":True,"note":candidate["collision_note"]}},
        "independent_review":{"decision":"ACCEPT","rationale":review_by[cid]["rationale"]},
        "director_adjudication":{"decision":"ACCEPT","rationale":director_rationale},
        "requested_state":"AI_GOVERNED_ACCEPT"
    }
    (packets / f"{cid}.json").write_text(json.dumps(packet, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

promote_ai_governed_candidates(BATCH, ACCEPTED)
with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as h:
    after = {r["candidate_id"]: r for r in csv.DictReader(h)}
if any(after[c]["state"] != "READY_FOR_ID" or after[c]["permanent_question_id"] for c in ACCEPTED):
    raise SystemExit("B14 accepted promotion failed")
if {p.stem for p in packets.glob("*.json")} != set(ACCEPTED):
    raise SystemExit("B14 packet set drift")

with (AUTHORING / "questions.csv").open(encoding="utf-8", newline="") as h:
    canonical_count = sum(1 for _ in csv.DictReader(h))
if canonical_count != 336:
    raise SystemExit(f"canonical baseline changed: {canonical_count}")
released = json.loads((AUTHORING / "released_questions.json").read_text(encoding="utf-8"))["released_questions"]
if len(released) != 188:
    raise SystemExit("released baseline changed")
meta = json.loads((AUTHORING / "bank.json").read_text(encoding="utf-8"))
runtime = json.loads((BANK / meta["runtime_output"]).read_text(encoding="utf-8"))
if sum(len(u.get("cards", [])) for d in runtime.get("decks", []) for u in d.get("units", [])) != 188:
    raise SystemExit("runtime baseline changed")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "origin/main"], text=True).strip()
state["state_epoch"] = 99
state["next_atomic_objective"] = "ALLOCATE_AND_INTEGRATE_B14_ACCEPTED_9"
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
errors = validate_expansion_batch(BATCH)
if errors:
    raise SystemExit("B14 expansion validation failed: " + " | ".join(errors))
