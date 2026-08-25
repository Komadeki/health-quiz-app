#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tooling" / "question_bank"))
from ai_governance import ai_acceptance_errors, candidate_fingerprint, promote_ai_governed_candidates
from expansion import validate_expansion_batch

BANK = REPO / "question_banks" / "otsu4"
AUTHORING = BANK / "authoring"
BATCHES = AUTHORING / "batches"
WAVES = AUTHORING / "waves"
REQUEST_PATH = WAVES / "acceptance_request.json"
STATE_PATH = REPO / "tooling" / "komadeki_autopilot" / "otsu4_state.json"
WAVE_ID_PATTERN = re.compile(r"^W([1-9][0-9]*)$")
ALLOWED_DECISIONS = {"ACCEPT", "REJECT", "REWORK", "HOLD"}


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise SystemExit(f"expected object: {path}")
    return value


def read_candidates(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), list(reader)


def find_batch_dir(batch_id: str) -> Path:
    matches: list[Path] = []
    for child in BATCHES.iterdir():
        if not child.is_dir() or not (child / "batch.json").is_file():
            continue
        if str(read_json(child / "batch.json").get("batch_id", "")).strip() == batch_id:
            matches.append(child)
    if len(matches) != 1:
        raise SystemExit(f"expected exactly one directory for {batch_id}, found {len(matches)}")
    return matches[0]


request = read_json(REQUEST_PATH)
if request.get("schema_version") != "1.0":
    raise SystemExit("unsupported acceptance request schema")
wave_id = str(request.get("wave_id", "")).strip()
match = WAVE_ID_PATTERN.fullmatch(wave_id)
if not match:
    raise SystemExit(f"invalid wave_id: {wave_id!r}")
wave_number = int(match.group(1))
wave_path = WAVES / f"wave_{wave_number:03d}.json"
wave = read_json(wave_path)
if wave.get("wave_id") != wave_id or wave.get("status") != "INDEPENDENT_AI_REVIEWED":
    raise SystemExit("wave is not in independently reviewed state")

state = read_json(STATE_PATH)
expected_epoch = request.get("expected_state_epoch")
expected_objective = str(request.get("expected_objective", "")).strip()
if state.get("state_epoch") != expected_epoch or state.get("next_atomic_objective") != expected_objective:
    raise SystemExit(
        f"unexpected state: {state.get('state_epoch')} / {state.get('next_atomic_objective')}"
    )
director_id = str(request.get("director_id", "")).strip()
if not director_id:
    raise SystemExit("director_id is required")
expected_accept_count = request.get("expected_accept_count")
if not isinstance(expected_accept_count, int) or expected_accept_count <= 0:
    raise SystemExit("expected_accept_count must be a positive integer")

wave_batches = wave.get("batches")
if not isinstance(wave_batches, list) or not wave_batches:
    raise SystemExit("wave batches missing")
batch_ids = [str(item.get("batch_id", "")).strip() for item in wave_batches if isinstance(item, dict)]
if len(batch_ids) != len(wave_batches) or len(set(batch_ids)) != len(batch_ids) or any(not value for value in batch_ids):
    raise SystemExit("invalid wave batch set")

review_summary = wave.get("review_summary")
if not isinstance(review_summary, dict):
    raise SystemExit("wave review_summary missing")
expected_review_counts = {
    "reviewed": int(review_summary.get("reviewed", -1)),
    "accept": int(review_summary.get("accept", -1)),
    "reject": int(review_summary.get("reject", -1)),
    "rework": int(review_summary.get("rework", -1)),
    "hold": int(review_summary.get("hold", -1)),
}
if expected_review_counts["accept"] != expected_accept_count:
    raise SystemExit("request accept count does not match wave review summary")

batch_contexts: list[dict] = []
all_actor_ids: set[str] = {director_id}
reviewer_ids: set[str] = set()
author_ids: set[str] = set()
actual_counts: Counter[str] = Counter()
all_candidate_ids: set[str] = set()
accepted_ids: list[str] = []
nonaccepted: list[dict] = []

