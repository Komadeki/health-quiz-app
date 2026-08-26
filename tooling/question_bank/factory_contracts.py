"""Authoring-only Question Factory coverage and verification contracts."""

from __future__ import annotations

from collections import defaultdict
from datetime import date
from typing import Any

from contract import BankInputs, ValidationResult


def _string(value: Any) -> str:
    return value.strip() if isinstance(value, str) else ""


def _list_of_strings(value: Any) -> list[str] | None:
    if not isinstance(value, list) or any(not _string(item) for item in value):
        return None
    return [_string(item) for item in value]


def validate_coverage(
    inputs: BankInputs,
    question_by_id: dict[str, dict[str, str]],
    unit_ids: set[str],
    result: ValidationResult,
) -> dict[str, Any]:
    """Validate declared coverage without making a semantic adequacy claim."""
    coverage = inputs.coverage
    summary: dict[str, Any] = {
        "declared_target_bank_size": None,
        "bank_size_decision_rationale": "",
        "required_targets": [],
        "optional_targets": [],
        "missing_required_knowledge_target_ids": [],
        "missing_required_variations": [],
        "unbound_active_question_ids": [],
    }
    location = "authoring/coverage.json"
    if not coverage:
        result.error("missing_coverage_artifact", "coverage.json is required.", location)
        return summary
    if coverage.get("schema_version") != 1:
        result.error("invalid_coverage_schema_version", "schema_version must be 1.", location)
    decision = coverage.get("target_bank_size")
    if not isinstance(decision, dict):
        result.error("missing_target_bank_size", "target_bank_size is required.", location)
    else:
        count = decision.get("approved_question_count")
        rationale = _string(decision.get("rationale"))
        bootstrap = decision.get("bootstrap") is True
        valid_count = (
            isinstance(count, int)
            and not isinstance(count, bool)
            and (count >= 1 or (bootstrap and count == 0))
        )
        if not valid_count:
            result.error(
                "invalid_target_bank_size",
                "approved_question_count must be positive, or zero for an explicit bootstrap.",
                location,
            )
        else:
            summary["declared_target_bank_size"] = count
        if not rationale:
            result.error(
                "missing_bank_size_decision_rationale",
                "target_bank_size.rationale is required.",
                location,
            )
        summary["bank_size_decision_rationale"] = rationale

    raw_targets = coverage.get("knowledge_targets")
    if not isinstance(raw_targets, list):
        result.error("invalid_knowledge_targets", "knowledge_targets must be an array.", location)
        raw_targets = []
    targets: dict[str, dict[str, Any]] = {}
    for index, target in enumerate(raw_targets, start=1):
        target_location = f"{location}:knowledge_targets[{index}]"
        if not isinstance(target, dict):
            result.error("invalid_knowledge_target", "Knowledge target must be an object.", target_location)
            continue
        target_id = _string(target.get("knowledge_target_id"))
        if not target_id:
            result.error("missing_knowledge_target_id", "knowledge_target_id is required.", target_location)
            continue
        if target_id in targets:
            result.error("duplicate_knowledge_target_id", f"Duplicate knowledge_target_id: {target_id}", target_location)
            continue
        targets[target_id] = target
        unit_id = _string(target.get("unit_id"))
        if not unit_id:
            result.error("missing_knowledge_target_unit", "unit_id is required.", target_location)
        elif unit_id not in unit_ids:
            result.error("unknown_knowledge_target_unit", f"Unknown unit_id: {unit_id}", target_location)
        for field_name in ("title", "statement"):
            if not _string(target.get(field_name)):
                result.error("missing_knowledge_target_field", f"{field_name} is required.", target_location)
        required = target.get("required")
        if not isinstance(required, bool):
            result.error("invalid_knowledge_target_required", "required must be boolean.", target_location)
        importance = target.get("importance")
        if not isinstance(importance, int) or isinstance(importance, bool) or importance not in {1, 2, 3}:
            result.error("invalid_knowledge_target_importance", "importance must be 1, 2, or 3.", target_location)
        minimum = target.get("minimum_active_question_count")
        if not isinstance(minimum, int) or isinstance(minimum, bool) or minimum < 0:
            result.error(
                "invalid_minimum_active_question_count",
                "minimum_active_question_count must be a non-negative integer.",
                target_location,
            )
        variations = _list_of_strings(target.get("variation_requirements", []))
        if variations is None or len(variations) != len(set(variations)):
            result.error(
                "invalid_variation_requirements",
                "variation_requirements must be unique non-empty strings.",
                target_location,
            )

    raw_bindings = coverage.get("question_bindings")
    if not isinstance(raw_bindings, list):
        result.error("invalid_question_bindings", "question_bindings must be an array.", location)
        raw_bindings = []
    active_ids_by_target: dict[str, set[str]] = defaultdict(set)
    draft_ids_by_target: dict[str, set[str]] = defaultdict(set)
    variation_tags_by_target: dict[str, set[str]] = defaultdict(set)
    bound_active_ids: set[str] = set()
    seen_bindings: set[tuple[str, str, tuple[str, ...]]] = set()
    for index, binding in enumerate(raw_bindings, start=1):
        binding_location = f"{location}:question_bindings[{index}]"
        if not isinstance(binding, dict):
            result.error("invalid_question_binding", "Question binding must be an object.", binding_location)
            continue
        question_id = _string(binding.get("question_id"))
        target_id = _string(binding.get("knowledge_target_id"))
        tags = _list_of_strings(binding.get("variation_tags", []))
        if not question_id or not target_id or tags is None or len(tags) != len(set(tags)):
            result.error(
                "invalid_question_binding",
                "Bindings require question_id, knowledge_target_id, and unique variation_tags.",
                binding_location,
            )
            continue
        identity = (question_id, target_id, tuple(sorted(tags)))
        if identity in seen_bindings:
            result.error("duplicate_question_binding", "Duplicate identical question binding.", binding_location)
            continue
        seen_bindings.add(identity)
        row = question_by_id.get(question_id)
        if row is None:
            result.error("unknown_binding_question_id", f"Unknown question_id: {question_id}", binding_location)
            continue
        if target_id not in targets:
            result.error("unknown_binding_knowledge_target_id", f"Unknown knowledge_target_id: {target_id}", binding_location)
            continue
        target_unit_id = _string(targets[target_id].get("unit_id"))
        if target_unit_id and row.get("unit_id") != target_unit_id:
            result.error(
                "binding_question_unit_mismatch",
                f"{question_id} is in {row.get('unit_id')}, not target unit {target_unit_id}",
                binding_location,
            )
        if row.get("status") == "active":
            active_ids_by_target[target_id].add(question_id)
            variation_tags_by_target[target_id].update(tags)
            bound_active_ids.add(question_id)
        elif row.get("status") == "draft":
            draft_ids_by_target[target_id].add(question_id)

    for target_id in sorted(targets):
        target = targets[target_id]
        minimum = target.get("minimum_active_question_count")
        minimum = minimum if isinstance(minimum, int) and not isinstance(minimum, bool) else 0
        active_count = len(active_ids_by_target[target_id])
        target_summary = {
            "knowledge_target_id": target_id,
            "active_question_count": active_count,
            "draft_question_count": len(draft_ids_by_target[target_id]),
            "minimum_active_question_count": minimum,
            "required": target.get("required") is True,
            "variation_requirements": sorted(_list_of_strings(target.get("variation_requirements", [])) or []),
        }
        summary["required_targets" if target.get("required") is True else "optional_targets"].append(target_summary)
        if active_count < minimum:
            if target.get("required") is True:
                result.error(
                    "missing_required_knowledge_target_coverage",
                    f"{target_id} has {active_count} active question(s); requires {minimum}.",
                    location,
                )
                summary["missing_required_knowledge_target_ids"].append(target_id)
            else:
                result.warning(
                    "optional_knowledge_target_gap",
                    f"{target_id} has {active_count} active question(s); target is {minimum}.",
                    location,
                )
        for tag in _list_of_strings(target.get("variation_requirements", [])) or []:
            if tag not in variation_tags_by_target[target_id]:
                if target.get("required") is True:
                    result.error(
                        "missing_required_variation_coverage",
                        f"{target_id} is missing variation tag: {tag}",
                        location,
                    )
                else:
                    result.warning(
                        "optional_variation_coverage_gap",
                        f"{target_id} is missing optional variation tag: {tag}",
                        location,
                    )
                summary["missing_required_variations"].append(
                    {"knowledge_target_id": target_id, "variation_tag": tag}
                )
    summary["unbound_active_question_ids"] = sorted(
        question_id
        for question_id, row in question_by_id.items()
        if row.get("status") == "active" and question_id not in bound_active_ids
    )
    for question_id in summary["unbound_active_question_ids"]:
        result.warning("unbound_active_question", f"Active question is unbound: {question_id}", location)
    return summary


