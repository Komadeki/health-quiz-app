"""Contract validation for the Drone V0-Panel validation bundle."""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Any

from contract import (
    file_sha256,
    formal_snapshot_source_hash,
    load_validation_inputs,
    parse_control_metadata,
)
from generation import build_generated_files, build_validation_documents


EXPECTED_BANK_REVISION = "drone-second-class-v0-core-2026-08-19"
EXPECTED_CONTENT_AS_OF = "2026-08-19"
EXPECTED_SNAPSHOT_SHA = "61eb6962416e6cd91f22cbf96126244ff760fcc6"
EXPECTED_PROTOCOL_VERSION = "drone-second-class-v0-panel-protocol-v1"
EXPECTED_ROLE_COUNTS = {
    "DEEP_OBSERVED": 14,
    "DEEP_HELDOUT": 6,
    "DEEP_REPLICATION_A": 1,
    "DEEP_REPLICATION_B": 1,
    "BREADTH_OBSERVED": 7,
    "BREADTH_HELDOUT": 7,
    "UNKNOWN_SENTINEL": 8,
    "COVERAGE": 56,
}
EXPECTED_DEEP = {
    "VS-001": ("H1", None, None),
    "VS-002": ("H2", None, None),
    "VS-003": ("H2", "VS-002", None),
    "VS-004": ("T1", None, None),
    "VS-005": ("T2", None, None),
    "VS-006": ("T2", "VS-005", None),
    "VS-007": ("G1", None, None),
    "VS-008": ("G2", None, None),
    "VS-009": ("G1", "VS-007", None),
    "VS-010": ("A1", None, None),
    "VS-011": ("A4", None, None),
    "VS-012": ("E1", None, None),
    "VS-013": ("E2", None, None),
    "VS-014": ("E1", "VS-012", None),
    "VS-015": ("H5", None, None),
    "VS-016": ("T3", None, None),
    "VS-017": ("G3", None, None),
    "VS-018": ("A2", None, None),
    "VS-019": ("A3", None, None),
    "VS-020": ("E3", None, None),
    "VS-021": ("H3", None, "A"),
    "VS-022": ("H4", None, "B"),
}
EXPECTED_BREADTH = {
    "HB-1": ("VS-023", "VS-030", "YES"),
    "HB-2": ("VS-024", "VS-031", "PARTIAL_ONLY"),
    "HB-3": ("VS-025", "VS-032", "YES"),
    "HB-4": ("VS-026", "VS-033", "YES"),
    "HB-5": ("VS-027", "VS-034", "YES"),
    "HB-6": ("VS-028", "VS-035", "YES"),
    "HB-7": ("VS-029", "VS-036", "YES"),
}
EXPECTED_SENTINELS = {
    "US-A": ("VS-037", "DRONE-Q-000041"),
    "US-B": ("VS-038", "DRONE-Q-000042"),
    "US-C": ("VS-039", "DRONE-Q-000004"),
    "US-D": ("VS-040", "DRONE-Q-000043"),
    "US-E": ("VS-041", "DRONE-Q-000039"),
    "US-F": ("VS-042", "DRONE-Q-000040"),
    "US-G": ("VS-043", "DRONE-Q-000044"),
    "US-H": ("VS-044", "DRONE-Q-000045"),
}
REQUIRED_SENTINEL_TOKENS = {
    "US-A": {"COV-01", "MODEL_AIRCRAFT_RESIDUAL_REGULATION_TRUTH"},
    "US-B": {"COV-08", "COV-39", "VS-083", "AFTER_SENTINEL_RESPONSE"},
    "US-C": {"COV-25", "VS-069", "REMOTE_COMMAND_CHAIN_TRUTH"},
    "US-D": {
        "COV-32",
        "INTERFERENCE_IMPLIES_CALIBRATION",
        "COV-26",
        "GENERIC_CALIBRATION_TRUTH",
    },
    "US-E": {"COV-37", "PREFLIGHT"},
    "US-F": {"HB-5", "RESIDUAL_ALCOHOL_TRUTH"},
    "US-G": {
        "COV-43",
        "ALTERNATE_LANDING_LOCATION",
        "EMERGENCY_LANDING_OPTION_PREPLANNING",
        "CONTINGENCY_ROUTE",
        "H3",
        "H4",
    },
    "US-H": {
        "HB-6",
        "LOW_TEMPERATURE_BATTERY",
        "TEMPERATURE_TO_ENDURANCE",
        "THERMAL_ENVIRONMENT_TO_ENERGY_MARGIN",
    },
}


