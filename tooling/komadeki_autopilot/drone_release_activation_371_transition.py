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
AUTHORING = BANK / "authoring"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "drone_state.json"
ACTIVATION_PATH = AUTHORING / "release_activation_371.json"
RELEASE_CUT_PATH = AUTHORING / "owner_release_cut_371_2026-08-25.json"
TOOL_DIR = REPO / "tooling" / "question_bank"
sys.path.insert(0, str(TOOL_DIR))

from contract import load_bank_inputs, pretty_json_bytes  # noqa: E402
from expansion import validate_expansion_batch  # noqa: E402
from generation import build_released_questions_document, write_generated_files  # noqa: E402
from validation import validate_bank  # noqa: E402

RELEASE_ID = "drone-second-class-v4-release-2026-08-25"
CURRENT_RELEASE_ID = "drone-second-class-v3-release-2026-08-25"
RELEASE_DATE = "2026-08-25"
HISTORICAL_IDS = tuple(f"DRONE-Q-{n:06d}" for n in range(1, 189))
SELECTED_IDS = tuple(f"DRONE-Q-{n:06d}" for n in range(189, 372))
ALL_IDS = tuple(f"DRONE-Q-{n:06d}" for n in range(1, 372))
HISTORICAL_SET = set(HISTORICAL_IDS)
SELECTED_SET = set(SELECTED_IDS)
ALL_SET = set(ALL_IDS)
SELECTED_BATCH_NAMES = tuple(f"batch_{n:03d}" for n in range(5, 19))


def fail(message: str) -> None:
    raise SystemExit(message)


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), list(reader)


def write_csv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def runtime_cards(runtime: dict) -> list[dict]:
    return [
        card
        for deck in runtime.get("decks", [])
        for unit in deck.get("units", [])
        for card in unit.get("cards", [])
    ]


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if text.count(old) != 1:
        fail(f"expected exactly one release-fact replacement in {path}: {old[:80]!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")


def replace_section(path: Path, start_marker: str, end_marker: str, replacement: str) -> None:
    text = path.read_text(encoding="utf-8")
    start = text.find(start_marker)
    end = text.find(end_marker)
    if start < 0 or end < 0 or end <= start:
        fail(f"release-fact section markers missing in {path}")
    path.write_text(text[:start] + replacement + text[end:], encoding="utf-8")


activation = json.loads(ACTIVATION_PATH.read_text(encoding="utf-8"))
if activation.get("activation_id") != "DRONE-PRODUCTION-BANK-371-RELEASE-ACTIVATION":
    fail("unexpected 371 activation contract")
selection = activation.get("release_selection", {})
if selection != {
    "current_active_count": 188,
    "current_released_count": 188,
    "current_runtime_count": 188,
    "canonical_question_count": 371,
    "activation_question_count": 183,
    "activation_question_id_start": "DRONE-Q-000189",
    "activation_question_id_end": "DRONE-Q-000371",
    "expected_post_active_count": 371,
    "expected_post_released_count": 371,
    "expected_post_runtime_count": 371,
}:
    fail("371 release selection drift")
planned = activation.get("planned_release_identity", {})
if (
    planned.get("current_bank_revision") != CURRENT_RELEASE_ID
    or planned.get("bank_revision") != RELEASE_ID
    or planned.get("content_as_of") != RELEASE_DATE
    or planned.get("expected_free_question_count") != 30
    or planned.get("expected_premium_question_count") != 341
):
    fail("371 planned release identity drift")
if tuple(activation.get("selected_candidate_batches", [])) != SELECTED_BATCH_NAMES:
    fail("selected candidate batch set drift")

# Fail closed on every persisted SHA-bound release input after current-main reconciliation.
for relative_path, expected_blob in activation.get("baseline_bindings", {}).items():
    actual_blob = subprocess.check_output(
        ["git", "rev-parse", f"HEAD:{relative_path}"], text=True
    ).strip()
    if actual_blob != expected_blob:
        fail(f"bound input drift: {relative_path}: {actual_blob} != {expected_blob}")

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("status") != "ACTIVE" or state.get("current_phase") != "QUESTION_BANK_COMPLETION":
    fail("unexpected Drone phase/status")
