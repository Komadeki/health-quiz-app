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

BANK = REPO / "question_banks" / "otsu4"
AUTHORING = BANK / "authoring"
BATCH = AUTHORING / "batches" / "batch_003"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "otsu4_state.json"
ALL = tuple(f"O4-B3-LAW-C{i:03d}" for i in range(1, 25))
REJECTED = ("O4-B3-LAW-C016", "O4-B3-LAW-C017")
ACCEPTED = tuple(cid for cid in ALL if cid not in REJECTED)
EXPECTED = {cid: f"OTSU4-Q-{n:06d}" for cid, n in zip(ACCEPTED, range(30, 52))}

state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
if state.get("state_epoch") != 40 or state.get("next_atomic_objective") != "VERIFY_OTSU4_BATCH_3_CANONICAL_SOURCES_22":
    raise SystemExit(f"unexpected state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}")

candidate_path = BATCH / "candidates.csv"
with candidate_path.open(encoding="utf-8", newline="") as h:
    reader = csv.DictReader(h)
    fields = list(reader.fieldnames or [])
    rows = list(reader)
by_candidate = {r["candidate_id"]: r for r in rows}
if set(by_candidate) != set(ALL):
    raise SystemExit("unexpected Otsu4 Batch 3 candidate set")
for cid, qid in EXPECTED.items():
    row = by_candidate[cid]
    if row["state"] != "INTEGRATED" or row["permanent_question_id"] != qid:
        raise SystemExit(f"unexpected integrated state: {cid}")
if any(by_candidate[c]["state"] != "AI_PRE_ACCEPT" or by_candidate[c]["permanent_question_id"] for c in REJECTED):
    raise SystemExit("rejected Otsu4 Batch 3 candidate mutated")

with (AUTHORING / "questions.csv").open(encoding="utf-8", newline="") as h:
    questions = {r["question_id"]: r for r in csv.DictReader(h)}
if len(questions) != 51:
    raise SystemExit(f"unexpected Otsu4 canonical inventory: {len(questions)}")
sources_doc = json.loads((AUTHORING / "sources.json").read_text(encoding="utf-8"))
sources = {str(s.get("source_id", "")): s for s in sources_doc.get("sources", []) if isinstance(s, dict)}

verification_path = AUTHORING / "source_verifications.json"
verification_doc = json.loads(verification_path.read_text(encoding="utf-8"))
verifications = list(verification_doc.get("verifications", []))
if len(verifications) != 29:
    raise SystemExit(f"unexpected Otsu4 verification baseline: {len(verifications)}")
verified_ids = {str(r.get("question_id", "")) for r in verifications}
if any(qid in verified_ids for qid in EXPECTED.values()):
    raise SystemExit("partial Otsu4 Batch 3 source verification detected")

for cid, qid in EXPECTED.items():
    candidate = by_candidate[cid]
    question = questions.get(qid)
    if question is None:
        raise SystemExit(f"missing canonical question: {qid}")
    for candidate_field, canonical_field in (
        ("question", "question"), ("choice1", "choice1"), ("choice2", "choice2"),
        ("choice3", "choice3"), ("choice4", "choice4"), ("proposed_correct", "correct_choice"),
        ("explanation", "explanation"), ("source_id", "source_id"),
        ("source_locator", "source_locator"), ("unit_id", "unit_id"),
    ):
        if candidate[candidate_field] != question.get(canonical_field, ""):
            raise SystemExit(f"canonical content mismatch {cid}: {candidate_field}")
    source = sources.get(candidate["source_id"])
    if source is None:
        raise SystemExit(f"unregistered source for {cid}: {candidate['source_id']}")
    source_version = str(source.get("source_version", "")).strip()
    if candidate["source_version"] != source_version:
        raise SystemExit(f"source version drift for {cid}")
    verifications.append({
        "question_id": qid,
        "source_id": candidate["source_id"],
        "source_version": source_version,
        "verification_state": "author_source_verified",
        "verified_at": "2026-08-25",
    })
    candidate["state"] = "VERIFIED"

with candidate_path.open("w", encoding="utf-8", newline="") as h:
    writer = csv.DictWriter(h, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
verification_doc["verifications"] = verifications
verification_path.write_text(json.dumps(verification_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

if len(verifications) != 51 or len({r["question_id"] for r in verifications}) != 51:
    raise SystemExit("Otsu4 source verification inventory mismatch")
with candidate_path.open(encoding="utf-8", newline="") as h:
    after = {r["candidate_id"]: r for r in csv.DictReader(h)}
if any(after[c]["state"] != "VERIFIED" or after[c]["permanent_question_id"] != EXPECTED[c] for c in ACCEPTED):
    raise SystemExit("Otsu4 Batch 3 verified state mismatch")
if any(after[c]["state"] != "AI_PRE_ACCEPT" or after[c]["permanent_question_id"] for c in REJECTED):
    raise SystemExit("rejected Otsu4 Batch 3 candidate changed during verification")
released = json.loads((AUTHORING / "released_questions.json").read_text(encoding="utf-8"))["released_questions"]
if released:
    raise SystemExit("Otsu4 released baseline changed")
meta = json.loads((AUTHORING / "bank.json").read_text(encoding="utf-8"))
runtime = json.loads((BANK / meta["runtime_output"]).read_text(encoding="utf-8"))
runtime_count = sum(len(u.get("cards", [])) for d in runtime.get("decks", []) for u in d.get("units", []))
if runtime_count != 0:
    raise SystemExit("Otsu4 runtime baseline changed")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "origin/main"], text=True).strip()
state["state_epoch"] = 41
state["next_atomic_objective"] = "PLAN_OTSU4_BATCH_4_600Q_COVERAGE_BATCH"
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
errors = validate_expansion_batch(BATCH)
if errors:
    raise SystemExit("Otsu4 Batch 3 expansion validation failed: " + " | ".join(errors))