for batch_id in batch_ids:
    batch_dir = find_batch_dir(batch_id)
    fields, candidates = read_candidates(batch_dir / "candidates.csv")
    if not candidates:
        raise SystemExit(f"{batch_id}: empty candidate set")
    rows = {row.get("candidate_id", ""): row for row in candidates}
    if "" in rows or len(rows) != len(candidates):
        raise SystemExit(f"{batch_id}: invalid or duplicate candidate ids")
    if all_candidate_ids.intersection(rows):
        raise SystemExit(f"{batch_id}: candidate id collision across wave")
    all_candidate_ids.update(rows)
    if any(row.get("state") != "AI_PRE_ACCEPT" or row.get("permanent_question_id") for row in candidates):
        raise SystemExit(f"{batch_id}: unexpected pre-transaction candidate state")

    packets_dir = batch_dir / "acceptance_packets"
    if packets_dir.exists() and list(packets_dir.glob("*.json")):
        raise SystemExit(f"{batch_id}: partial acceptance packet state detected")

    review = read_json(batch_dir / "independent_review_r1.json")
    if review.get("batch_id") != batch_id or review.get("wave_id") != wave_id:
        raise SystemExit(f"{batch_id}: review identity mismatch")
    if review.get("identity_separation") != "PASS":
        raise SystemExit(f"{batch_id}: review identity separation is not PASS")
    reviewer = review.get("reviewer") if isinstance(review.get("reviewer"), dict) else {}
    reviewer_id = str(reviewer.get("id", "")).strip()
    author_id = str(review.get("author_identity_checked", "")).strip()
    if reviewer.get("role") != "AI_REVIEWER" or not reviewer_id or not author_id:
        raise SystemExit(f"{batch_id}: incomplete AI review identities")
    if len({author_id, reviewer_id, director_id}) != 3:
        raise SystemExit(f"{batch_id}: author/reviewer/director identity collision")
    reviewer_ids.add(reviewer_id)
    author_ids.add(author_id)
    all_actor_ids.update({reviewer_id, author_id})

    decisions_raw = review.get("decisions")
    if not isinstance(decisions_raw, list):
        raise SystemExit(f"{batch_id}: review decisions missing")
    decisions = {str(item.get("candidate_id", "")).strip(): item for item in decisions_raw if isinstance(item, dict)}
    if set(decisions) != set(rows) or len(decisions) != len(decisions_raw):
        raise SystemExit(f"{batch_id}: review decision candidate set drift")

    batch_counts: Counter[str] = Counter()
    accepted_batch: list[str] = []
    for candidate_id, row in rows.items():
        decision = decisions[candidate_id]
        decision_name = str(decision.get("decision", "")).strip()
        rationale = str(decision.get("rationale", "")).strip()
        if decision_name not in ALLOWED_DECISIONS or not rationale:
            raise SystemExit(f"{candidate_id}: invalid independent review decision")
        batch_counts[decision_name.lower()] += 1
        actual_counts[decision_name.lower()] += 1
        actual_counts["reviewed"] += 1
        if decision_name == "ACCEPT":
            accepted_batch.append(candidate_id)
            accepted_ids.append(candidate_id)
        else:
            nonaccepted.append(
                {
                    "candidate_id": candidate_id,
                    "batch_id": batch_id,
                    "decision": decision_name,
                    "reason_code": str(decision.get("reason_code", "")).strip(),
                    "rationale": rationale,
                    "resume_condition": str(decision.get("resume_condition", "")).strip(),
                }
            )

    summary = review.get("summary")
    if not isinstance(summary, dict):
        raise SystemExit(f"{batch_id}: review summary missing")
    expected_batch_summary = {
        "reviewed": len(rows),
        "accept": batch_counts["accept"],
        "reject": batch_counts["reject"],
        "rework": batch_counts["rework"],
        "hold": batch_counts["hold"],
    }
    if summary != expected_batch_summary:
        raise SystemExit(f"{batch_id}: review summary drift")

    batch_contexts.append(
        {
            "batch_id": batch_id,
            "dir": batch_dir,
            "fields": fields,
            "rows": rows,
            "review": review,
            "decisions": decisions,
            "author_id": author_id,
            "reviewer_id": reviewer_id,
            "accepted": tuple(accepted_batch),
        }
    )

actual_review_counts = {
    "reviewed": actual_counts["reviewed"],
    "accept": actual_counts["accept"],
    "reject": actual_counts["reject"],
    "rework": actual_counts["rework"],
    "hold": actual_counts["hold"],
}
if actual_review_counts != expected_review_counts:
    raise SystemExit(f"wave review summary drift: {actual_review_counts} != {expected_review_counts}")
if len(accepted_ids) != expected_accept_count or len(set(accepted_ids)) != len(accepted_ids):
    raise SystemExit("accepted candidate set drift")
