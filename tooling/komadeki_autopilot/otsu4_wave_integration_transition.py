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
from transaction import QuestionExpansionTransaction

BANK = REPO / "question_banks" / "otsu4"
AUTHORING = BANK / "authoring"
BATCHES = AUTHORING / "batches"
WAVES = AUTHORING / "waves"
REQUEST_PATH = WAVES / "integration_request.json"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "otsu4_state.json"
WAVE_ID_PATTERN = re.compile(r"^W([1-9][0-9]*)$")


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise SystemExit(f"expected object: {path}")
    return value


def read_csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def find_batch_dir(batch_id: str) -> Path:
    matches = []
    for child in BATCHES.iterdir():
        if child.is_dir() and (child / "batch.json").is_file():
            if str(read_json(child / "batch.json").get("batch_id", "")).strip() == batch_id:
                matches.append(child)
    if len(matches) != 1:
        raise SystemExit(f"expected exactly one directory for {batch_id}, found {len(matches)}")
    return matches[0]


def canonical_row(candidate: dict[str, str], question_id: str) -> dict[str, str]:
    unit_id = candidate["unit_id"]
    if unit_id not in {"otsu4_law", "otsu4_physics", "otsu4_fire"}:
        raise SystemExit(f"unsupported Otsu4 unit_id: {unit_id}")
    return {
        "question_id": question_id,
        "question_version": "1",
        "status": "draft",
        "deck_id": unit_id,
        "unit_id": unit_id,
        "question": candidate["question"],
        "choice1": candidate["choice1"],
        "choice2": candidate["choice2"],
        "choice3": candidate["choice3"],
        "choice4": candidate["choice4"],
        "choice5": "",
        "correct_choice": candidate["proposed_correct"],
        "explanation": candidate["explanation"],
        "source_id": candidate["source_id"],
        "source_locator": candidate["source_locator"],
        "difficulty": "2",
        "importance": "3",
        "is_free": "false",
        "valid_from": "",
        "valid_until": "",
        "last_reviewed_at": "",
        "supersedes_id": "",
        "tags": "",
        "notes_internal": "",
    }


request = read_json(REQUEST_PATH)
if request.get("schema_version") != "1.0":
    raise SystemExit("unsupported integration request schema")
wave_id = str(request.get("wave_id", "")).strip()
match = WAVE_ID_PATTERN.fullmatch(wave_id)
if not match:
    raise SystemExit(f"invalid wave_id: {wave_id!r}")
wave_number = int(match.group(1))
wave_path = WAVES / f"wave_{wave_number:03d}.json"
wave = read_json(wave_path)
if wave.get("wave_id") != wave_id or wave.get("status") != "DIRECTOR_ACCEPTED_AND_PROMOTED":
    raise SystemExit("wave is not ready for integration")

state = read_json(STATE_PATH)
expected_epoch = request.get("expected_state_epoch")
expected_objective = str(request.get("expected_objective", "")).strip()
if state.get("state_epoch") != expected_epoch or state.get("next_atomic_objective") != expected_objective:
    raise SystemExit(f"unexpected state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}")
expected_accept_count = request.get("expected_accept_count")
if not isinstance(expected_accept_count, int) or expected_accept_count <= 0:
    raise SystemExit("expected_accept_count must be a positive integer")

adjudication_path = WAVES / f"wave_{wave_number:03d}_director_adjudication_r1.json"
adjudication = read_json(adjudication_path)
accepted_all = tuple(str(v) for v in adjudication.get("accepted_candidate_ids", []))
if len(accepted_all) != expected_accept_count or len(set(accepted_all)) != len(accepted_all):
    raise SystemExit("Director accepted set drift")
accepted_set = set(accepted_all)

baseline = wave.get("canonical_verified_baseline")
if not isinstance(baseline, int):
    raise SystemExit("wave canonical baseline missing")
questions_before = read_csv_rows(AUTHORING / "questions.csv")
registry_before = read_csv_rows(AUTHORING / "question_id_registry.csv")
verifications_before = read_json(AUTHORING / "source_verifications.json").get("verifications", [])
released_before = read_json(AUTHORING / "released_questions.json").get("released_questions", [])
meta = read_json(AUTHORING / "bank.json")
runtime_path = BANK / str(meta.get("runtime_output", ""))
runtime_before = runtime_path.read_bytes()
if len(questions_before) != baseline or len(registry_before) != baseline or len(verifications_before) != baseline:
    raise SystemExit("canonical/registry/source-verification baseline drift")