def validate_source_verifications(
    inputs: BankInputs,
    question_by_id: dict[str, dict[str, str]],
    source_by_id: dict[str, dict[str, Any]],
    result: ValidationResult,
) -> dict[str, Any]:
    """Validate the minimum machine-checkable verification evidence."""
    document = inputs.source_verifications
    summary: dict[str, Any] = {
        "active_question_count": sum(row.get("status") == "active" for row in question_by_id.values()),
        "complete_active_question_count": 0,
        "missing_question_ids": [],
        "source_version_mismatches": [],
    }
    location = "authoring/source_verifications.json"
    if not document:
        result.error("missing_source_verification_artifact", "source_verifications.json is required.", location)
        summary["missing_question_ids"] = sorted(
            question_id for question_id, row in question_by_id.items() if row.get("status") == "active"
        )
        return summary
    if document.get("schema_version") != 1:
        result.error("invalid_source_verification_schema_version", "schema_version must be 1.", location)
    raw_records = document.get("verifications")
    if not isinstance(raw_records, list):
        result.error("invalid_source_verifications", "verifications must be an array.", location)
        raw_records = []
    by_question: dict[str, dict[str, Any]] = {}
    for index, record in enumerate(raw_records, start=1):
        record_location = f"{location}:verifications[{index}]"
        if not isinstance(record, dict):
            result.error("invalid_source_verification", "Verification record must be an object.", record_location)
            continue
        values = {field_name: _string(record.get(field_name)) for field_name in ("question_id", "source_id", "source_version", "verification_state", "verified_at")}
        if not all(values.values()):
            result.error("missing_source_verification_field", "All verification fields are required.", record_location)
            continue
        question_id = values["question_id"]
        if question_id in by_question:
            result.error("duplicate_source_verification", f"Duplicate verification for {question_id}", record_location)
            continue
        by_question[question_id] = values
        try:
            date.fromisoformat(values["verified_at"])
        except ValueError:
            result.error("invalid_verified_at", "verified_at must use YYYY-MM-DD.", record_location)
        question = question_by_id.get(question_id)
        if question is None:
            result.error("unknown_verification_question_id", f"Unknown question_id: {question_id}", record_location)
            continue
        if values["source_id"] != question.get("source_id"):
            result.error("verification_source_id_mismatch", f"source_id does not match {question_id}", record_location)
        current_source = source_by_id.get(question.get("source_id", ""))
        if current_source and values["source_version"] != str(current_source.get("source_version", "")):
            result.error(
                "source_verification_source_version_mismatch",
                f"source_version does not match the current registry for {question_id}",
                record_location,
            )
            summary["source_version_mismatches"].append(question_id)

    for question_id, question in sorted(question_by_id.items()):
        if question.get("status") != "active":
            continue
        record = by_question.get(question_id)
        if record is None:
            result.error("missing_source_verification", f"Active question lacks verification: {question_id}", location)
            summary["missing_question_ids"].append(question_id)
            continue
        current_source = source_by_id.get(question.get("source_id", ""))
        complete = (
            record["verification_state"] == "author_source_verified"
            and record["source_id"] == question.get("source_id")
            and current_source is not None
            and record["source_version"] == str(current_source.get("source_version", ""))
        )
        if record["verification_state"] != "author_source_verified":
            result.error(
                "active_question_not_source_verified",
                f"Active question must be author_source_verified: {question_id}",
                location,
            )
        if complete:
            summary["complete_active_question_count"] += 1
    summary["missing_question_ids"].sort()
    summary["source_version_mismatches"].sort()
    return summary
