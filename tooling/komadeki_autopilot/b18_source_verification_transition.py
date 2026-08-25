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
BATCH = AUTHORING / "batches" / "batch_018"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "drone_state.json"
ACCEPTED = tuple(f"B18-RULE-C{i:03d}" for i in range(1, 7))
MAPPING = {cid: f"DRONE-Q-{n:06d}" for cid, n in zip(ACCEPTED, range(366, 372))}

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("next_atomic_objective") != "VERIFY_B18_CANONICAL_SOURCES_6" or state.get("state_epoch") != 130:
    raise SystemExit(f"unexpected state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}")
release_cut = json.loads((AUTHORING / "owner_release_cut_371_2026-08-25.json").read_text(encoding="utf-8"))
if release_cut.get("status") != "ACTIVE" or release_cut.get("release_cut", {}).get("final_source_verified_canonical_after_b18") != 371:
    raise SystemExit("371 release-cut contract drift")


def read_csv(path: Path):
    with path.open(encoding="utf-8", newline="") as h:
        return list(csv.DictReader(h))

with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as h:
    reader = csv.DictReader(h)
    fields = list(reader.fieldnames or [])
    rows = list(reader)
by_id = {r["candidate_id"]: r for r in rows}
if set(by_id) != set(ACCEPTED):
    raise SystemExit("unexpected B18 candidate set")
for cid, qid in MAPPING.items():
    r = by_id[cid]
    if r["state"] != "INTEGRATED" or r["permanent_question_id"] != qid:
        raise SystemExit(f"integration binding mismatch: {cid}")
    if r["source_id"] != "MLIT-UAS-SAFETY-GUIDE-5" or r["source_version"] != "5":
        raise SystemExit(f"source contract mismatch: {cid}")
    if not r["source_locator"].startswith("教則 第3章 3.1.2(3)") or "〔一等〕" in r["source_locator"]:
        raise SystemExit(f"source locator/scope mismatch: {cid}")

questions = {r["question_id"]: r for r in read_csv(AUTHORING / "questions.csv")}
if len(questions) != 371:
    raise SystemExit(f"canonical inventory expected 371, got {len(questions)}")
for cid, qid in MAPPING.items():
    q, c = questions[qid], by_id[cid]
    if q["status"] != "draft" or q["unit_id"] != "drone_rules":
        raise SystemExit(f"canonical draft mismatch: {qid}")
    for qfield, cfield in (("question","question"),("choice1","choice1"),("choice2","choice2"),("choice3","choice3"),("choice4","choice4"),("correct_choice","proposed_correct"),("explanation","explanation"),("source_id","source_id"),("source_locator","source_locator")):
        if q[qfield] != c[cfield]:
            raise SystemExit(f"canonical binding mismatch: {qid}:{qfield}")

sources = json.loads((AUTHORING / "sources.json").read_text(encoding="utf-8"))["sources"]
source = next(s for s in sources if s["source_id"] == "MLIT-UAS-SAFETY-GUIDE-5")
if str(source["source_version"]) != "5" or source.get("edition") != "第5版":
    raise SystemExit("unexpected current source contract")

verification_path = AUTHORING / "source_verifications.json"
verification_doc = json.loads(verification_path.read_text(encoding="utf-8"))
existing = {r["question_id"] for r in verification_doc["verifications"]}
if any(qid in existing for qid in MAPPING.values()):
    raise SystemExit("partial/duplicate B18 source verification detected")
verification_doc["verifications"].extend({
    "question_id": qid,
    "source_id": "MLIT-UAS-SAFETY-GUIDE-5",
    "source_version": "5",
    "verification_state": "author_source_verified",
    "verified_at": "2026-08-25"
} for qid in MAPPING.values())
verification_doc["verifications"].sort(key=lambda r: r["question_id"])
verification_path.write_text(json.dumps(verification_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

for cid in ACCEPTED:
    by_id[cid]["state"] = "VERIFIED"
with (BATCH / "candidates.csv").open("w", encoding="utf-8", newline="") as h:
    writer = csv.DictWriter(h, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)

released = json.loads((AUTHORING / "released_questions.json").read_text(encoding="utf-8"))["released_questions"]
if len(released) != 188:
    raise SystemExit("released baseline changed")
meta = json.loads((AUTHORING / "bank.json").read_text(encoding="utf-8"))
runtime = json.loads((BANK / meta["runtime_output"]).read_text(encoding="utf-8"))
if sum(len(u.get("cards", [])) for d in runtime.get("decks", []) for u in d.get("units", [])) != 188:
    raise SystemExit("runtime baseline changed")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "origin/main"], text=True).strip()
state["next_atomic_objective"] = "PREPARE_PRODUCTION_BANK_371_RELEASE_ACTIVATION"
state["state_epoch"] = 131
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
errors = validate_expansion_batch(BATCH)
if errors:
    raise SystemExit("B18 expansion validation failed: " + " | ".join(errors))
