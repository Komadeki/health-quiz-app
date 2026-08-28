#!/usr/bin/env python3
"""Fail-closed activation of the reviewed Eisei1 400-question bank."""

from __future__ import annotations

import csv
import hashlib
import json
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
BANK = REPO / "question_banks" / "eisei1"
AUTHORING = BANK / "authoring"
sys.path.insert(0, str(REPO / "tooling" / "question_bank"))

from contract import load_bank_inputs, pretty_json_bytes  # noqa: E402
from expansion import validate_expansion_batch  # noqa: E402
from generation import (  # noqa: E402
    build_released_questions_document,
    write_generated_files,
)
from validation import validate_bank  # noqa: E402

RELEASE_ID = "eisei1-v1-release-2026-08-28"
RELEASE_DATE = "2026-08-28"
ALL_IDS = tuple(f"EISEI1-Q-{number:06d}" for number in range(1, 401))
ALL_ID_SET = set(ALL_IDS)
FREE_COUNTS = {
    "eisei1_law_hazardous": 7,
    "eisei1_hygiene_hazardous": 7,
    "eisei1_law_general": 5,
    "eisei1_hygiene_general": 4,
    "eisei1_physiology": 7,
}


def fail(message: str) -> None:
    raise SystemExit(message)


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), list(reader)


def write_csv(
    path: Path,
    fields: list[str],
    rows: list[dict[str, str]],
) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def sha256(path: Path) -> str:
    return f"sha256:{hashlib.sha256(path.read_bytes()).hexdigest()}"


bank_path = AUTHORING / "bank.json"
questions_path = AUTHORING / "questions.csv"
registry_path = AUTHORING / "question_id_registry.csv"
coverage_path = AUTHORING / "coverage.json"
sources_path = AUTHORING / "sources.json"
verifications_path = AUTHORING / "source_verifications.json"
released_path = AUTHORING / "released_questions.json"
review_path = AUTHORING / "EISEI1_INDEPENDENT_AI_REVIEW_400_V1.md"

bound_paths = (
    bank_path,
    questions_path,
    registry_path,
    coverage_path,
    sources_path,
    verifications_path,
    released_path,
    review_path,
)
baseline_hashes = {
    str(path.relative_to(REPO)): sha256(path) for path in bound_paths
}

metadata = json.loads(bank_path.read_text(encoding="utf-8"))
if metadata.get("bank_revision") != "eisei1-bank-bootstrap-2026-08-26":
    fail("unexpected pre-release bank revision")
if metadata.get("content_as_of") != "2026-08-26":
    fail("unexpected pre-release content date")

question_fields, questions = read_csv(questions_path)
question_lists: dict[str, list[dict[str, str]]] = defaultdict(list)
for row in questions:
    question_lists[row["question_id"]].append(row)
if set(question_lists) != ALL_ID_SET:
    fail("canonical inventory must be exact EISEI1 Q1..Q400")
if any(len(rows) != 1 for rows in question_lists.values()):
    fail("canonical question IDs must be unique")
question_by_id = {question_id: rows[0] for question_id, rows in question_lists.items()}
if any(question_by_id[question_id]["status"] != "draft" for question_id in ALL_IDS):
    fail("all 400 canonical questions must still be draft")
if any(question_by_id[question_id]["is_free"] != "false" for question_id in ALL_IDS):
    fail("pre-release free selection must be empty")

expected_unit_counts = {
    "eisei1_law_hazardous": 91,
    "eisei1_hygiene_hazardous": 91,
    "eisei1_law_general": 64,
    "eisei1_hygiene_general": 64,
    "eisei1_physiology": 90,
}
if Counter(row["unit_id"] for row in questions) != expected_unit_counts:
    fail("reviewed 400-question unit allocation drift")

registry_fields, registry_rows = read_csv(registry_path)
registry_lists: dict[str, list[dict[str, str]]] = defaultdict(list)
for row in registry_rows:
    registry_lists[row["question_id"]].append(row)