def _error(errors: list[str], code: str, message: str) -> None:
    errors.append(f"ERROR [{code}] {message}")


def _validate_protocol(protocol: dict[str, Any], errors: list[str]) -> None:
    expected_scalars = {
        "schema_version": 1,
        "bank_revision": EXPECTED_BANK_REVISION,
        "content_as_of": EXPECTED_CONTENT_AS_OF,
        "formal_snapshot_commit_sha": EXPECTED_SNAPSHOT_SHA,
        "validation_protocol_version": EXPECTED_PROTOCOL_VERSION,
    }
    for key, expected in expected_scalars.items():
        if protocol.get(key) != expected:
            _error(errors, "protocol_identity_mismatch", f"{key} must be {expected!r}.")
    if protocol.get("required_role_counts") != EXPECTED_ROLE_COUNTS:
        _error(errors, "protocol_role_counts_mismatch", "Required role counts changed.")
    if protocol.get("coverage_mapping") != {
        "slot_start": 45,
        "slot_end": 100,
        "coverage_start": 1,
        "coverage_end": 56,
    }:
        _error(errors, "coverage_formula_mismatch", "Coverage formula must map VS-045..VS-100 to COV-01..COV-56.")

    deep = {
        entry.get("slot_id"): (
            entry.get("contamination_group"),
            entry.get("alternate_of"),
            entry.get("replication_form"),
        )
        for entry in protocol.get("deep_measurements", [])
    }
    if deep != EXPECTED_DEEP:
        _error(errors, "deep_mapping_mismatch", "Deep measurement mapping changed.")

    breadth = {
        entry.get("contamination_group"): (
            entry.get("observed_slot_id"),
            entry.get("heldout_slot_id"),
            entry.get("counterbalance"),
        )
        for entry in protocol.get("breadth_measurements", [])
    }
    if breadth != EXPECTED_BREADTH:
        _error(errors, "breadth_mapping_mismatch", "Breadth measurement mapping changed.")

    sentinels = {
        entry.get("sentinel_id"): (entry.get("slot_id"), entry.get("question_id"))
        for entry in protocol.get("sentinels", [])
    }
    if sentinels != EXPECTED_SENTINELS:
        _error(errors, "sentinel_mapping_mismatch", "Sentinel mapping changed.")
    for entry in protocol.get("sentinels", []):
        sentinel_id = entry.get("sentinel_id")
        serialized = json.dumps(entry.get("routing_constraints", []), sort_keys=True)
        missing = REQUIRED_SENTINEL_TOKENS.get(sentinel_id, set()) - {
            token for token in REQUIRED_SENTINEL_TOKENS.get(sentinel_id, set()) if token in serialized
        }
        if missing:
            _error(errors, "sentinel_routing_incomplete", f"{sentinel_id} is missing {sorted(missing)}.")

    if protocol.get("feedback_lock") != {
        "requires_all_bank_sentinels": False,
        "sentinel_scope": "PARTICIPANT_ASSIGNED",
        "unlock_condition": "ALL_ASSIGNED_SENTINEL_RESPONSES_DURABLY_COMMITTED",
    }:
        _error(errors, "feedback_lock_mismatch", "Feedback lock must use the participant-assigned Sentinel block.")
    cov_52 = protocol.get("coverage_routing_constraints", {}).get("COV-52")
    if cov_52 != [
        {"constraint_type": "ROUTE_CLASS_REQUIRED", "route_class": "NON_THERMAL_FOG"}
    ]:
        _error(errors, "cov_52_route_mismatch", "COV-52 must remain the non-thermal fog route.")


