#!/usr/bin/env python3
from __future__ import annotations
import csv,json,subprocess,sys
from pathlib import Path
R=Path(__file__).resolve().parents[2]; sys.path.insert(0,str(R/"tooling/question_bank"))
from expansion import validate_expansion_batch
from transaction import QuestionExpansionTransaction
from eisei1_ready_for_id_integration_transition import canonical_row
B=R/"question_banks/eisei1"; A=B/"authoring"; X=A/"batches/batch_012"; S=R/"tooling/komadeki_autopilot/eisei1_state.json"
IDS=("E1-B12-LH-C001","E1-B12-LH-C002","E1-B12-LH-C003","E1-B12-LH-C004"); EXPECTED={c:f"EISEI1-Q-{n:06d}" for c,n in zip(IDS,range(24,28))}
def read(p,k):
 with p.open(encoding="utf-8",newline="") as h:return {r[k]:r for r in csv.DictReader(h,restval="")}
st=json.loads(S.read_text(encoding="utf-8")); before=read(A/"questions.csv","question_id"); candidates=read(X/"candidates.csv","candidate_id")
if st.get("state_epoch")!=18 or st.get("next_atomic_objective")!="ALLOCATE_AND_INTEGRATE_EISEI1_B12_ACCEPTED_4":raise SystemExit("unexpected state")
if set(before)!={f"EISEI1-Q-{n:06d}" for n in range(1,24)} or any(candidates[c]["state"]!="READY_FOR_ID" or candidates[c].get("permanent_question_id") for c in IDS):raise SystemExit("precondition drift")
untouched={p:p.read_bytes() for p in (A/"source_verifications.json",A/"released_questions.json",B/"generated/eisei1_bank.json")}
t=QuestionExpansionTransaction(B,X,IDS,question_factory=canonical_row)
if t.plan().mapping!=EXPECTED or t.apply()!=EXPECTED:raise SystemExit("allocation failed")
if set(read(A/"questions.csv","question_id"))!={f"EISEI1-Q-{n:06d}" for n in range(1,28)}:raise SystemExit("inventory mismatch")
if any(p.read_bytes()!=v for p,v in untouched.items()):raise SystemExit("out-of-scope mutation")
if errors:=validate_expansion_batch(X):raise SystemExit("validation failed: "+" | ".join(errors))
st.update(observed_main=subprocess.check_output(["git","rev-parse","HEAD"],text=True).strip(),next_atomic_objective="VERIFY_EISEI1_B12_CANONICAL_SOURCES_4",state_epoch=19);S.write_text(json.dumps(st,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
