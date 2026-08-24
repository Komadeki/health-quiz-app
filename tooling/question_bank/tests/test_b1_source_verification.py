from __future__ import annotations
import csv,json,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
A=ROOT/"question_banks/drone_second_class/authoring"
B=A/"batches/batch_001"
IDS=[f"DRONE-Q-{n:06d}" for n in range(101,119)]
ACCEPTED={*[f"B1-R-C{i:03d}" for i in range(1,17)],"B1-R-C023","B1-R-C024"}
class T(unittest.TestCase):
 def test_verified(self):
  with (B/"candidates.csv").open(encoding="utf-8",newline="") as h: rows={r["candidate_id"]:r for r in csv.DictReader(h)}
  self.assertTrue(all(rows[c]["state"]=="VERIFIED" for c in ACCEPTED))
  v=json.loads((A/"source_verifications.json").read_text(encoding="utf-8"))["verifications"]; by={r["question_id"]:r for r in v}
  for q in IDS:
   self.assertEqual("author_source_verified",by[q]["verification_state"]); self.assertEqual("5",by[q]["source_version"]); self.assertEqual("2026-08-24",by[q]["verified_at"])
  released=json.loads((A/"released_questions.json").read_text(encoding="utf-8"))["released_questions"]; self.assertEqual(100,len(released))
if __name__=="__main__": unittest.main()