def _validate_source_state(inputs: Any, errors: list[str]) -> dict[str, dict[str, str]]:
    if inputs.bank.get("bank_revision") != EXPECTED_BANK_REVISION:
        _error(errors, "bank_revision_mismatch", "Formal bank revision changed.")
    if inputs.bank.get("content_as_of") != EXPECTED_CONTENT_AS_OF:
        _error(errors, "content_as_of_mismatch", "Formal content_as_of changed.")

    expected_ids = {f"DRONE-Q-{number:06d}" for number in range(1, 101)}
    question_ids = [row.get("question_id", "") for row in inputs.questions]
    if len(question_ids) != 100 or set(question_ids) != expected_ids:
        _error(errors, "question_id_set_mismatch", "Questions must be exactly DRONE-Q-000001..DRONE-Q-000100.")
    if any(row.get("question_version") != "1" for row in inputs.questions):
        _error(errors, "question_version_mismatch", "All question versions must be 1.")
    if any(row.get("status") != "draft" for row in inputs.questions):
        _error(errors, "question_status_mismatch", "All source questions must remain draft.")

    registry_ids = {row.get("question_id", "") for row in inputs.registry}
    if registry_ids != expected_ids:
        _error(errors, "registry_id_set_mismatch", "Registry must contain only the first 100 permanent IDs.")
    if any(row.get("first_used_bank_revision", "") for row in inputs.registry):
        _error(errors, "first_used_revision_set", "first_used_bank_revision must remain empty.")
    if inputs.released.get("released_questions") != []:
        _error(errors, "released_questions_not_empty", "released_questions must remain empty.")

    controls_by_slot: dict[str, dict[str, str]] = {}
    roles: Counter[str] = Counter()
    for row in inputs.questions:
        try:
            controls = parse_control_metadata(row.get("notes_internal", ""))
        except ValueError as exception:
            _error(errors, "invalid_control_metadata", f"{row.get('question_id')}: {exception}")
            continue
        missing = {"slot_id", "primary_role", "kt_id"} - controls.keys()
        if missing:
            _error(errors, "missing_required_metadata", f"{row.get('question_id')} is missing {sorted(missing)}.")
            continue
        slot_id = controls["slot_id"]
        if slot_id in controls_by_slot:
            _error(errors, "duplicate_slot_id", f"Duplicate slot_id: {slot_id}.")
        controls_by_slot[slot_id] = {**controls, "question_id": row.get("question_id", "")}
        roles[controls["primary_role"]] += 1

    expected_slots = {f"VS-{number:03d}" for number in range(1, 101)}
    if set(controls_by_slot) != expected_slots:
        _error(errors, "slot_id_set_mismatch", "Slots must be exactly VS-001..VS-100.")
    if dict(roles) != EXPECTED_ROLE_COUNTS:
        _error(errors, "role_counts_mismatch", f"Role counts are {dict(roles)}.")

    for slot_id, (family, alternate_of, _) in EXPECTED_DEEP.items():
        controls = controls_by_slot.get(slot_id, {})
        if controls.get("family") != family:
            _error(errors, "deep_family_mismatch", f"{slot_id} must use item family {family}.")
        if controls.get("alternate_of") != (alternate_of or None):
            _error(errors, "deep_alternate_mismatch", f"{slot_id} alternate_of changed.")
    for group, (observed, heldout, counterbalance) in EXPECTED_BREADTH.items():
        for slot_id, role in ((observed, "BREADTH_OBSERVED"), (heldout, "BREADTH_HELDOUT")):
            controls = controls_by_slot.get(slot_id, {})
            if (
                controls.get("primary_role") != role
                or controls.get("counterbalance") not in (None, counterbalance)
            ):
                _error(errors, "breadth_source_mapping_mismatch", f"{group} source controls changed at {slot_id}.")
    for sentinel_id, (slot_id, question_id) in EXPECTED_SENTINELS.items():
        controls = controls_by_slot.get(slot_id, {})
        if controls.get("question_id") != question_id or controls.get("family") != sentinel_id:
            _error(errors, "sentinel_source_mapping_mismatch", f"{sentinel_id} source mapping changed.")
    for number in range(1, 57):
        slot_id = f"VS-{44 + number:03d}"
        controls = controls_by_slot.get(slot_id, {})
        if controls.get("coverage") != f"COV-{number:02d}":
            _error(errors, "coverage_source_mapping_mismatch", f"{slot_id} must map to COV-{number:02d}.")
    return controls_by_slot


