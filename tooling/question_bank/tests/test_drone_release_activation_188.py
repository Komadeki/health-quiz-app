from __future__ import annotations
import csv,json,sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
BANK=ROOT/"question_banks/drone_second_class"
A=BANK/"authoring"
sys.path.insert(0,str(ROOT/"tooling/question_bank"))
from expansion import validate_expansion_batch
from validation import validate_bank
REV="drone-second-class-v2-release-2026-08-24"
OLD="drone-second-class-v1-release-2026-08-20"
class Release188Test(unittest.TestCase):
 def test_release_is_exact_and_generated(self):
  meta=json.loads((A/"bank.json").read_text(encoding="utf-8")); self.assertEqual(REV,meta["bank_revision"]); self.assertEqual("2026-08-24",meta["content_as_of"])
  with (A/"questions.csv").open(encoding="utf-8",newline="") as h: q={r["question_id"]:r for r in csv.DictReader(h)}
  ids=[f"DRONE-Q-{n:06d}" for n in range(1,189)]; self.assertTrue(set(ids).issubset(set(q))); self.assertTrue(all(q[i]["status"]=="active" for i in ids)); self.assertTrue(all(q[i]["last_reviewed_at"]=="2026-08-24" for i in ids[100:])); future=[r for qid,r in q.items() if int(qid.rsplit("-",1)[1])>188]; self.assertTrue(all(r["status"]=="draft" for r in future))
  with (A/"question_id_registry.csv").open(encoding="utf-8",newline="") as h: reg={r["question_id"]:r for r in csv.DictReader(h)}
  self.assertTrue(all(reg[i]["first_used_bank_revision"]==OLD for i in ids[:100])); self.assertTrue(all(reg[i]["first_used_bank_revision"]==REV for i in ids[100:])); self.assertTrue(all(not reg[qid]["first_used_bank_revision"] for qid in reg if int(qid.rsplit("-",1)[1])>188))
  released=json.loads((A/"released_questions.json").read_text(encoding="utf-8"))["released_questions"]; self.assertEqual(ids,[r["question_id"] for r in released])
  runtime_path=BANK/"generated/drone_second_class_bank.json"; app=ROOT/"apps/drone_second_class/assets/question_bank/drone_second_class_bank.json"; self.assertEqual(runtime_path.read_bytes(),app.read_bytes())
  runtime=json.loads(runtime_path.read_text(encoding="utf-8")); cards=[c for d in runtime["decks"] for u in d["units"] for c in u["cards"]]; self.assertEqual(set(ids),{c["stableId"] for c in cards}); self.assertEqual(20,sum(not c["isPremium"] for c in cards))
  manifest=json.loads((BANK/"generated/bank_manifest.json").read_text(encoding="utf-8")); self.assertEqual(188,manifest["question_count"]); self.assertEqual(20,manifest["free_question_count"]); self.assertEqual(REV,manifest["bank_revision"])
  result=validate_bank(BANK,check_generated=True); self.assertTrue(result.is_valid,[str(i) for i in result.issues])
  for n in range(1,5): self.assertEqual([],validate_expansion_batch(A/"batches"/f"batch_{n:03d}"))
 def test_exact_88_candidates_released(self):
  mapped=[]
  for n in range(1,5):
   with (A/"batches"/f"batch_{n:03d}"/"candidates.csv").open(encoding="utf-8",newline="") as h: rows=list(csv.DictReader(h))
   mapped += [r for r in rows if r["permanent_question_id"]]
  selected=[r for r in mapped if 101<=int(r["permanent_question_id"].rsplit("-",1)[1])<=188]
  self.assertEqual(88,len(selected)); self.assertTrue(all(r["state"]=="RELEASED" for r in selected))
  self.assertTrue(all(r["state"]!="RELEASED" for r in mapped if r not in selected))
if __name__=="__main__": unittest.main()