if state.get("state_epoch") != 132 or state.get("next_atomic_objective") != "EXECUTE_PRODUCTION_BANK_371_RELEASE_ACTIVATION":
    fail(f"unexpected Drone state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}")
if state.get("human_blocker") is not None:
    fail("unexpected human blocker")

release_cut = json.loads(RELEASE_CUT_PATH.read_text(encoding="utf-8"))
cut = release_cut.get("release_cut", {})
if (
    release_cut.get("decision_id") != "DRONE-OWNER-RELEASE-CUT-371-2026-08-25"
    or release_cut.get("status") != "ACTIVE"
    or cut.get("final_source_verified_canonical_after_b18") != 371
    or cut.get("current_released_runtime") != 188
    or cut.get("new_authoring_after_b18") != "CLOSED_FOR_THIS_RELEASE"
    or cut.get("additional_residual_scan_before_release") is not False
    or cut.get("fixed_400_target") is not False
):
    fail("owner 371 release-cut contract drift")

bank_path = AUTHORING / "bank.json"
bank_before = json.loads(bank_path.read_text(encoding="utf-8"))
if bank_before.get("bank_revision") != CURRENT_RELEASE_ID or bank_before.get("content_as_of") != "2026-08-24":
    fail("pre-activation bank identity drift")

manifest_path = BANK / "generated" / "bank_manifest.json"
manifest_before = json.loads(manifest_path.read_text(encoding="utf-8"))
if (
    manifest_before.get("bank_revision") != CURRENT_RELEASE_ID
    or manifest_before.get("question_count") != 188
    or manifest_before.get("free_question_count") != 30
):
    fail("pre-activation manifest drift")
generated_path = BANK / "generated" / "drone_second_class_bank.json"
app_asset_path = REPO / "apps" / "drone_second_class" / "assets" / "question_bank" / "drone_second_class_bank.json"
generated_before = generated_path.read_bytes()
if app_asset_path.read_bytes() != generated_before:
    fail("pre-activation generated/app asset mismatch")
runtime_before = json.loads(generated_before.decode("utf-8"))
runtime_before_cards = runtime_cards(runtime_before)
if len(runtime_before_cards) != 188 or {c["stableId"] for c in runtime_before_cards} != HISTORICAL_SET:
    fail("pre-activation runtime ID inventory drift")
if sum(not c["isPremium"] for c in runtime_before_cards) != 30:
    fail("pre-activation runtime free count drift")

questions_path = AUTHORING / "questions.csv"
q_fields, questions = read_csv(questions_path)
q_rows_by_id: dict[str, list[dict[str, str]]] = {}
for row in questions:
    q_rows_by_id.setdefault(row["question_id"], []).append(row)
if set(q_rows_by_id) != ALL_SET or any(len(rows) != 1 for rows in q_rows_by_id.values()):
    fail("canonical ID inventory must be exact unique Q1..Q371")
q_by_id = {qid: rows[0] for qid, rows in q_rows_by_id.items()}
if any(q_by_id[qid]["status"] != "active" for qid in HISTORICAL_IDS):
    fail("Q1..Q188 must remain active before v4 activation")
if any(q_by_id[qid]["status"] != "draft" for qid in SELECTED_IDS):
    fail("Q189..Q371 must remain draft before v4 activation")
if any(q_by_id[qid]["is_free"] != "false" for qid in SELECTED_IDS):
    fail("Q189..Q371 must remain premium")
free_ids_before = {qid for qid in ALL_IDS if q_by_id[qid]["is_free"] == "true"}
if len(free_ids_before) != 30 or not free_ids_before.issubset(HISTORICAL_SET):
    fail("canonical free-ID set must be exact current 30 historical IDs")
historical_questions_before = {qid: deepcopy(q_by_id[qid]) for qid in HISTORICAL_IDS}
selected_questions_before = {qid: deepcopy(q_by_id[qid]) for qid in SELECTED_IDS}

registry_path = AUTHORING / "question_id_registry.csv"
r_fields, registry = read_csv(registry_path)
r_rows_by_id: dict[str, list[dict[str, str]]] = {}
for row in registry:
    r_rows_by_id.setdefault(row["question_id"], []).append(row)