if set(registry_lists) != ALL_ID_SET or any(
    len(rows) != 1 for rows in registry_lists.values()
):
    fail("registry inventory must be exact unique Q1..Q400")
registry_by_id = {
    question_id: rows[0] for question_id, rows in registry_lists.items()
}
if any(
    registry_by_id[question_id]["status"] != "used"
    or registry_by_id[question_id]["first_used_bank_revision"]
    or registry_by_id[question_id]["retired_at"]
    for question_id in ALL_IDS
):
    fail("registry pre-release state drift")

released = json.loads(released_path.read_text(encoding="utf-8"))
if released.get("released_questions") != []:
    fail("released snapshot must still be empty")

sources = json.loads(sources_path.read_text(encoding="utf-8")).get("sources", [])
source_by_id = {source["source_id"]: source for source in sources}
verifications = json.loads(
    verifications_path.read_text(encoding="utf-8")
).get("verifications", [])
verification_lists: dict[str, list[dict[str, object]]] = defaultdict(list)
for verification in verifications:
    verification_lists[str(verification.get("question_id", ""))].append(
        verification
    )
for question_id in ALL_IDS:
    rows = verification_lists.get(question_id, [])
    question = question_by_id[question_id]
    source = source_by_id.get(question["source_id"])
    if len(rows) != 1 or source is None:
        fail(f"source verification missing or duplicated: {question_id}")
    verification = rows[0]
    if (
        verification.get("verification_state") != "author_source_verified"
        or verification.get("source_id") != question["source_id"]
        or str(verification.get("source_version"))
        != str(source.get("source_version"))
    ):
        fail(f"source verification binding drift: {question_id}")

candidate_bindings: dict[str, tuple[Path, str]] = {}
batch_snapshots: dict[Path, tuple[list[str], list[dict[str, str]]]] = {}
for batch in sorted((AUTHORING / "batches").glob("batch_*")):
    candidates_path = batch / "candidates.csv"
    if not candidates_path.is_file():
        continue
    errors = validate_expansion_batch(batch)
    if errors:
        fail(f"invalid expansion batch {batch.name}: {' | '.join(errors)}")
    fields, rows = read_csv(candidates_path)
    batch_snapshots[candidates_path] = (fields, rows)
    for row in rows:
        question_id = row["permanent_question_id"]
        if question_id not in ALL_ID_SET:
            continue
        if row["state"] != "INTEGRATED" or question_id in candidate_bindings:
            fail(f"candidate binding state drift: {row['candidate_id']}")
        canonical = question_by_id[question_id]
        for candidate_field, canonical_field in (
            ("question", "question"),
            ("choice1", "choice1"),
            ("choice2", "choice2"),
            ("choice3", "choice3"),
            ("choice4", "choice4"),
            ("choice5", "choice5"),
            ("proposed_correct", "correct_choice"),
            ("explanation", "explanation"),
            ("source_id", "source_id"),
            ("source_locator", "source_locator"),
            ("unit_id", "unit_id"),
        ):
            if row[candidate_field] != canonical[canonical_field]:
                fail(
                    f"candidate/canonical drift: {row['candidate_id']} "
                    f"{candidate_field}"
                )
        candidate_bindings[question_id] = (candidates_path, row["candidate_id"])
if set(candidate_bindings) != ALL_ID_SET:
    fail(f"candidate bindings must cover all 400 IDs, got {len(candidate_bindings)}")

coverage = json.loads(coverage_path.read_text(encoding="utf-8"))
target_ids = {
    target["knowledge_target_id"] for target in coverage.get("knowledge_targets", [])
}
bound_target_ids = {
    binding["knowledge_target_id"]
    for binding in coverage.get("question_bindings", [])
}
if len(target_ids) != 37 or target_ids != bound_target_ids:
    fail("coverage must be exactly 37/37 before activation")

preflight = validate_bank(BANK, check_generated=True)
if not preflight.is_valid:
    fail("pre-release bank invalid: " + " | ".join(map(str, preflight.errors)))

