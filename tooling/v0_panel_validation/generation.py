"""Deterministic V0-Panel validation bundle generation."""

from __future__ import annotations

from collections import Counter
from pathlib import Path
from typing import Any, Iterable

from contract import (
    GENERATED_NOTICE,
    ValidationInputs,
    canonical_json_bytes,
    formal_snapshot_source_hash,
    load_validation_inputs,
    parse_control_metadata,
    pretty_json_bytes,
    sha256_value,
)


def _slot_number(slot_id: str) -> int:
    return int(slot_id.removeprefix("VS-"))


def _protocol_maps(
    protocol: dict[str, Any],
) -> tuple[dict[str, dict[str, Any]], dict[str, dict[str, Any]], dict[str, dict[str, Any]]]:
    deep = {entry["slot_id"]: entry for entry in protocol["deep_measurements"]}
    breadth: dict[str, dict[str, Any]] = {}
    for entry in protocol["breadth_measurements"]:
        breadth[entry["observed_slot_id"]] = entry
        breadth[entry["heldout_slot_id"]] = entry
    sentinels = {entry["slot_id"]: entry for entry in protocol["sentinels"]}
    return deep, breadth, sentinels


def _role_eligibility(role: str, breadth: dict[str, Any] | None) -> list[str]:
    if breadth is None:
        return [role]
    return ["BREADTH_OBSERVED", "BREADTH_HELDOUT"]


def _question_payload(
    row: dict[str, str],
    protocol: dict[str, Any],
    deep_by_slot: dict[str, dict[str, Any]],
    breadth_by_slot: dict[str, dict[str, Any]],
    sentinel_by_slot: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    controls = parse_control_metadata(row["notes_internal"])
    slot_id = controls["slot_id"]
    role = controls["primary_role"]
    deep = deep_by_slot.get(slot_id)
    breadth = breadth_by_slot.get(slot_id)
    sentinel = sentinel_by_slot.get(slot_id)
    coverage_id = controls.get("coverage")

    routing_constraints: list[dict[str, Any]] = []
    if sentinel is not None:
        routing_constraints.extend(sentinel["routing_constraints"])
    if coverage_id is not None:
        routing_constraints.extend(
            protocol.get("coverage_routing_constraints", {}).get(coverage_id, [])
        )

    metadata = {
        "administration_role_eligibility": _role_eligibility(role, breadth),
        "alternate_of": deep.get("alternate_of") if deep else None,
        "contamination_group": (
            deep["contamination_group"]
            if deep
            else breadth["contamination_group"]
            if breadth
            else None
        ),
        "counterbalance": breadth.get("counterbalance") if breadth else None,
        "coverage_id": coverage_id,
        "item_family": controls.get("family"),
        "kt_id": controls["kt_id"],
        "primary_role": role,
        "replication_form": deep.get("replication_form") if deep else None,
        "routing_constraints": routing_constraints,
        "sentinel_id": sentinel.get("sentinel_id") if sentinel else None,
        "slot_id": slot_id,
    }
    choices = [
        row[f"choice{index}"]
        for index in range(1, 5)
        if row[f"choice{index}"]
    ]
    return {
        "choices": choices,
        "correct_choice": row["correct_choice"],
        "correct_index": ord(row["correct_choice"]) - ord("A"),
        "deck_id": row["deck_id"],
        "explanation": row["explanation"],
        "question": row["question"],
        "question_id": row["question_id"],
        "question_version": int(row["question_version"]),
        "source_reference": {
            "source_id": row["source_id"],
            "source_locator": row["source_locator"],
        },
        "unit_id": row["unit_id"],
        "validation_metadata": metadata,
    }


def build_validation_documents(
    inputs: ValidationInputs,
) -> tuple[dict[str, Any], dict[str, Any]]:
    protocol = inputs.protocol
    deep, breadth, sentinels = _protocol_maps(protocol)
    questions = [
        _question_payload(row, protocol, deep, breadth, sentinels)
        for row in inputs.questions
    ]
    questions.sort(
        key=lambda item: _slot_number(item["validation_metadata"]["slot_id"])
    )
    source_hash = formal_snapshot_source_hash(inputs)
    bundle = {
        "artifact_purpose": "VALIDATION_ONLY",
        "bank_revision": protocol["bank_revision"],
        "content_as_of": protocol["content_as_of"],
        "formal_snapshot_commit_sha": protocol["formal_snapshot_commit_sha"],
        "formal_snapshot_source_hash": source_hash,
        "generated_file_notice": GENERATED_NOTICE,
        "questions": questions,
        "schema_version": 1,
        "sentinel_feedback_lock": protocol["feedback_lock"],
        "validation_protocol_version": protocol["validation_protocol_version"],
    }
    bundle_hash = sha256_value(canonical_json_bytes(bundle))
    role_counts = Counter(
        question["validation_metadata"]["primary_role"] for question in questions
    )
    manifest = {
        "artifact_purpose": "VALIDATION_ONLY",
        "bank_revision": protocol["bank_revision"],
        "bundle_question_count": len(questions),
        "content_as_of": protocol["content_as_of"],
        "coverage_count": sum(
            question["validation_metadata"]["coverage_id"] is not None
            for question in questions
        ),
        "formal_snapshot_commit_sha": protocol["formal_snapshot_commit_sha"],
        "formal_snapshot_source_hash": source_hash,
        "generated_file_notice": GENERATED_NOTICE,
        "hash_basis": "CANONICAL_JSON_V1",
        "role_counts": dict(sorted(role_counts.items())),
        "schema_version": 1,
        "sentinel_count": sum(
            question["validation_metadata"]["sentinel_id"] is not None
            for question in questions
        ),
        "validation_bundle_hash": bundle_hash,
        "validation_protocol_version": protocol["validation_protocol_version"],
    }
    return bundle, manifest


def build_generated_files(inputs: ValidationInputs) -> dict[Path, bytes]:
    bundle, manifest = build_validation_documents(inputs)
    return {
        Path(inputs.protocol["bundle_output"]): pretty_json_bytes(bundle),
        Path(inputs.protocol["manifest_output"]): pretty_json_bytes(manifest),
    }


def write_generated_files(bank_root: Path) -> Iterable[Path]:
    from validation import validate_contract

    validation = validate_contract(bank_root, check_generated=False)
    if validation:
        raise ValueError("\n".join(validation))
    inputs = load_validation_inputs(bank_root)
    written: list[Path] = []
    for relative_path, content in build_generated_files(inputs).items():
        path = bank_root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        written.append(path)
    return written
