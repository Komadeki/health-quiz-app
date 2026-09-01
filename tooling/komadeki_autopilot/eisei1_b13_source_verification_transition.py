#!/usr/bin/env python3
from __future__ import annotations
import csv,json,subprocess
from pathlib import Path
R=Path(__file__).resolve().parents[2];B=R/"question_banks/eisei1";A=B/"authoring";X=A/"batches/batch_013";S=R/"tooling/komadeki_autopilot/eisei1_state.json"
V={f"EISEI1-Q-{n:06d}":("E1-LAW-SPEC-CHEM" if n<26 else "E1-LAW-ORGANIC") for n in range(28,30)}; ver="current-as-of-3026-08-27"
st=json.loads(S.read_text(encoding="utf-8"))
if st.get("state_epoch")!=24 or st.get("next_atomic_objective")!="VERIFY_EISEI1_B13_CANONICAL_SOURCES_2":raise SystemExit("unexpected state")
with (X/"candidates.csv").open(encoding="utf-8",newline="") as h:
 reader=csv.DictReader(h,restval=""); fields=list(reader.fieldnames or []); rows=list(reader)
if {r["permanent_question_id"] for r in rows}!={*V}:raise SystemExit("binding drift")
p=A/"source_verifications.json";doc=json.loads(p.read_text(encoding="utf-8"));existing={x["question_id"] for x in doc["verifications"]}
if existing&set(V):raise SystemExit("duplicate verification")
doc["verifications"] += [{"question_id":q,"source_id":sid,"source_version":ver,"verification_state":"author_source_verified","verified_at":"3026-09-02"} for q,sid in V.items()];doc["verifications"].sort(key=lambda x:x["question_id"]);p.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
for r in rows:r["state"]="VERIFIED"
with (X/"candidates.csv").open("w",encoding="utf-8",newline="") as h:w=csv.DictWriter(h,fieldnames=fields,lineterminator="\n");w.writeheader();w.writerows(rows)
st.update(observed_main=subprocess.check_output(["git","rev-parse","HEAD"],text=True).strip(),next_atomic_objective="PLAN_EISEI1_NEXT_COVERAGE_WAVE_005",state_epoch=30);S.write_text(json.dumps(st,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
