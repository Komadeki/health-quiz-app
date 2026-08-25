from __future__ import annotations
import csv,json,sys,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]; BANK=ROOT/"question_banks/drone_second_class"; A=BANK/"authoring"
sys.path.insert(0,str(ROOT/"tooling/question_bank"))
from expansion import validate_expansion_batch
from validation import validate_bank
REV="drone-second-class-v4-release-2026-08-26"; MID="drone-second-class-v2-release-2026-08-24"; OLD="drone-second-class-v1-release-2026-08-20"
class Release386Test(unittest.TestCase):
 def test_release(self):
  ids=[f"DRONE-Q-{n:06d}" for n in range(1,387)]; meta=json.loads((A/"bank.json").read_text()); self.assertEqual(REV,meta["bank_revision"]); self.assertEqual("2026-08-26",meta["content_as_of"])
  with (A/"questions.csv").open(newline="",encoding="utf-8") as h:q={r["question_id"]:r for r in csv.DictReader(h)}
  self.assertEqual(set(ids),set(q)); self.assertTrue(all(q[i]["status"]=="active" for i in ids)); self.assertEqual(30,sum(q[i]["is_free"]=="true" for i in ids)); self.assertTrue(all(q[i]["is_free"]=="false" for i in ids[188:])); self.assertTrue(all(q[i]["last_reviewed_at"]=="2026-08-26" for i in ids[188:]))
  with (A/"question_id_registry.csv").open(newline="",encoding="utf-8") as h:r={x["question_id"]:x for x in csv.DictReader(h)}
  self.assertTrue(all(r[i]["first_used_bank_revision"]==OLD for i in ids[:100])); self.assertTrue(all(r[i]["first_used_bank_revision"]==MID for i in ids[100:188])); self.assertTrue(all(r[i]["first_used_bank_revision"]==REV for i in ids[188:])); self.assertFalse(any(int(i.rsplit("-",1)[1])>386 for i in r if i.startswith("DRONE-Q-")))
  released=json.loads((A/"released_questions.json").read_text())["released_questions"]; self.assertEqual(ids,[x["question_id"] for x in released])
  gen=BANK/"generated/drone_second_class_bank.json"; app=ROOT/"apps/drone_second_class/assets/question_bank/drone_second_class_bank.json"; self.assertEqual(gen.read_bytes(),app.read_bytes()); runtime=json.loads(gen.read_text()); cards=[c for d in runtime["decks"] for u in d["units"] for c in u["cards"]]; self.assertEqual(set(ids),{c["stableId"] for c in cards}); self.assertEqual(30,sum(not c["isPremium"] for c in cards))
  m=json.loads((BANK/"generated/bank_manifest.json").read_text()); self.assertEqual(386,m["question_count"]); self.assertEqual(30,m["free_question_count"]); self.assertEqual(REV,m["bank_revision"]); self.assertTrue(validate_bank(BANK,check_generated=True).is_valid)
  for n in range(1,20): self.assertEqual([],validate_expansion_batch(A/"batches"/f"batch_{n:03d}"))
 def test_new_candidates_released(self):
  rows=[]
  for n in range(5,20):
   with (A/"batches"/f"batch_{n:03d}"/"candidates.csv").open(newline="",encoding="utf-8") as h: rows += list(csv.DictReader(h))
  selected=[r for r in rows if r["permanent_question_id"] and 189<=int(r["permanent_question_id"].rsplit("-",1)[1])<=386]; self.assertEqual(198,len(selected)); self.assertEqual({f"DRONE-Q-{n:06d}" for n in range(189,387)},{r["permanent_question_id"] for r in selected}); self.assertTrue(all(r["state"]=="RELEASED" for r in selected))
if __name__=="__main__":unittest.main()