if len(all_actor_ids) != 1 + len(reviewer_ids) + len(author_ids):
    raise SystemExit("actor identity collision across wave")

nonaccepted_from_wave = wave.get("non_accepted_candidate_ids")
if isinstance(nonaccepted_from_wave, dict):
    expected_nonaccepted = set()
    for values in nonaccepted_from_wave.values():
        if isinstance(values, list):
            expected_nonaccepted.update(str(value) for value in values)
    if expected_nonaccepted != {item["candidate_id"] for item in nonaccepted}:
        raise SystemExit("wave non-accepted candidate set drift")

bank_questions_path = AUTHORING / "questions.csv"
registry_path = AUTHORING / "question_id_registry.csv"
source_verifications_path = AUTHORING / "source_verifications.json"
released_path = AUTHORING / "released_questions.json"
with bank_questions_path.open(encoding="utf-8", newline="") as handle:
    canonical_before = list(csv.DictReader(handle))
with registry_path.open(encoding="utf-8", newline="") as handle:
    registry_before = list(csv.DictReader(handle))
source_verifications_before = read_json(source_verifications_path).get("verifications", [])
released_before = read_json(released_path).get("released_questions", [])
meta = read_json(AUTHORING / "bank.json")
runtime_path = BANK / str(meta.get("runtime_output", ""))
runtime_before = runtime_path.read_bytes()

canonical_baseline = wave.get("canonical_verified_baseline")
if not isinstance(canonical_baseline, int) or len(canonical_before) != canonical_baseline:
    raise SystemExit("canonical baseline drift before wave promotion")
if len(registry_before) != canonical_baseline or len(source_verifications_before) != canonical_baseline:
    raise SystemExit("registry/source-verification baseline drift before wave promotion")

rationale = (
    "Adopt the independent reviewer decisions without quota backfill. The accepted candidates satisfy the current "
    "source-binding, semantic-collision and educational-value gates. Reviewer REJECT/REWORK/HOLD decisions remain "
    "blocking under Wave Mode and cannot receive acceptance packets or READY_FOR_ID status in this transaction."
)
director_artifact = {
    "schema_version": "1.0",
    "wave_id": wave_id,
    "adjudication_round": 1,
    "adjudicated_at": str(request.get("adjudicated_at", "")).strip(),
    "director": {"id": director_id, "role": "AI_DIRECTOR"},
    "authors": {context["batch_id"]: {"id": context["author_id"], "role": "AI_AUTHOR"} for context in batch_contexts},
    "reviewers": {context["batch_id"]: {"id": context["reviewer_id"], "role": "AI_REVIEWER"} for context in batch_contexts},
    "identity_separation": "PASS",
    "decision": "ADOPT_REVIEWER_DECISIONS",
    "summary": {key: actual_review_counts[key] for key in ("accept", "reject", "rework", "hold")},
    "accepted_candidate_ids": accepted_ids,
    "nonaccepted": nonaccepted,
    "director_rationale": rationale,
    "invariants_before_transaction": {
        "candidate_states": "ALL_AI_PRE_ACCEPT",
        "acceptance_packets": 0,
        "permanent_ids_allocated": 0,
        "canonical_count": len(canonical_before),
        "registry_count": len(registry_before),
        "source_verification_count": len(source_verifications_before),
        "released_count": len(released_before),
        "runtime_unchanged_required": True,
        "human_review_fabricated": False,
    },
    "final_gate": f"READY_TO_ALLOCATE_AND_INTEGRATE_{wave_id}_ACCEPTED_{len(accepted_ids)}",
}
if not director_artifact["adjudicated_at"]:
    raise SystemExit("adjudicated_at is required")
director_path = WAVES / f"wave_{wave_number:03d}_director_adjudication_r1.json"
if director_path.exists():
    raise SystemExit("partial Director adjudication state detected")