if not ALL_SET.issubset(r_rows_by_id) or any(len(r_rows_by_id[qid]) != 1 for qid in ALL_IDS):
    fail("registry must contain one row for every Q1..Q371")
for qid in r_rows_by_id:
    if qid.startswith("DRONE-Q-"):
        try:
            number = int(qid.rsplit("-", 1)[1])
        except ValueError:
            continue
        if number > 371:
            fail(f"unexpected allocated Drone ID beyond release cut: {qid}")
r_by_id = {qid: rows[0] for qid, rows in r_rows_by_id.items() if len(rows) == 1}
if any(
    r_by_id[qid]["status"] != "used"
    or not r_by_id[qid]["first_used_bank_revision"]
    or r_by_id[qid]["retired_at"]
    for qid in HISTORICAL_IDS
):
    fail("historical registry release identity drift")
if any(
    r_by_id[qid]["status"] != "used"
    or r_by_id[qid]["first_used_bank_revision"]
    or r_by_id[qid]["retired_at"]
    for qid in SELECTED_IDS
):
    fail("Q189..Q371 registry pre-release state drift")
historical_registry_before = {qid: deepcopy(r_by_id[qid]) for qid in HISTORICAL_IDS}
selected_registry_before = {qid: deepcopy(r_by_id[qid]) for qid in SELECTED_IDS}

released_path = AUTHORING / "released_questions.json"
released_doc_before = json.loads(released_path.read_text(encoding="utf-8"))
released_before = deepcopy(released_doc_before.get("released_questions", []))
if [row["question_id"] for row in released_before] != list(HISTORICAL_IDS):
    fail("pre-activation released snapshot must be exact Q1..Q188")

sources = json.loads((AUTHORING / "sources.json").read_text(encoding="utf-8")).get("sources", [])
source_by_id = {str(row.get("source_id", "")): row for row in sources if isinstance(row, dict)}
verification_rows = json.loads((AUTHORING / "source_verifications.json").read_text(encoding="utf-8")).get("verifications", [])
verification_by_id: dict[str, list[dict]] = {}
for row in verification_rows:
    if isinstance(row, dict):
        verification_by_id.setdefault(str(row.get("question_id", "")), []).append(row)
for qid in ALL_IDS:
    rows = verification_by_id.get(qid, [])
    if len(rows) != 1:
        fail(f"exact source verification missing/duplicated: {qid}")
    verification = rows[0]
    question = q_by_id[qid]
    source = source_by_id.get(question["source_id"])
    if (
        verification.get("verification_state") != "author_source_verified"
        or verification.get("source_id") != question["source_id"]
        or source is None
        or str(verification.get("source_version")) != str(source.get("source_version"))
    ):
        fail(f"source verification binding drift: {qid}")

# All and only Q189..Q371 must be mapped by VERIFIED candidates in B5..B18.
batch_snapshots: dict[Path, tuple[list[str], list[dict[str, str]]]] = {}
mapped_candidates: dict[str, tuple[Path, str]] = {}
for batch_name in SELECTED_BATCH_NAMES:
    batch = AUTHORING / "batches" / batch_name
    errors = validate_expansion_batch(batch)
    if errors:
        fail(f"pre-activation batch validation failed {batch_name}: {' | '.join(errors)}")
    fields, rows = read_csv(batch / "candidates.csv")
    batch_snapshots[batch] = (fields, deepcopy(rows))
    for row in rows:
        qid = row["permanent_question_id"]
        if qid not in SELECTED_SET:
            continue
        if row["state"] != "VERIFIED":
            fail(f"selected candidate not VERIFIED: {row['candidate_id']} / {qid}")
        if qid in mapped_candidates:
            fail(f"duplicate selected candidate mapping: {qid}")
        question = q_by_id[qid]
        for candidate_field, question_field in (
            ("question", "question"),
            ("choice1", "choice1"),
            ("choice2", "choice2"),
            ("choice3", "choice3"),
            ("choice4", "choice4"),
            ("proposed_correct", "correct_choice"),
            ("explanation", "explanation"),
            ("source_id", "source_id"),
            ("source_locator", "source_locator"),
            ("unit_id", "unit_id"),
        ):
            if row[candidate_field] != question[question_field]:
                fail(f"candidate/canonical binding drift {row['candidate_id']}:{candidate_field}")
        mapped_candidates[qid] = (batch, row["candidate_id"])