batch_ids = [str(item.get("batch_id", "")).strip() for item in wave.get("batches", []) if isinstance(item, dict)]
if not batch_ids:
    raise SystemExit("wave batch set missing")

mapping: dict[str, str] = {}
nonaccepted_seen: set[str] = set()
for batch_id in batch_ids:
    batch_dir = find_batch_dir(batch_id)
    rows = read_csv_rows(batch_dir / "candidates.csv")
    row_by_id = {r["candidate_id"]: r for r in rows}
    batch_accepted = tuple(r["candidate_id"] for r in rows if r["candidate_id"] in accepted_set)
    batch_nonaccepted = tuple(r["candidate_id"] for r in rows if r["candidate_id"] not in accepted_set)
    if not batch_accepted:
        raise SystemExit(f"{batch_id}: no accepted candidates")
    if any(row_by_id[c]["state"] != "READY_FOR_ID" or row_by_id[c]["permanent_question_id"] for c in batch_accepted):
        raise SystemExit(f"{batch_id}: accepted candidate pre-ID state drift")
    if any(row_by_id[c]["state"] != "AI_PRE_ACCEPT" or row_by_id[c]["permanent_question_id"] for c in batch_nonaccepted):
        raise SystemExit(f"{batch_id}: nonaccepted candidate state drift")
    packet_ids = {p.stem for p in (batch_dir / "acceptance_packets").glob("*.json")}
    if packet_ids != set(batch_accepted):
        raise SystemExit(f"{batch_id}: acceptance packet set drift")
    transaction = QuestionExpansionTransaction(BANK, batch_dir, batch_accepted, question_factory=canonical_row)
    plan = transaction.plan()
    applied = transaction.apply()
    if applied != plan.mapping:
        raise SystemExit(f"{batch_id}: integration mapping drift")
    mapping.update(applied)
    nonaccepted_seen.update(batch_nonaccepted)
    errors = validate_expansion_batch(batch_dir)
    if errors:
        raise SystemExit(f"{batch_id}: expansion validation failed: " + " | ".join(errors))

if set(mapping) != accepted_set or len(mapping) != expected_accept_count:
    raise SystemExit("wave integrated candidate set drift")

questions_after = read_csv_rows(AUTHORING / "questions.csv")
registry_after = read_csv_rows(AUTHORING / "question_id_registry.csv")
if len(questions_after) != baseline + expected_accept_count or len(registry_after) != baseline + expected_accept_count:
    raise SystemExit("canonical/registry final inventory mismatch")
qids = [mapping[c] for c in accepted_all]
expected_qids = [f"OTSU4-Q-{n:06d}" for n in range(baseline + 1, baseline + expected_accept_count + 1)]
if qids != expected_qids:
    raise SystemExit(f"unexpected Permanent ID allocation: {qids[:3]} ... {qids[-3:]}")

verifications_after = read_json(AUTHORING / "source_verifications.json").get("verifications", [])
released_after = read_json(AUTHORING / "released_questions.json").get("released_questions", [])
if verifications_after != verifications_before or released_after != released_before or runtime_path.read_bytes() != runtime_before:
    raise SystemExit("integration crossed source-verification/release/runtime boundary")

wave["status"] = "INTEGRATED"
wave["integration_state_epoch"] = int(expected_epoch) + 1
wave["integrated_candidate_count"] = expected_accept_count
wave["permanent_id_range"] = {"first": expected_qids[0], "last": expected_qids[-1]}
wave["next_gate"] = f"VERIFY_{wave_id}_CANONICAL_SOURCES_{expected_accept_count}"
wave_path.write_text(json.dumps(wave, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "origin/main"], text=True).strip()
state["state_epoch"] = int(expected_epoch) + 1
state["next_atomic_objective"] = f"VERIFY_OTSU4_WAVE_{wave_number}_CANONICAL_SOURCES_{expected_accept_count}"
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
