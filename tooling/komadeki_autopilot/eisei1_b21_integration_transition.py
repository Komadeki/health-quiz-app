#!/usr/bin/env python3
from pathlib import Path
import json, subprocess, sys
R=Path(__file__).resolve().parents[2]; sys.path.insert(0,str(R/"tooling/question_bank"))
from transaction import QuestionExpansionTransaction
from eisei1_ready_for_id_integration_transition import canonical_row
B=R/"question_banks/eisei1"; X=B/"authoring/batches/batch_021"; S=R/"tooling/komadeki_autopilot/eisei1_state.json"
st=json.loads(S.read_text(encoding="utf-8"))
if st.get("state_epoch")!=49 or st.get("next_atomic_objective")!="ALLOCATE_AND_INTEGRATE_EISEI1_B21_ACCEPTED_2": raise SystemExit("unexpected state")
ids=("E1-B21-HH-C001","E1-B21-LG-C001")
t=QuestionExpansionTransaction(B,X,ids,question_factory=canonical_row)
if t.plan().mapping!={"E1-B21-HH-C001":"EISEI1-Q-000037","E1-B21-LG-C001":"EISEI1-Q-000038"}: raise SystemExit("allocation failed")
t.apply()
st.update(observed_main=subprocess.check_output(["git","rev-parse","HEAD"],text=True).strip(),next_atomic_objective="VERIFY_EISEI1_B21_CANONICAL_SOURCES_2",state_epoch=50)
S.write_text(json.dumps(st,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
