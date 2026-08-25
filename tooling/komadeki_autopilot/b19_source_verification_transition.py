#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tooling" / "question_bank"))
from expansion import validate_expansion_batch

BANK = REPO / "question_banks" / "drone_second_class"
AUTHORING = BANK / "authoring"
BATCH = AUTHORING / "batches" / "batch_019"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "drone_state.json"
ACCEPTED = tuple(f"B19-RULE-C{i:03d}" for i in range(1, 16))
MAPPING = {cid: f"DRONE-Q-{n:06d}" for cid, n in zip(ACCEPTED, range(372, 387))}

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 140 or state.get("next_atomic_objective") != "VERIFY_B19_CANONICAL_SOURCES_15":
    raise SystemExit(f"unexpected state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}")

policy = json.loads((AUTHORING / "owner_dynamic_release_inclusion_2026-08-26.json").read_text(encoding="utf-8"))
release_policy = policy.get("release_policy", {})
current_facts = policy.get("current_facts", {})
if (
    policy.get("status") != "ACTIVE"
    or release_policy.get("fixed_release_question_count") is not None
    or release_policy.get("release_progression_blocked_by_400_target") is not False
    or "B19" not in release_policy.get("in_flight_batch_rule", "")
    or current_facts.get("b20_before_current_release") != "PROHIBITED"
    or policy.get("handoff_after_b19") != "FREEZE_CURRENT_SOURCE_VERIFIED_SET_FOR_RELEASE_ACTIVATION"
):
    raise SystemExit("dynamic release policy drift")


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as handle:
    reader = csv.DictReader(handle)
    fields = list(reader.fieldnames or [])
    rows = list(reader)
by_id = {row["candidate_id"]: row for row in rows}
if set(by_id) != set(ACCEPTED):
    raise SystemExit("unexpected B19 candidate set")
for cid, qid in MAPPING.items():
    row = by_id[cid]
    if row["state"] != "INTEGRATED" or row["permanent_question_id"] != qid:
        raise SystemExit(f"integration binding mismatch: {cid}")
    if row["source_id"] != "MLIT-UAS-SAFETY-GUIDE-5" or row["source_version"] != "5":
        raise SystemExit(f"source contract mismatch: {cid}")
    if not row["source_locator"].startswith("教則 第3章") or "〔一等〕" in row["source_locator"]:
        raise SystemExit(f"source locator/scope mismatch: {cid}")

questions = {row["question_id"]: row for row in read_csv(AUTHORING / "questions.csv")}
if len(questions) != 386:
    raise SystemExit(f"canonical inventory expected 386, got {len(questions)}")
for cid, qid in MAPPING.items():
    question = questions[qid]
    candidate = by_id[cid]
    if question["status"] != "draft" or question["unit_id"] != "drone_rules":
        raise SystemExit(f"canonical draft mismatch: {qid}")
    for qfield, cfield in (
        ("question", "question"),
        ("choice1", "choice1"),
        ("choice2", "choice2"),
        ("choice3", "choice3"),
        ("choice4", "choice4"),
        ("correct_choice", "proposed_correct"),
        ("explanation", "explanation"),
        ("source_id", "source_id"),
        ("source_locator", "source_locator"),
    ):
        if question[qfield] != candidate[cfield]:
            raise SystemExit(f"canonical binding mismatch: {qid}:{qfield}")

sources = json.loads((AUTHORING / "sources.json").read_text(encoding="utf-8"))["sources"]
source = next(item for item in sources if item["source_id"] == "MLIT-UAS-SAFETY-GUIDE-5")
if str(source["source_version"]) != "5" or source.get("edition") != "第5版":
    raise SystemExit("unexpected current source contract")

verification_path = AUTHORING / "source_verifications.json"
verification_doc = json.loads(verification_path.read_text(encoding="utf-8"))
existing = {row["question_id"] for row in verification_doc["verifications"]}
if any(qid in existing for qid in MAPPING.values()):
    raise SystemExit("partial/duplicate B19 source verification detected")
verification_doc["verifications"].extend(
    {
        "question_id": qid,
        "source_id": "MLIT-UAS-SAFETY-GUIDE-5",
        "source_version": "5",
        "verification_state": "author_source_verified",
        "verified_at": "2026-08-26",
    }
    for qid in MAPPING.values()
)
verification_doc["verifications"].sort(key=lambda row: row["question_id"])
verification_path.write_text(json.dumps(verification_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

for cid in ACCEPTED:
    by_id[cid]["state"] = "VERIFIED"
with (BATCH / "candidates.csv").open("w", encoding="utf-8", newline="") as handle:
    writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)

released = json.loads((AUTHORING / "released_questions.json").read_text(encoding="utf-8"))["released_questions"]
if len(released) != 188:
    raise SystemExit("released baseline changed")
meta = json.loads((AUTHORING / "bank.json").read_text(encoding="utf-8"))
runtime = json.loads((BANK / meta["runtime_output"]).read_text(encoding="utf-8"))
if sum(len(unit.get("cards", [])) for deck in runtime.get("decks", []) for unit in deck.get("units", [])) != 188:
    raise SystemExit("runtime baseline changed")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "origin/main"], text=True).strip()
state["state_epoch"] = 141
state["next_atomic_objective"] = "FREEZE_CURRENT_SOURCE_VERIFIED_SET_FOR_RELEASE_ACTIVATION"
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

errors = validate_expansion_batch(BATCH)
if errors:
    raise SystemExit("B19 expansion validation failed: " + " | ".join(errors))
