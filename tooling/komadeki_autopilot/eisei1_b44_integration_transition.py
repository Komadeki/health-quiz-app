from pathlib import Path
import json, subprocess, sys

R = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(R / "tooling/question_bank"))
from transaction import QuestionExpansionTransaction
from eisei1_ready_for_id_integration_transition import canonical_row

B = R / "question_banks/eisei1"
X = B / "authoring/batches/batch_044"
S = R / "tooling/komadeki_autopilot/eisei1_state.json"
s = json.loads(S.read_text())
if s["state_epoch"] != 141 or s["next_atomic_objective"] != "ALLOCATE_AND_INTEGRATE_EISEI1_B44_ACCEPTED_1":
    raise SystemExit("unexpected state")
t = QuestionExpansionTransaction(B, X, ("E1-B44-HH-C001",), question_factory=canonical_row)
if t.plan().mapping != {"E1-B44-HH-C001": "EISEI1-Q-000061"}:
    raise SystemExit("allocation failed")
t.apply()
s.update(observed_main=subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(), next_atomic_objective="VERIFY_EISEI1_B44_CANONICAL_SOURCES_1", state_epoch=142)
S.write_text(json.dumps(s, ensure_ascii=False, indent=2) + "\n")
