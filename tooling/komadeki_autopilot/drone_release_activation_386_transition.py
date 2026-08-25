#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import subprocess
import sys
from copy import deepcopy
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BANK = REPO / "question_banks" / "drone_second_class"
A = BANK / "authoring"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "drone_state.json"
FREEZE_PATH = A / "release_activation_freeze_386_2026-08-26.json"
POLICY_PATH = A / "owner_dynamic_release_inclusion_2026-08-26.json"
REASSERT_PATH = A / "owner_target_400_reassertion_2026-08-26.json"
GUARD_PATH = REPO / "tooling" / "komadeki_autopilot" / "drone_owner_direction_guard.json"
sys.path.insert(0, str(REPO / "tooling" / "question_bank"))
from contract import load_bank_inputs, pretty_json_bytes
from expansion import validate_expansion_batch
from generation import build_released_questions_document, write_generated_files
from validation import validate_bank

RELEASE_ID = "drone-second-class-v4-release-2026-08-26"
CURRENT_RELEASE_ID = "drone-second-class-v3-release-2026-08-25"
RELEASE_DATE = "2026-08-26"
HIST = tuple(f"DRONE-Q-{n:06d}" for n in range(1, 189))
NEW = tuple(f"DRONE-Q-{n:06d}" for n in range(189, 387))
ALL = tuple(f"DRONE-Q-{n:06d}" for n in range(1, 387))
HIST_SET, NEW_SET, ALL_SET = set(HIST), set(NEW), set(ALL)
BATCHES = tuple(f"batch_{n:03d}" for n in range(5, 20))


def fail(msg: str) -> None:
    raise SystemExit(msg)


def read_csv(path: Path):
    with path.open(encoding="utf-8", newline="") as h:
        r = csv.DictReader(h)
        return list(r.fieldnames or []), list(r)


def write_csv(path: Path, fields, rows) -> None:
    with path.open("w", encoding="utf-8", newline="") as h:
        w = csv.DictWriter(h, fieldnames=fields, lineterminator="\n")
        w.writeheader(); w.writerows(rows)


def cards(runtime: dict) -> list[dict]:
    return [c for d in runtime.get("decks", []) for u in d.get("units", []) for c in u.get("cards", [])]


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        fail(f"expected one replacement in {path}: {old[:80]!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")


def replace_section(path: Path, start: str, end: str, replacement: str) -> None:
    text = path.read_text(encoding="utf-8")
    i, j = text.find(start), text.find(end)
    if i < 0 or j < 0 or j <= i:
        fail(f"section marker missing: {path}")
    path.write_text(text[:i] + replacement + text[j:], encoding="utf-8")


freeze = json.loads(FREEZE_PATH.read_text(encoding="utf-8"))
if freeze.get("freeze_id") != "DRONE-PRODUCTION-BANK-386-RELEASE-FREEZE-2026-08-26":
    fail("unexpected 386 freeze identity")
sel = freeze.get("release_selection", {})
expected_sel = {
    "current_active_count": 188, "current_released_count": 188, "current_runtime_count": 188,
    "current_free_question_count": 30, "frozen_canonical_count": 386,
    "frozen_source_verified_count": 386, "activation_question_count": 198,
    "activation_question_id_start": "DRONE-Q-000189", "activation_question_id_end": "DRONE-Q-000386",
    "expected_post_active_count": 386, "expected_post_released_count": 386,
    "expected_post_runtime_count": 386, "expected_post_free_question_count": 30,
    "expected_post_premium_question_count": 356,
}
if sel != expected_sel:
    fail("386 release selection drift")
planned = freeze.get("planned_release_identity", {})
if planned.get("bank_revision") != RELEASE_ID or planned.get("prior_bank_revision") != CURRENT_RELEASE_ID or planned.get("content_as_of") != RELEASE_DATE:
    fail("386 planned identity drift")
for rel, expected in freeze.get("baseline_bindings", {}).items():
    actual = subprocess.check_output(["git", "rev-parse", f"HEAD:{rel}"], text=True).strip()
    if actual != expected:
        fail(f"freeze-bound input drift: {rel}: {actual} != {expected}")

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("status") != "ACTIVE" or state.get("current_phase") != "QUESTION_BANK_COMPLETION" or state.get("human_blocker") is not None:
    fail("unexpected Drone state status/phase")
