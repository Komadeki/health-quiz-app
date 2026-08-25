#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tooling" / "question_bank"))
from expansion import validate_expansion_batch

BANK = REPO / "question_banks" / "otsu4"
AUTHORING = BANK / "authoring"
BATCHES = AUTHORING / "batches"
WAVES = AUTHORING / "waves"
REQUEST_PATH = WAVES / "source_verification_request.json"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "otsu4_state.json"
WAVE_ID_PATTERN = re.compile(r"^W([1-9][0-9]*)$")


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise SystemExit(f"expected object: {path}")
    return value


def read_csv_with_fields(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), list(reader)


def find_batch_dir(batch_id: str) -> Path:
    matches = []
    for child in BATCHES.iterdir():
        if child.is_dir() and (child / "batch.json").is_file():
            if str(read_json(child / "batch.json").get("batch_id", "")).strip() == batch_id:
                matches.append(child)
    if len(matches) != 1:
        raise SystemExit(f"expected exactly one directory for {batch_id}, found {len(matches)}")
    return matches[0]


request = read_json(REQUEST_PATH)
if request.get("schema_version") != "1.0":
    raise SystemExit("unsupported source verification request schema")
wave_id = str(request.get("wave_id", "")).strip()
match = WAVE_ID_PATTERN.fullmatch(wave_id)
if not match:
    raise SystemExit(f"invalid wave_id: {wave_id!r}")
wave_number = int(match.group(1))
wave_path = WAVES / f"wave_{wave_number:03d}.json"
wave = read_json(wave_path)
if wave.get("wave_id") != wave_id or wave.get("status") != "INTEGRATED":
    raise SystemExit("wave is not ready for source verification")

state = read_json(STATE_PATH)
expected_epoch = request.get("expected_state_epoch")
expected_objective = str(request.get("expected_objective", "")).strip()
if state.get("state_epoch") != expected_epoch or state.get("next_atomic_objective") != expected_objective:
    raise SystemExit(f"unexpected state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}")
expected_count = request.get("expected_integrated_count")
if not isinstance(expected_count, int) or expected_count <= 0:
    raise SystemExit("expected_integrated_count must be a positive integer")
verified_at = str(request.get("verified_at", "")).strip()
if not verified_at:
    raise SystemExit("verified_at is required")

adjudication = read_json(WAVES / f"wave_{wave_number:03d}_director_adjudication_r1.json")
accepted_ids = tuple(str(v) for v in adjudication.get("accepted_candidate_ids", []))
if len(accepted_ids) != expected_count or len(set(accepted_ids)) != len(accepted_ids):
    raise SystemExit("Director accepted set drift")
accepted_set = set(accepted_ids)

questions = {r["question_id"]: r for r in read_csv_with_fields(AUTHORING / "questions.csv")[1]}
sources_doc = read_json(AUTHORING / "sources.json")
sources = {str(s.get("source_id", "")).strip(): s for s in sources_doc.get("sources", []) if isinstance(s, dict) and str(s.get("source_id", "")).strip()}
verification_path = AUTHORING / "source_verifications.json"
verification_doc = read_json(verification_path)
verifications = list(verification_doc.get("verifications", []))
baseline = wave.get("canonical_verified_baseline")
if not isinstance(baseline, int) or len(verifications) != baseline:
    raise SystemExit("source verification baseline drift")
verified_ids = {str(r.get("question_id", "")).strip() for r in verifications}

batch_ids = [str(item.get("batch_id", "")).strip() for item in wave.get("batches", []) if isinstance(item, dict)]
if not batch_ids:
    raise SystemExit("wave batch set missing")
seen_accepted: set[str] = set()

for batch_id in batch_ids:
    batch_dir = find_batch_dir(batch_id)
    candidate_path = batch_dir / "candidates.csv"
    fields, rows = read_csv_with_fields(candidate_path)
    by_id = {r["candidate_id"]: r for r in rows}
    batch_accepted = [cid for cid in by_id if cid in accepted_set]
    batch_nonaccepted = [cid for cid in by_id if cid not in accepted_set]
    for cid in batch_accepted:
        candidate = by_id[cid]
        qid = candidate["permanent_question_id"]
        if candidate["state"] != "INTEGRATED" or not qid:
            raise SystemExit(f"{cid}: integrated state drift")
        if qid in verified_ids:
            raise SystemExit(f"{cid}: partial source verification detected")
        question = questions.get(qid)
        if question is None:
            raise SystemExit(f"{cid}: missing canonical question {qid}")
        for candidate_field, canonical_field in (
            ("question", "question"), ("choice1", "choice1"), ("choice2", "choice2"),
            ("choice3", "choice3"), ("choice4", "choice4"), ("proposed_correct", "correct_choice"),
            ("explanation", "explanation"), ("source_id", "source_id"),
            ("source_locator", "source_locator"), ("unit_id", "unit_id"),
        ):
            if candidate[candidate_field] != question.get(canonical_field, ""):
                raise SystemExit(f"{cid}: canonical content mismatch {candidate_field}")
        source = sources.get(candidate["source_id"])
        if source is None:
            raise SystemExit(f"{cid}: unregistered source {candidate['source_id']}")
        source_version = str(source.get("source_version", "")).strip()
        if candidate["source_version"] != source_version:
            raise SystemExit(f"{cid}: source version drift")
        verifications.append({
            "question_id": qid,
            "source_id": candidate["source_id"],
            "source_version": source_version,
            "verification_state": "author_source_verified",
            "verified_at": verified_at,
        })
        candidate["state"] = "VERIFIED"
        seen_accepted.add(cid)
        verified_ids.add(qid)
    if any(by_id[c]["state"] != "AI_PRE_ACCEPT" or by_id[c]["permanent_question_id"] for c in batch_nonaccepted):
        raise SystemExit(f"{batch_id}: nonaccepted candidate state drift")
    with candidate_path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    errors = validate_expansion_batch(batch_dir)
    if errors:
        raise SystemExit(f"{batch_id}: expansion validation failed: " + " | ".join(errors))

if seen_accepted != accepted_set:
    raise SystemExit("wave accepted verification set drift")
verification_doc["verifications"] = verifications
verification_path.write_text(json.dumps(verification_doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
if len(verifications) != baseline + expected_count or len({str(r.get('question_id', '')) for r in verifications}) != baseline + expected_count:
    raise SystemExit("source verification final inventory mismatch")

released = read_json(AUTHORING / "released_questions.json").get("released_questions", [])
meta = read_json(AUTHORING / "bank.json")
runtime = read_json(BANK / str(meta.get("runtime_output", "")))
runtime_count = sum(len(u.get("cards", [])) for d in runtime.get("decks", []) for u in d.get("units", []))
if released or runtime_count != 0:
    raise SystemExit("source verification crossed release/runtime boundary")

wave["status"] = "SOURCE_VERIFIED"
wave["source_verification_state_epoch"] = int(expected_epoch) + 1
wave["verified_candidate_count"] = expected_count
wave["canonical_verified_count_after_wave"] = baseline + expected_count
wave["next_gate"] = f"PLAN_WAVE_{wave_number + 1}_600Q_COVERAGE"
wave_path.write_text(json.dumps(wave, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "origin/main"], text=True).strip()
state["state_epoch"] = int(expected_epoch) + 1
state["next_atomic_objective"] = f"PLAN_OTSU4_WAVE_{wave_number + 1}_600Q_COVERAGE"
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