def _validate_protected_files(inputs: Any, errors: list[str]) -> None:
    hashes = inputs.protocol.get("protected_file_byte_hashes", {})
    for relative_path, expected_hash in hashes.items():
        path = inputs.source_root / relative_path
        if not path.exists() or file_sha256(path) != expected_hash:
            _error(errors, "protected_file_drift", f"Protected file changed: {relative_path}.")


def _validate_production_runtime(inputs: Any, errors: list[str]) -> None:
    runtime_path = inputs.source_root / "generated" / "drone_second_class_bank.json"
    manifest_path = inputs.source_root / "generated" / "bank_manifest.json"
    runtime = json.loads(runtime_path.read_text(encoding="utf-8"))
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if runtime.get("decks") != []:
        _error(errors, "production_runtime_not_empty", "Production decks must remain empty.")
    if manifest.get("question_count") != 0 or manifest.get("free_question_count") != 0:
        _error(errors, "production_counts_not_zero", "Production question counts must remain zero.")
    if runtime.get("examProfileVersion") != "drone-second-class-unreleased":
        _error(errors, "production_profile_changed", "Production exam profile changed.")


def _contains_key(value: Any, forbidden_key: str) -> bool:
    if isinstance(value, dict):
        return forbidden_key in value or any(
            _contains_key(child, forbidden_key) for child in value.values()
        )
    if isinstance(value, list):
        return any(_contains_key(child, forbidden_key) for child in value)
    return False


def _validate_built_documents(inputs: Any, errors: list[str]) -> None:
    try:
        bundle, manifest = build_validation_documents(inputs)
    except (KeyError, TypeError, ValueError) as exception:
        _error(errors, "bundle_build_failed", str(exception))
        return
    questions = bundle.get("questions", [])
    if len(questions) != 100 or manifest.get("bundle_question_count") != 100:
        _error(errors, "bundle_count_mismatch", "Validation bundle must contain 100 questions.")
    if manifest.get("role_counts") != EXPECTED_ROLE_COUNTS:
        _error(errors, "manifest_role_counts_mismatch", "Manifest role counts changed.")
    if manifest.get("coverage_count") != 56 or manifest.get("sentinel_count") != 8:
        _error(errors, "manifest_protocol_counts_mismatch", "Coverage/Sentinel counts must be 56/8.")
    required_metadata = {"question_id", "question_version"}
    required_validation = {
        "slot_id",
        "primary_role",
        "kt_id",
        "item_family",
        "contamination_group",
        "alternate_of",
        "counterbalance",
        "administration_role_eligibility",
        "coverage_id",
        "sentinel_id",
        "replication_form",
        "routing_constraints",
    }
    for question in questions:
        if not required_metadata <= question.keys():
            _error(errors, "bundle_question_metadata_missing", f"Missing identity metadata for {question.get('question_id')}.")
        metadata = question.get("validation_metadata", {})
        if not required_validation <= metadata.keys():
            _error(errors, "bundle_validation_metadata_missing", f"Missing typed metadata for {question.get('question_id')}.")
    if _contains_key(bundle, "notes_internal"):
        _error(errors, "notes_internal_leaked", "Raw notes_internal must not be emitted.")


def validate_contract(bank_root: Path, *, check_generated: bool) -> list[str]:
    errors: list[str] = []
    try:
        inputs = load_validation_inputs(bank_root)
    except (FileNotFoundError, json.JSONDecodeError, ValueError) as exception:
        return [f"ERROR [invalid_validation_layout] {exception}"]

    _validate_protocol(inputs.protocol, errors)
    _validate_source_state(inputs, errors)
    _validate_protected_files(inputs, errors)
    _validate_production_runtime(inputs, errors)
    actual_source_hash = formal_snapshot_source_hash(inputs)
    if actual_source_hash != inputs.protocol.get("formal_snapshot_source_hash"):
        _error(errors, "formal_snapshot_source_hash_mismatch", "Formal snapshot inputs changed under the fixed bank revision.")
    _validate_built_documents(inputs, errors)

    if check_generated:
        try:
            expected_files = build_generated_files(inputs)
        except (KeyError, TypeError, ValueError) as exception:
            _error(errors, "generated_build_failed", str(exception))
        else:
            for relative_path, expected in expected_files.items():
                path = bank_root / relative_path
                if not path.exists() or path.read_bytes() != expected:
                    _error(errors, "validation_generated_drift", f"Regenerate {relative_path}.")
    return errors