if state.get("state_epoch") != 143 or state.get("next_atomic_objective") != "EXECUTE_FROZEN_PRODUCTION_BANK_386_RELEASE_ACTIVATION":
    fail(f"unexpected Drone objective: {state.get('state_epoch')} / {state.get('next_atomic_objective')}")
policy = json.loads(POLICY_PATH.read_text(encoding="utf-8"))
reassert = json.loads(REASSERT_PATH.read_text(encoding="utf-8"))
guard = json.loads(GUARD_PATH.read_text(encoding="utf-8"))
if policy.get("status") != "ACTIVE" or policy.get("decision_id") != freeze.get("owner_policy_id"):
    fail("dynamic release policy not active")
if reassert.get("status") != "SUPERSEDED":
    fail("fixed-400 reassertion not superseded")
if guard.get("status") != "ACTIVE" or guard.get("guard_id") != freeze.get("owner_guard_id"):
    fail("owner-direction guard drift")

bank_path = A / "bank.json"
bank_before = json.loads(bank_path.read_text(encoding="utf-8"))
if bank_before.get("bank_revision") != CURRENT_RELEASE_ID or bank_before.get("content_as_of") != "2026-08-24":
    fail("pre-release bank identity drift")
manifest_path = BANK / "generated" / "bank_manifest.json"
generated_path = BANK / "generated" / "drone_second_class_bank.json"
app_asset = REPO / "apps" / "drone_second_class" / "assets" / "question_bank" / "drone_second_class_bank.json"
manifest_before = json.loads(manifest_path.read_text(encoding="utf-8"))
if manifest_before.get("bank_revision") != CURRENT_RELEASE_ID or manifest_before.get("question_count") != 188 or manifest_before.get("free_question_count") != 30:
    fail("pre-release generated manifest drift")
if generated_path.read_bytes() != app_asset.read_bytes():
    fail("pre-release generated/app asset mismatch")
runtime_before = json.loads(generated_path.read_text(encoding="utf-8"))
cb = cards(runtime_before)
if len(cb) != 188 or {c["stableId"] for c in cb} != HIST_SET or sum(not c["isPremium"] for c in cb) != 30:
    fail("pre-release runtime inventory drift")

q_path = A / "questions.csv"
q_fields, q_rows = read_csv(q_path)
q_lists = {}
for r in q_rows: q_lists.setdefault(r["question_id"], []).append(r)
if set(q_lists) != ALL_SET or any(len(v) != 1 for v in q_lists.values()):
    fail("canonical inventory must be exact unique Q1..Q386")
q = {k: v[0] for k, v in q_lists.items()}
if any(q[i]["status"] != "active" for i in HIST) or any(q[i]["status"] != "draft" for i in NEW):
    fail("canonical pre-release status drift")
if any(q[i]["is_free"] != "false" for i in NEW):
    fail("new release range must remain premium")
free_ids = {i for i in ALL if q[i]["is_free"] == "true"}
if len(free_ids) != 30 or not free_ids.issubset(HIST_SET):
    fail("free selection drift")
hist_q_before = {i: deepcopy(q[i]) for i in HIST}
new_q_before = {i: deepcopy(q[i]) for i in NEW}

r_path = A / "question_id_registry.csv"
r_fields, r_rows = read_csv(r_path)
r_lists = {}
for r in r_rows: r_lists.setdefault(r["question_id"], []).append(r)
if not ALL_SET.issubset(r_lists) or any(len(r_lists[i]) != 1 for i in ALL):
    fail("registry missing/duplicate Q1..Q386")
for qid in r_lists:
    if qid.startswith("DRONE-Q-"):
        try: n = int(qid.rsplit("-", 1)[1])
        except ValueError: continue
        if n > 386: fail(f"unexpected Drone ID beyond freeze: {qid}")
reg = {k: v[0] for k, v in r_lists.items() if len(v) == 1}
if any(reg[i]["status"] != "used" or not reg[i]["first_used_bank_revision"] or reg[i]["retired_at"] for i in HIST):
    fail("historical registry drift")
if any(reg[i]["status"] != "used" or reg[i]["first_used_bank_revision"] or reg[i]["retired_at"] for i in NEW):
    fail("new registry pre-release drift")
hist_reg_before = {i: deepcopy(reg[i]) for i in HIST}
new_reg_before = {i: deepcopy(reg[i]) for i in NEW}