director_path.write_text(json.dumps(director_artifact, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

for context in batch_contexts:
    batch_dir = context["dir"]
    packets_dir = batch_dir / "acceptance_packets"
    packets_dir.mkdir(exist_ok=True)
    for candidate_id in context["accepted"]:
        candidate = context["rows"][candidate_id]
        review_decision = context["decisions"][candidate_id]
        packet = {
            "schema_version": "1.0",
            "candidate_id": candidate_id,
            "candidate_state": "AI_PRE_ACCEPT",
            "candidate_fingerprint": candidate_fingerprint(candidate),
            "actors": {
                "author": {"id": context["author_id"], "role": "AI_AUTHOR"},
                "reviewer": {"id": context["reviewer_id"], "role": "AI_REVIEWER"},
                "director": {"id": director_id, "role": "AI_DIRECTOR"},
            },
            "evidence": {
                "source": {key: candidate[key] for key in ("source_id", "source_version", "source_locator")},
                "answer_defining_proposition": candidate["answer_defining_proposition"],
                "tested_misconception": candidate["tested_misconception"],
                "reasoning_path": candidate["reasoning_path"],
                "collision": {
                    "released_bank_checked": True,
                    "canonical_drafts_checked": True,
                    "batch_checked": True,
                    "note": candidate["collision_note"],
                },
            },
            "independent_review": {"decision": "ACCEPT", "rationale": review_decision["rationale"]},
            "director_adjudication": {"decision": "ACCEPT", "rationale": rationale},
            "requested_state": "AI_GOVERNED_ACCEPT",
        }
        (packets_dir / f"{candidate_id}.json").write_text(
            json.dumps(packet, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

for context in batch_contexts:
    batch_dir = context["dir"]
    expected_packets = set(context["accepted"])
    packets_dir = batch_dir / "acceptance_packets"
    if {path.stem for path in packets_dir.glob("*.json")} != expected_packets:
        raise SystemExit(f"{context['batch_id']}: acceptance packet set drift")
    for candidate_id in context["accepted"]:
        errors = ai_acceptance_errors(batch_dir, context["rows"][candidate_id])
        if errors:
            raise SystemExit(f"{candidate_id}: invalid acceptance packet: " + " | ".join(errors))
    promote_ai_governed_candidates(batch_dir, context["accepted"])

for context in batch_contexts:
    _, after_rows_list = read_candidates(context["dir"] / "candidates.csv")
    after_rows = {row["candidate_id"]: row for row in after_rows_list}
    accepted_set = set(context["accepted"])
    for candidate_id, row in after_rows.items():
        if candidate_id in accepted_set:
            if row.get("state") != "READY_FOR_ID" or row.get("permanent_question_id"):
                raise SystemExit(f"{candidate_id}: accepted promotion failed")
        elif row.get("state") != "AI_PRE_ACCEPT" or row.get("permanent_question_id"):
            raise SystemExit(f"{candidate_id}: non-accepted candidate mutated")
    errors = validate_expansion_batch(context["dir"])
    if errors:
        raise SystemExit(f"{context['batch_id']}: expansion validation failed: " + " | ".join(errors))

with bank_questions_path.open(encoding="utf-8", newline="") as handle:
    canonical_after = list(csv.DictReader(handle))
with registry_path.open(encoding="utf-8", newline="") as handle:
    registry_after = list(csv.DictReader(handle))
source_verifications_after = read_json(source_verifications_path).get("verifications", [])
released_after = read_json(released_path).get("released_questions", [])
if canonical_after != canonical_before or registry_after != registry_before:
    raise SystemExit("canonical/registry changed during Wave accept-and-promote")
if source_verifications_after != source_verifications_before or released_after != released_before:
    raise SystemExit("source-verification/released state changed during Wave accept-and-promote")
if runtime_path.read_bytes() != runtime_before:
    raise SystemExit("runtime changed during Wave accept-and-promote")

wave["status"] = "DIRECTOR_ACCEPTED_AND_PROMOTED"
wave["director_adjudication"] = {
    "artifact": director_path.name,
    "decision": "ADOPT_REVIEWER_DECISIONS",
    "accept": actual_review_counts["accept"],
    "reject": actual_review_counts["reject"],
    "rework": actual_review_counts["rework"],
    "hold": actual_review_counts["hold"],
}
wave["accepted_candidate_state"] = "READY_FOR_ID"
wave["accept_promote_state_epoch"] = int(expected_epoch) + 1
wave["next_gate"] = f"ALLOCATE_AND_INTEGRATE_{wave_id}_ACCEPTED_{len(accepted_ids)}"
wave_path.write_text(json.dumps(wave, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

state["observed_main"] = subprocess.check_output(["git", "rev-parse", "origin/main"], text=True).strip()
state["state_epoch"] = int(expected_epoch) + 1
state["next_atomic_objective"] = f"ALLOCATE_AND_INTEGRATE_OTSU4_WAVE_{wave_number}_ACCEPTED_{len(accepted_ids)}"
STATE_PATH.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