if set(mapped_candidates) != SELECTED_SET:
    fail(f"selected candidate mapping must be exact 183, got {len(mapped_candidates)}")

pre_validation = validate_bank(BANK, check_generated=False)
if not pre_validation.is_valid:
    fail("pre-activation canonical validation failed: " + " | ".join(str(i) for i in pre_validation.errors))

# Stage the complete release atomically on the PR branch.
for qid in SELECTED_IDS:
    q_by_id[qid]["status"] = "active"
    q_by_id[qid]["last_reviewed_at"] = RELEASE_DATE
write_csv(questions_path, q_fields, questions)

for qid in SELECTED_IDS:
    r_by_id[qid]["first_used_bank_revision"] = RELEASE_ID
write_csv(registry_path, r_fields, registry)

bank_after = deepcopy(bank_before)
bank_after["bank_revision"] = RELEASE_ID
bank_after["content_as_of"] = RELEASE_DATE
bank_path.write_text(json.dumps(bank_after, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

inputs = load_bank_inputs(BANK)
released_after_doc = build_released_questions_document(inputs)
released_after = released_after_doc.get("released_questions", [])
if len(released_after) != 371 or [row["question_id"] for row in released_after] != list(ALL_IDS):
    fail("staged released snapshot must be exact Q1..Q371")
if released_after[:188] != released_before:
    fail("371 release would rewrite historical Q1..Q188 release contracts")
released_path.write_bytes(pretty_json_bytes(released_after_doc))

mid_validation = validate_bank(BANK, check_generated=False)
if not mid_validation.is_valid:
    fail("staged canonical validation failed: " + " | ".join(str(i) for i in mid_validation.errors))
list(write_generated_files(BANK))
app_asset_path.write_bytes(generated_path.read_bytes())

for batch, (fields, before_rows) in batch_snapshots.items():
    current_fields, current_rows = read_csv(batch / "candidates.csv")
    if current_fields != fields:
        fail(f"candidate schema drift during activation: {batch.name}")
    for row in current_rows:
        if row["permanent_question_id"] in SELECTED_SET:
            row["state"] = "RELEASED"
    write_csv(batch / "candidates.csv", fields, current_rows)

# Update durable release facts only; no product-scope or question-content change.
bank_readme = BANK / "README.md"
replace_once(
    bank_readme,
    "Production release v3 keeps the complete 188-question canonical bank and expands the\nfree tier from 20 to 30 questions without changing question content or permanent identities.",
    "Production release v4 activates the complete 371-question canonical bank while preserving the\nexisting 30-question free selection and all permanent question identities."
)
replace_section(
    bank_readme,
    "## Release state\n",
    "## Validation snapshot identity\n",
    """## Release state\n\n- 371 / 371 canonical questions are Production active and released.\n- Production bank revision: `drone-second-class-v4-release-2026-08-25`.\n- Production runtime: 371 active questions, 30 free, and 341 premium.\n- Free selection preserves the exact v3 30-question set; Q189..Q371 remain premium.\n- `DRONE-Q-000001..DRONE-Q-000100` preserve first use in `drone-second-class-v1-release-2026-08-20`.\n- `DRONE-Q-000101..DRONE-Q-000188` preserve first use in `drone-second-class-v2-release-2026-08-24`.\n- `DRONE-Q-000189..DRONE-Q-000371` record first use in `drone-second-class-v4-release-2026-08-25`.\n- `DRONE-Q-000372` and later IDs remain unreserved.\n- New authoring is closed for this release under `DRONE-OWNER-RELEASE-CUT-371-2026-08-25`; any later expansion is a separate post-release revision.\n\n"""
)
replace_once(
    bank_readme,
    "The registry uses the existing `used` status. `DRONE-Q-000001..DRONE-Q-000100`\npreserve `drone-second-class-v1-release-2026-08-20` in `first_used_bank_revision`;\n`DRONE-Q-000101..DRONE-Q-000188` record\n`drone-second-class-v2-release-2026-08-24`. IDs beyond `DRONE-Q-000188` are not reserved.",
    "The registry uses the existing `used` status. `DRONE-Q-000001..DRONE-Q-000100`\npreserve `drone-second-class-v1-release-2026-08-20`; `DRONE-Q-000101..DRONE-Q-000188`\npreserve `drone-second-class-v2-release-2026-08-24`; and `DRONE-Q-000189..DRONE-Q-000371`\nrecord `drone-second-class-v4-release-2026-08-25` in `first_used_bank_revision`. IDs beyond `DRONE-Q-000371` are not reserved."
)
replace_once(
    bank_readme,
    "Expansion IDs `DRONE-Q-000101..DRONE-Q-000188` are allocated and released; `DRONE-Q-000189` and later remain unreserved.",
    "Expansion IDs `DRONE-Q-000101..DRONE-Q-000371` are allocated and released; `DRONE-Q-000372` and later remain unreserved."
)

app_readme = REPO / "apps" / "drone_second_class" / "README.md"
replace_once(app_readme, "The production entrypoint is `lib/main.dart`. It loads the generated 188-question\nruntime,", "The production entrypoint is `lib/main.dart`. It loads the generated 371-question\nruntime,")
replace_once(app_readme, "- Free: 20 questions, five in each unit.\n- Full unlock: all 188 questions (20 free + 168 premium).", "- Free: 30 questions.\n- Full unlock: all 371 questions (30 free + 341 premium).")

production_test = REPO / "apps" / "drone_second_class" / "test" / "production_controller_test.dart"
text = production_test.read_text(encoding="utf-8")
for old, new in (
    ("Reference Product preserves the 188Q/30Q bank and neutral mock profile", "Reference Product preserves the 371Q/30Q bank and neutral mock profile"),
    ("drone-second-class-v3-release-2026-08-25", RELEASE_ID),
    ("hasLength(188)", "hasLength(371)"),
    ("expect(unlocked.accessibleQuestionCount, 188);", "expect(unlocked.accessibleQuestionCount, 371);"),
):
    if old not in text:
        fail(f"production controller release assertion missing: {old}")
    text = text.replace(old, new)
production_test.write_text(text, encoding="utf-8")

for relative in (
    "tooling/question_bank/tests/test_b1_source_verification.py",
    "tooling/question_bank/tests/test_b4_source_verification.py",
):
    path = REPO / relative
    text = path.read_text(encoding="utf-8")
    if "self.assertEqual(188, len(released))" not in text:
        fail(f"stale release count assertion missing: {relative}")
    path.write_text(text.replace("self.assertEqual(188, len(released))", "self.assertEqual(371, len(released))"), encoding="utf-8")

b4_test = REPO / "tooling" / "question_bank" / "tests" / "test_b4_integration.py"
text = b4_test.read_text(encoding="utf-8")
for old, new in (
    ("self.assertEqual(188, len(released))", "self.assertEqual(371, len(released))"),
    ("self.assertEqual(188, runtime_count)", "self.assertEqual(371, runtime_count)"),
):
    if old not in text:
        fail(f"B4 release assertion missing: {old}")
    text = text.replace(old, new)
b4_test.write_text(text, encoding="utf-8")

b5_test = REPO / "tooling" / "question_bank" / "tests" / "test_b5_source_verification.py"
text = b5_test.read_text(encoding="utf-8")
for old, new in (
    ("test_b5_is_verified_without_release_activation", "test_b5_is_released_after_verified_activation"),
    ('rows[c]["state"]=="VERIFIED"', 'rows[c]["state"]=="RELEASED"'),
    ('q[i]["status"]=="draft"', 'q[i]["status"]=="active"'),
    ("self.assertEqual(188,len(released))", "self.assertEqual(371,len(released))"),
    ("range(1,189)", "range(1,372)"),
    ("self.assertEqual(188,len(cards))", "self.assertEqual(371,len(cards))"),
):
    if old not in text:
        fail(f"B5 release assertion missing: {old}")
    text = text.replace(old, new)
b5_test.write_text(text, encoding="utf-8")

old_release_test = REPO / "tooling" / "question_bank" / "tests" / "test_drone_release_activation_188.py"
if not old_release_test.is_file():
    fail("historical 188 release regression file missing")
old_release_test.unlink()
new_release_test = REPO / "tooling" / "question_bank" / "tests" / "test_drone_release_activation_371.py"
new_release_test.write_text(
    '''from __future__ import annotations\nimport csv,json,sys,unittest\nfrom pathlib import Path\nROOT=Path(__file__).resolve().parents[3]\nBANK=ROOT/"question_banks/drone_second_class"\nA=BANK/"authoring"\nsys.path.insert(0,str(ROOT/"tooling/question_bank"))\nfrom expansion import validate_expansion_batch\nfrom validation import validate_bank\nCURRENT_REV="drone-second-class-v4-release-2026-08-25"\nMID_REV="drone-second-class-v2-release-2026-08-24"\nOLD_REV="drone-second-class-v1-release-2026-08-20"\nclass Release371Test(unittest.TestCase):\n def test_release_is_exact_and_generated(self):\n  meta=json.loads((A/"bank.json").read_text(encoding="utf-8")); self.assertEqual(CURRENT_REV,meta["bank_revision"]); self.assertEqual("2026-08-25",meta["content_as_of"])\n  with (A/"questions.csv").open(encoding="utf-8",newline="") as h: q={r["question_id"]:r for r in csv.DictReader(h)}\n  ids=[f"DRONE-Q-{n:06d}" for n in range(1,372)]; self.assertEqual(set(ids),set(q)); self.assertTrue(all(q[i]["status"]=="active" for i in ids)); self.assertTrue(all(q[i]["last_reviewed_at"]=="2026-08-25" for i in ids[188:])); self.assertEqual(30,sum(q[i]["is_free"]=="true" for i in ids)); self.assertTrue(all(q[i]["is_free"]=="false" for i in ids[188:]))\n  with (A/"question_id_registry.csv").open(encoding="utf-8",newline="") as h: reg={r["question_id"]:r for r in csv.DictReader(h)}\n  self.assertTrue(all(reg[i]["first_used_bank_revision"]==OLD_REV for i in ids[:100])); self.assertTrue(all(reg[i]["first_used_bank_revision"]==MID_REV for i in ids[100:188])); self.assertTrue(all(reg[i]["first_used_bank_revision"]==CURRENT_REV for i in ids[188:])); self.assertFalse(any(int(qid.rsplit("-",1)[1])>371 for qid in reg if qid.startswith("DRONE-Q-")))\n  released=json.loads((A/"released_questions.json").read_text(encoding="utf-8"))["released_questions"]; self.assertEqual(ids,[r["question_id"] for r in released])\n  runtime_path=BANK/"generated/drone_second_class_bank.json"; app=ROOT/"apps/drone_second_class/assets/question_bank/drone_second_class_bank.json"; self.assertEqual(runtime_path.read_bytes(),app.read_bytes())\n  runtime=json.loads(runtime_path.read_text(encoding="utf-8")); cards=[c for d in runtime["decks"] for u in d["units"] for c in u["cards"]]; self.assertEqual(set(ids),{c["stableId"] for c in cards}); self.assertEqual(30,sum(not c["isPremium"] for c in cards))\n  manifest=json.loads((BANK/"generated/bank_manifest.json").read_text(encoding="utf-8")); self.assertEqual(371,manifest["question_count"]); self.assertEqual(30,manifest["free_question_count"]); self.assertEqual(CURRENT_REV,manifest["bank_revision"])\n  result=validate_bank(BANK,check_generated=True); self.assertTrue(result.is_valid,[str(i) for i in result.issues])\n  for n in range(1,19): self.assertEqual([],validate_expansion_batch(A/"batches"/f"batch_{n:03d}"))\n def test_exact_183_new_candidates_released(self):\n  mapped=[]\n  for n in range(5,19):\n   with (A/"batches"/f"batch_{n:03d}"/"candidates.csv").open(encoding="utf-8",newline="") as h: rows=list(csv.DictReader(h))\n   mapped += [r for r in rows if r["permanent_question_id"]]\n  selected=[r for r in mapped if 189<=int(r["permanent_question_id"].rsplit("-",1)[1])<=371]\n  self.assertEqual(183,len(selected)); self.assertEqual({f"DRONE-Q-{n:06d}" for n in range(189,372)},{r["permanent_question_id"] for r in selected}); self.assertTrue(all(r["state"]=="RELEASED" for r in selected))\nif __name__=="__main__": unittest.main()\n''',
    encoding="utf-8",
)

# Post-release invariants before advancing machine state.
_, questions_after = read_csv(questions_path)
q_after = {row["question_id"]: row for row in questions_after}
for qid in HISTORICAL_IDS:
    if q_after[qid] != historical_questions_before[qid]:
        fail(f"historical canonical row changed: {qid}")
for qid in SELECTED_IDS:
    before = selected_questions_before[qid]
    after = q_after[qid]
    for field in q_fields:
        expected = "active" if field == "status" else RELEASE_DATE if field == "last_reviewed_at" else before[field]
        if after[field] != expected:
            fail(f"unexpected selected canonical mutation {qid}:{field}")
if {qid for qid in ALL_IDS if q_after[qid]["is_free"] == "true"} != free_ids_before:
    fail("canonical free-ID set changed")

_, registry_after = read_csv(registry_path)
reg_after = {row["question_id"]: row for row in registry_after}
for qid in HISTORICAL_IDS:
    if reg_after[qid] != historical_registry_before[qid]:
        fail(f"historical registry row changed: {qid}")
for qid in SELECTED_IDS:
    before = selected_registry_before[qid]
    after = reg_after[qid]
    for field in r_fields:
        expected = RELEASE_ID if field == "first_used_bank_revision" else before[field]
        if after[field] != expected:
            fail(f"unexpected selected registry mutation {qid}:{field}")

released_post = json.loads(released_path.read_text(encoding="utf-8"))["released_questions"]
if released_post[:188] != released_before or [r["question_id"] for r in released_post] != list(ALL_IDS):
    fail("post-release snapshot identity drift")

for batch, (fields, before_rows) in batch_snapshots.items():
    after_fields, after_rows = read_csv(batch / "candidates.csv")
    if after_fields != fields or len(after_rows) != len(before_rows):
        fail(f"candidate ledger shape changed: {batch.name}")
    before_by_id = {r["candidate_id"]: r for r in before_rows}
    for after in after_rows:
        before = before_by_id[after["candidate_id"]]
        selected = after["permanent_question_id"] in SELECTED_SET
        for field in fields:
            expected = "RELEASED" if selected and field == "state" else before[field]
            if after[field] != expected:
                fail(f"unexpected candidate mutation {batch.name}/{after['candidate_id']}:{field}")
    errors = validate_expansion_batch(batch)
    if errors:
        fail(f"post-activation batch validation failed {batch.name}: {' | '.join(errors)}")

post_validation = validate_bank(BANK, check_generated=True)
if not post_validation.is_valid:
    fail("post-activation generated validation failed: " + " | ".join(str(i) for i in post_validation.errors))
manifest_after = json.loads(manifest_path.read_text(encoding="utf-8"))
if (
    manifest_after.get("bank_revision") != RELEASE_ID
    or manifest_after.get("content_as_of") != RELEASE_DATE
    or manifest_after.get("question_count") != 371
    or manifest_after.get("free_question_count") != 30
):
    fail("post-activation manifest drift")
if app_asset_path.read_bytes() != generated_path.read_bytes():
    fail("post-activation generated/app asset mismatch")
runtime_after = json.loads(generated_path.read_text(encoding="utf-8"))
cards_after = runtime_cards(runtime_after)
if len(cards_after) != 371 or {c["stableId"] for c in cards_after} != ALL_SET:
    fail("post-activation runtime inventory drift")
if {c["stableId"] for c in cards_after if not c["isPremium"]} != free_ids_before:
    fail("runtime free-ID set changed")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "origin/main"], text=True).strip()
state["current_phase"] = "FEATURE_COMPLETION"
state["state_epoch"] = 133
state["next_atomic_objective"] = "VERIFY_FEATURE_COMPLETION_EXIT_CRITERIA"
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
