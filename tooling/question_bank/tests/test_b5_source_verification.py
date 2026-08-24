from __future__ import annotations
import csv,json,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
BANK=ROOT/"question_banks/drone_second_class"
A=BANK/"authoring"
B=A/"batches/batch_005"
CIDS=[f"B5-OPS-C{i:03d}" for i in range(1,9)]
QIDS=[f"DRONE-Q-{i:06d}" for i in range(189,197)]
class B5SourceVerificationTest(unittest.TestCase):
 def test_b5_is_verified_without_release_activation(self):
  with (B/"candidates.csv").open(encoding="utf-8",newline="") as h: rows={r["candidate_id"]:r for r in csv.DictReader(h)}
  self.assertEqual(set(CIDS),set(rows)); self.assertTrue(all(rows[c]["state"]=="VERIFIED" for c in CIDS)); self.assertEqual(QIDS,[rows[c]["permanent_question_id"] for c in CIDS])
  with (A/"questions.csv").open(encoding="utf-8",newline="") as h: q={r["question_id"]:r for r in csv.DictReader(h)}
  self.assertEqual(196,len(q)); self.assertTrue(all(q[i]["status"]=="draft" for i in QIDS))
  v=json.loads((A/"source_verifications.json").read_text(encoding="utf-8"))["verifications"]; by={r["question_id"]:r for r in v}
  for qid in QIDS:
   self.assertEqual("author_source_verified",by[qid]["verification_state"]); self.assertEqual("5",by[qid]["source_version"]); self.assertEqual("2026-08-25",by[qid]["verified_at"])
  released=json.loads((A/"released_questions.json").read_text(encoding="utf-8"))["released_questions"]; self.assertEqual(188,len(released))
  meta=json.loads((A/"bank.json").read_text(encoding="utf-8")); runtime=json.loads((BANK/meta["runtime_output"]).read_text(encoding="utf-8")); cards=[c for d in runtime["decks"] for u in d["units"] for c in u["cards"]]; self.assertEqual(188,len(cards))
if __name__=="__main__": unittest.main()