released_path = A / "released_questions.json"
released_before = deepcopy(json.loads(released_path.read_text(encoding="utf-8")).get("released_questions", []))
if [r["question_id"] for r in released_before] != list(HIST):
    fail("pre-release snapshot must be exact Q1..Q188")

sources = json.loads((A / "sources.json").read_text(encoding="utf-8")).get("sources", [])
source_by_id = {str(x.get("source_id", "")): x for x in sources if isinstance(x, dict)}
ver = json.loads((A / "source_verifications.json").read_text(encoding="utf-8")).get("verifications", [])
ver_by_id = {}
for x in ver:
    if isinstance(x, dict): ver_by_id.setdefault(str(x.get("question_id", "")), []).append(x)
for qid in ALL:
    rows = ver_by_id.get(qid, [])
    if len(rows) != 1: fail(f"source verification missing/duplicate: {qid}")
    v, qr = rows[0], q[qid]
    src = source_by_id.get(qr["source_id"])
    if v.get("verification_state") != "author_source_verified" or v.get("source_id") != qr["source_id"] or src is None or str(v.get("source_version")) != str(src.get("source_version")):
        fail(f"source binding drift: {qid}")

batch_snapshots = {}
mapped = {}
for name in BATCHES:
    batch = A / "batches" / name
    errors = validate_expansion_batch(batch)
    if errors: fail(f"pre-release batch invalid {name}: {' | '.join(errors)}")
    fields, rows = read_csv(batch / "candidates.csv")
    batch_snapshots[batch] = (fields, deepcopy(rows))
    for row in rows:
        qid = row["permanent_question_id"]
        if qid not in NEW_SET: continue
        if row["state"] != "VERIFIED" or qid in mapped:
            fail(f"candidate release eligibility drift: {row['candidate_id']} / {qid}")
        qr = q[qid]
        for cf, qf in (("question","question"),("choice1","choice1"),("choice2","choice2"),("choice3","choice3"),("choice4","choice4"),("proposed_correct","correct_choice"),("explanation","explanation"),("source_id","source_id"),("source_locator","source_locator"),("unit_id","unit_id")):
            if row[cf] != qr[qf]: fail(f"candidate/canonical drift {row['candidate_id']}:{cf}")
        mapped[qid] = (batch, row["candidate_id"])
if set(mapped) != NEW_SET:
    fail(f"release candidate mapping must be exact 198, got {len(mapped)}")

pre = validate_bank(BANK, check_generated=False)
if not pre.is_valid: fail("pre-release bank invalid: " + " | ".join(str(i) for i in pre.errors))

for i in NEW:
    q[i]["status"] = "active"; q[i]["last_reviewed_at"] = RELEASE_DATE
