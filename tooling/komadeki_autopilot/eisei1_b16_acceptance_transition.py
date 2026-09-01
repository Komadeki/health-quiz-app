#!/usr/bin/env python3
from __future__ import annotations
import csv,json,subprocess,sys
from pathlib import Path
REPO=Path(__file__).resolve().parents[2]; sys.path.insert(0,str(REPO/"tooling/question_bank"))
from ai_governance import ai_acceptance_errors,candidate_fingerprint,promote_ai_governed_candidates
from expansion import validate_expansion_batch
BATCH=REPO/"question_banks/eisei1/authoring/batches/batch_016"; STATE=REPO/"tooling/komadeki_autopilot/eisei1_state.json"
IDS=("E1-B16-LG-C001",)
st=json.loads(STATE.read_text(encoding="utf-8"))
if st.get("state_epoch")!=32 or st.get("next_atomic_objective")!="ACCEPT_EISEI1_B16_CANDIDATES_1": raise SystemExit("unexpected state")
with (BATCH/"candidates.csv").open(encoding="utf-8",newline="") as h: reader=csv.DictReader(h,restval=""); rows=list(reader)
by={r["candidate_id"]:r for r in rows}; review=json.loads((BATCH/"independent_review_r1.json").read_text(encoding="utf-8")); dec={x["candidate_id"]:x for x in review["decisions"]}
if set(by)!=set(IDS) or any(r["state"]!="AI_PRE_ACCEPT" for r in rows) or set(dec)!=set(IDS) or any(x["decision"]!="ACCEPT" for x in dec.values()): raise SystemExit("B16 preaccept/review drift")
if list((BATCH/"acceptance_packets").glob("*.json")): raise SystemExit("partial packet state")
BATCH.joinpath("acceptance_packets").mkdir(exist_ok=True)
for cid in IDS:
 c=by[cid]; packet={"schema_version":"1.0","candidate_id":cid,"candidate_state":"AI_PRE_ACCEPT","candidate_fingerprint":candidate_fingerprint(c),"actors":{"author":{"id":"eisei1-b16-author-r1","role":"AI_AUTHOR"},"reviewer":{"id":"eisei1-b16-independent-reviewer-r1","role":"AI_REVIEWER"},"director":{"id":"eisei1-b16-director-r1","role":"AI_DIRECTOR"}},"evidence":{"source":{f:c[f] for f in ("source_id","source_version","source_locator")},"answer_defining_proposition":c["answer_defining_proposition"],"tested_misconception":c["tested_misconception"],"reasoning_path":c["reasoning_path"],"collision":{"released_bank_checked":True,"canonical_drafts_checked":True,"batch_checked":True,"note":c["collision_note"]}},"independent_review":{"decision":"ACCEPT","rationale":dec[cid]["rationale"]},"director_adjudication":{"decision":"ACCEPT","rationale":"Current e-Gov locator and global collision evidence rechecked; distinct proposition and explained options."},"requested_state":"AI_GOVERNED_ACCEPT"}
 (BATCH/"acceptance_packets"/f"{cid}.json").write_text(json.dumps(packet,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
 if errors:=ai_acceptance_errors(BATCH,c): raise SystemExit("invalid packet: "+" | ".join(errors))
promote_ai_governed_candidates(BATCH,list(IDS))
with (BATCH/"candidates.csv").open(encoding="utf-8",newline="") as h: promoted={r["candidate_id"]:r for r in csv.DictReader(h,restval="")}
if any(promoted[c]["state"]!="READY_FOR_ID" or promoted[c].get("permanent_question_id") for c in IDS): raise SystemExit("promotion failed")
if errors:=validate_expansion_batch(BATCH): raise SystemExit("validation failed: "+" | ".join(errors))
st.update(observed_main=subprocess.check_output(["git","rev-parse","HEAD"],text=True).strip(),next_atomic_objective="ALLOCATE_AND_INTEGRATE_EISEI1_B16_ACCEPTED_1",state_epoch=33); STATE.write_text(json.dumps(st,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