free_ids: set[str] = set()
for unit_id, free_count in FREE_COUNTS.items():
    unit_ids = sorted(
        question_id
        for question_id in ALL_IDS
        if question_by_id[question_id]["unit_id"] == unit_id
    )
    free_ids.update(unit_ids[:free_count])
if len(free_ids) != 30:
    fail("free selection must resolve to exactly 30 IDs")

for question_id in ALL_IDS:
    question = question_by_id[question_id]
    question["status"] = "active"
    question["is_free"] = "true" if question_id in free_ids else "false"
    question["last_reviewed_at"] = RELEASE_DATE
    registry_by_id[question_id]["first_used_bank_revision"] = RELEASE_ID
write_csv(questions_path, question_fields, questions)
write_csv(registry_path, registry_fields, registry_rows)

metadata["bank_revision"] = RELEASE_ID
metadata["content_as_of"] = RELEASE_DATE
bank_path.write_bytes(pretty_json_bytes(metadata))

coverage["target_bank_size"] = {
    "approved_question_count": 400,
    "bootstrap": False,
    "rationale": (
        "Frozen after 37/37 coverage, 400/400 source verification, "
        "local validation, and independent AI review."
    ),
}
coverage_path.write_bytes(pretty_json_bytes(coverage))

released_document = build_released_questions_document(load_bank_inputs(BANK))
if [row["question_id"] for row in released_document["released_questions"]] != list(
    ALL_IDS
):
    fail("generated release snapshot inventory drift")
released_path.write_bytes(pretty_json_bytes(released_document))

midflight = validate_bank(BANK, check_generated=False)
if not midflight.is_valid:
    fail("staged bank invalid: " + " | ".join(map(str, midflight.errors)))
list(write_generated_files(BANK))

for candidates_path, (fields, rows) in batch_snapshots.items():
    changed = False
    for row in rows:
        if row["permanent_question_id"] in ALL_ID_SET:
            row["state"] = "RELEASED"
            changed = True
    if changed:
        write_csv(candidates_path, fields, rows)

postflight = validate_bank(BANK, check_generated=True)
if not postflight.is_valid:
    fail("post-release bank invalid: " + " | ".join(map(str, postflight.errors)))
for batch in sorted((AUTHORING / "batches").glob("batch_*")):
    if (batch / "candidates.csv").is_file():
        errors = validate_expansion_batch(batch)
        if errors:
            fail(f"post-release invalid batch {batch.name}: {' | '.join(errors)}")

manifest = json.loads((BANK / "generated" / "bank_manifest.json").read_text())
if (
    manifest.get("question_count") != 400
    or manifest.get("free_question_count") != 30
    or manifest.get("bank_revision") != RELEASE_ID
):
    fail("post-release generated manifest drift")

receipt = {
    "schema_version": 1,
    "activation_id": "EISEI1-PRODUCTION-BANK-400-ACTIVATION-2026-08-28",
    "bank_revision": RELEASE_ID,
    "content_as_of": RELEASE_DATE,
    "question_count": 400,
    "free_question_count": 30,
    "premium_question_count": 370,
    "coverage": "37/37",
    "unit_counts": expected_unit_counts,
    "free_unit_counts": FREE_COUNTS,
    "source_verification_count": 400,
    "validator": {
        "error_count": len(postflight.errors),
        "warning_count": len(postflight.warnings),
        "warning_policy": (
            "Similarity warnings are retained for the release record; "
            "the independent review found no exact duplicate stems or "
            "answer-defining propositions."
        ),
    },
    "independent_review": str(review_path.relative_to(REPO)),
    "baseline_bindings": baseline_hashes,
    "generated_bindings": {
        str(path.relative_to(REPO)): sha256(path)
        for path in (
            BANK / "generated" / "eisei1_bank.json",
            BANK / "generated" / "bank_manifest.json",
        )
    },
    "external_release_performed": False,
}
(AUTHORING / "release_activation_400_2026-08-28.json").write_bytes(
    pretty_json_bytes(receipt)
)
print("Activated Eisei1 400-question production bank.")