write_csv(q_path, q_fields, q_rows)
for i in NEW: reg[i]["first_used_bank_revision"] = RELEASE_ID
write_csv(r_path, r_fields, r_rows)
bank_after = deepcopy(bank_before); bank_after["bank_revision"] = RELEASE_ID; bank_after["content_as_of"] = RELEASE_DATE
bank_path.write_text(json.dumps(bank_after, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

inputs = load_bank_inputs(BANK)
released_doc = build_released_questions_document(inputs)
released_after = released_doc.get("released_questions", [])
if len(released_after) != 386 or [x["question_id"] for x in released_after] != list(ALL): fail("staged released snapshot drift")
if released_after[:188] != released_before: fail("historical release prefix changed")
released_path.write_bytes(pretty_json_bytes(released_doc))
mid = validate_bank(BANK, check_generated=False)
if not mid.is_valid: fail("staged bank invalid: " + " | ".join(str(i) for i in mid.errors))
list(write_generated_files(BANK)); app_asset.write_bytes(generated_path.read_bytes())

for batch, (fields, before_rows) in batch_snapshots.items():
    current_fields, rows = read_csv(batch / "candidates.csv")
    if current_fields != fields: fail(f"candidate schema drift: {batch.name}")
    for row in rows:
        if row["permanent_question_id"] in NEW_SET: row["state"] = "RELEASED"
    write_csv(batch / "candidates.csv", fields, rows)

bank_readme = BANK / "README.md"
replace_once(bank_readme,
    "Production release v3 keeps the complete 188-question canonical bank and expands the\nfree tier from 20 to 30 questions without changing question content or permanent identities.",
    "Production release v4 activates the complete 386-question canonical bank while preserving the\nexisting 30-question free selection and all permanent question identities.")
replace_section(bank_readme, "## Release state\n", "## Validation snapshot identity\n",
"""## Release state\n\n- 386 / 386 canonical questions are Production active and released.\n- Production bank revision: `drone-second-class-v4-release-2026-08-26`.\n- Production runtime: 386 active questions, 30 free, and 356 premium.\n- Free selection preserves the exact v3 30-question set; Q189..Q386 remain premium.\n- `DRONE-Q-000001..DRONE-Q-000100` preserve first use in `drone-second-class-v1-release-2026-08-20`.\n- `DRONE-Q-000101..DRONE-Q-000188` preserve first use in `drone-second-class-v2-release-2026-08-24`.\n- `DRONE-Q-000189..DRONE-Q-000386` record first use in `drone-second-class-v4-release-2026-08-26`.\n- The current release set is frozen at 386 under `DRONE-PRODUCTION-BANK-386-RELEASE-FREEZE-2026-08-26`; later expansion is a separate bank revision.\n\n""")
replace_once(bank_readme,
    "The registry uses the existing `used` status. `DRONE-Q-000001..DRONE-Q-000100`\npreserve `drone-second-class-v1-release-2026-08-20` in `first_used_bank_revision`;\n`DRONE-Q-000101..DRONE-Q-000188` record\n`drone-second-class-v2-release-2026-08-24`. IDs beyond `DRONE-Q-000188` are not reserved.",
    "The registry uses the existing `used` status. `DRONE-Q-000001..DRONE-Q-000100` preserve `drone-second-class-v1-release-2026-08-20`; `DRONE-Q-000101..DRONE-Q-000188` preserve `drone-second-class-v2-release-2026-08-24`; and `DRONE-Q-000189..DRONE-Q-000386` record `drone-second-class-v4-release-2026-08-26` in `first_used_bank_revision`. IDs beyond `DRONE-Q-000386` are not reserved.")
replace_once(bank_readme,
    "Expansion IDs `DRONE-Q-000101..DRONE-Q-000188` are allocated and released; `DRONE-Q-000189` and later remain unreserved.",
    "Expansion IDs `DRONE-Q-000101..DRONE-Q-000386` are allocated and released; `DRONE-Q-000387` and later remain unreserved.")

app_readme = REPO / "apps" / "drone_second_class" / "README.md"
replace_once(app_readme, "The production entrypoint is `lib/main.dart`. It loads the generated 188-question\nruntime,", "The production entrypoint is `lib/main.dart`. It loads the generated 386-question\nruntime,")
replace_once(app_readme, "- Free: 20 questions, five in each unit.\n- Full unlock: all 188 questions (20 free + 168 premium).", "- Free: 30 questions.\n- Full unlock: all 386 questions (30 free + 356 premium).")

pt = REPO / "apps" / "drone_second_class" / "test" / "production_controller_test.dart"
text = pt.read_text(encoding="utf-8")
for old, new in (("Reference Product preserves the 188Q/30Q bank and neutral mock profile","Reference Product preserves the 386Q/30Q bank and neutral mock profile"),("drone-second-class-v3-release-2026-08-25",RELEASE_ID),("hasLength(188)","hasLength(386)"),("expect(unlocked.accessibleQuestionCount, 188);","expect(unlocked.accessibleQuestionCount, 386);")):
    if old not in text: fail(f"production test assertion missing: {old}")
    text = text.replace(old, new)
pt.write_text(text, encoding="utf-8")

for relative in ("tooling/question_bank/tests/test_b1_source_verification.py","tooling/question_bank/tests/test_b4_source_verification.py"):
    p = REPO / relative; t = p.read_text(encoding="utf-8")
    if "self.assertEqual(188, len(released))" not in t: fail(f"release count assertion missing: {relative}")
    p.write_text(t.replace("self.assertEqual(188, len(released))","self.assertEqual(386, len(released))"), encoding="utf-8")
p = REPO / "tooling/question_bank/tests/test_b4_integration.py"; t = p.read_text(encoding="utf-8")
for old, new in (("self.assertEqual(188, len(released))","self.assertEqual(386, len(released))"),("self.assertEqual(188, runtime_count)","self.assertEqual(386, runtime_count)")):
    if old not in t: fail(f"B4 assertion missing: {old}")
    t = t.replace(old, new)
p.write_text(t, encoding="utf-8")
p = REPO / "tooling/question_bank/tests/test_b5_source_verification.py"; t = p.read_text(encoding="utf-8")
for old, new in (("test_b5_is_verified_without_release_activation","test_b5_is_released_after_verified_activation"),('rows[c]["state"]=="VERIFIED"','rows[c]["state"]=="RELEASED"'),('q[i]["status"]=="draft"','q[i]["status"]=="active"'),("self.assertEqual(188,len(released))","self.assertEqual(386,len(released))"),("range(1,189)","range(1,387)"),("self.assertEqual(188,len(cards))","self.assertEqual(386,len(cards)")):
    if old not in t: fail(f"B5 assertion missing: {old}")
    t = t.replace(old, new)
p.write_text(t, encoding="utf-8")

old_test = REPO / "tooling/question_bank/tests/test_drone_release_activation_188.py"
if not old_test.is_file(): fail("188 release regression test missing")
old_test.unlink()
new_test = REPO / "tooling/question_bank/tests/test_drone_release_activation_386.py"
new_test.write_text('''from __future__ import annotations\nimport csv,json,sys,unittest\nfrom pathlib import Path\nROOT=Path(__file__).resolve().parents[3]; BANK=ROOT/"question_banks/drone_second_class"; A=BANK/"authoring"\nsys.path.insert(0,str(ROOT/"tooling/question_bank"))\nfrom expansion import validate_expansion_batch\nfrom validation import validate_bank\nREV="drone-second-class-v4-release-2026-08-26"; MID="drone-second-class-v2-release-2026-08-24"; OLD="drone-second-class-v1-release-2026-08-20"\nclass Release386Test(unittest.TestCase):\n def test_release(self):\n  ids=[f"DRONE-Q-{n:06d}" for n in range(1,387)]; meta=json.loads((A/"bank.json").read_text()); self.assertEqual(REV,meta["bank_revision"]); self.assertEqual("2026-08-26",meta["content_as_of"])\n  with (A/"questions.csv").open(newline="",encoding="utf-8") as h:q={r["question_id"]:r for r in csv.DictReader(h)}\n  self.assertEqual(set(ids),set(q)); self.assertTrue(all(q[i]["status"]=="active" for i in ids)); self.assertEqual(30,sum(q[i]["is_free"]=="true" for i in ids)); self.assertTrue(all(q[i]["is_free"]=="false" for i in ids[188:])); self.assertTrue(all(q[i]["last_reviewed_at"]=="2026-08-26" for i in ids[188:]))\n  with (A/"question_id_registry.csv").open(newline="",encoding="utf-8") as h:r={x["question_id"]:x for x in csv.DictReader(h)}\n  self.assertTrue(all(r[i]["first_used_bank_revision"]==OLD for i in ids[:100])); self.assertTrue(all(r[i]["first_used_bank_revision"]==MID for i in ids[100:188])); self.assertTrue(all(r[i]["first_used_bank_revision"]==REV for i in ids[188:])); self.assertFalse(any(int(i.rsplit("-",1)[1])>386 for i in r if i.startswith("DRONE-Q-")))\n  released=json.loads((A/"released_questions.json").read_text())["released_questions"]; self.assertEqual(ids,[x["question_id"] for x in released])\n  gen=BANK/"generated/drone_second_class_bank.json"; app=ROOT/"apps/drone_second_class/assets/question_bank/drone_second_class_bank.json"; self.assertEqual(gen.read_bytes(),app.read_bytes()); runtime=json.loads(gen.read_text()); cards=[c for d in runtime["decks"] for u in d["units"] for c in u["cards"]]; self.assertEqual(set(ids),{c["stableId"] for c in cards}); self.assertEqual(30,sum(not c["isPremium"] for c in cards))\n  m=json.loads((BANK/"generated/bank_manifest.json").read_text()); self.assertEqual(386,m["question_count"]); self.assertEqual(30,m["free_question_count"]); self.assertEqual(REV,m["bank_revision"]); self.assertTrue(validate_bank(BANK,check_generated=True).is_valid)\n  for n in range(1,20): self.assertEqual([],validate_expansion_batch(A/"batches"/f"batch_{n:03d}"))\n def test_new_candidates_released(self):\n  rows=[]\n  for n in range(5,20):\n   with (A/"batches"/f"batch_{n:03d}"/"candidates.csv").open(newline="",encoding="utf-8") as h: rows += list(csv.DictReader(h))\n  selected=[r for r in rows if r["permanent_question_id"] and 189<=int(r["permanent_question_id"].rsplit("-",1)[1])<=386]; self.assertEqual(198,len(selected)); self.assertEqual({f"DRONE-Q-{n:06d}" for n in range(189,387)},{r["permanent_question_id"] for r in selected}); self.assertTrue(all(r["state"]=="RELEASED" for r in selected))\nif __name__=="__main__":unittest.main()\n''', encoding="utf-8")

# Exact mutation and generated invariants.
_, q_after_rows = read_csv(q_path); qa = {r["question_id"]: r for r in q_after_rows}
for i in HIST:
    if qa[i] != hist_q_before[i]: fail(f"historical canonical changed: {i}")
for i in NEW:
    for f in q_fields:
        exp = "active" if f == "status" else RELEASE_DATE if f == "last_reviewed_at" else new_q_before[i][f]
        if qa[i][f] != exp: fail(f"unexpected canonical mutation {i}:{f}")
if {i for i in ALL if qa[i]["is_free"] == "true"} != free_ids: fail("free set changed")
_, rr = read_csv(r_path); ra = {r["question_id"]: r for r in rr}
for i in HIST:
    if ra[i] != hist_reg_before[i]: fail(f"historical registry changed: {i}")
for i in NEW:
    for f in r_fields:
        exp = RELEASE_ID if f == "first_used_bank_revision" else new_reg_before[i][f]
        if ra[i][f] != exp: fail(f"unexpected registry mutation {i}:{f}")
for batch, (fields, before) in batch_snapshots.items():
    af, rows = read_csv(batch / "candidates.csv"); bb={r["candidate_id"]:r for r in before}
    if af != fields or len(rows) != len(before): fail(f"candidate shape changed: {batch.name}")
    for row in rows:
        b=bb[row["candidate_id"]]; selected=row["permanent_question_id"] in NEW_SET
        for f in fields:
            exp="RELEASED" if selected and f=="state" else b[f]
            if row[f] != exp: fail(f"unexpected candidate mutation {batch.name}/{row['candidate_id']}:{f}")
    errors=validate_expansion_batch(batch)
    if errors: fail(f"post-release batch invalid {batch.name}: {' | '.join(errors)}")
post=validate_bank(BANK,check_generated=True)
if not post.is_valid: fail("post-release bank invalid: " + " | ".join(str(i) for i in post.errors))
ma=json.loads(manifest_path.read_text()); ca=cards(json.loads(generated_path.read_text()))
if ma.get("bank_revision")!=RELEASE_ID or ma.get("content_as_of")!=RELEASE_DATE or ma.get("question_count")!=386 or ma.get("free_question_count")!=30: fail("post-release manifest drift")
if generated_path.read_bytes()!=app_asset.read_bytes() or len(ca)!=386 or {c["stableId"] for c in ca}!=ALL_SET or {c["stableId"] for c in ca if not c["isPremium"]}!=free_ids: fail("post-release runtime drift")

receipt = {
 "schema_version":"1.0", "activation_id":"DRONE-PRODUCTION-BANK-386-RELEASE-ACTIVATION-2026-08-26",
 "freeze_id":freeze["freeze_id"], "bank_revision":RELEASE_ID, "activated_count":386, "free_count":30,
 "premium_count":356, "newly_activated_range":["DRONE-Q-000189","DRONE-Q-000386"],
 "historical_release_prefix_preserved":True, "generated_app_asset_byte_identical":True,
 "question_bank_validation":"PASS", "candidate_lifecycle":"Q189..Q386 VERIFIED_TO_RELEASED",
 "next_phase":"FEATURE_COMPLETION"
}
(A/"release_activation_386.json").write_text(json.dumps(receipt,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
state["observed_main"] = subprocess.check_output(["git","rev-parse","origin/main"],text=True).strip()
state["current_phase"]="FEATURE_COMPLETION"; state["state_epoch"]=144; state["next_atomic_objective"]="VERIFY_FEATURE_COMPLETION_EXIT_CRITERIA"
STATE_PATH.write_text(json.dumps(state,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
