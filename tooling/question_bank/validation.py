"""Semantic validation for qualification authoring contracts."""

from __future__ import annotations

import difflib
from datetime import date, timedelta
from pathlib import Path
from typing import Any

from contract import (
    QUESTION_FIELDS,
    REQUIRED_QUESTION_FIELDS,
    QUESTION_ID_PATTERN,
    VALID_STATUSES,
    VALID_USAGE_BASES,
    BankInputs,
    ValidationResult,
    load_bank_inputs,
    question_choices,
    read_csv,
)
from factory_contracts import validate_coverage, validate_source_verifications


def _parse_date(
    value: str,
    field_name: str,
    result: ValidationResult,
    location: str,
) -> date | None:
    if not value:
        return None
    try:
        return date.fromisoformat(value)
    except ValueError:
        result.error(
            "invalid_date",
            f"{field_name} must use YYYY-MM-DD: {value!r}",
            location,
        )
        return None


def _normalized(value: str) -> str:
    return " ".join(value.split()).casefold()


def _as_positive_int(
    value: str,
    field_name: str,
    result: ValidationResult,
    location: str,
) -> int | None:
    try:
        parsed = int(value)
    except ValueError:
        parsed = 0
    if parsed < 1:
        result.error(
            f"invalid_{field_name}",
            f"{field_name} must be a positive integer.",
            location,
        )
        return None
    return parsed


def _metadata_ids(metadata: dict[str, Any]) -> tuple[set[str], set[str]]:
    deck_ids: set[str] = set()
    unit_ids: set[str] = set()
    for deck in metadata.get("decks", []):
        deck_id = str(deck.get("deck_id", "")).strip()
        if deck_id:
            deck_ids.add(deck_id)
        for unit in deck.get("units", []):
            unit_id = str(unit.get("unit_id", "")).strip()
            if unit_id:
                unit_ids.add(unit_id)
    return deck_ids, unit_ids


def _validate_metadata(inputs: BankInputs, result: ValidationResult) -> date:
    metadata = inputs.metadata
    required = (
        "schema_version",
        "app_key",
        "bank_revision",
        "content_as_of",
        "exam_profile_version",
        "question_identity_policy",
    )
    for field_name in required:
        if str(metadata.get(field_name, "")).strip() == "":
            result.error(
                "missing_bank_metadata",
                f"Missing bank metadata field: {field_name}",
                "authoring/bank.json",
            )
    if metadata.get("schema_version") != 2:
        result.error(
            "invalid_schema_version",
            "Authoring bank schema_version must be 2.",
            "authoring/bank.json",
        )
    if metadata.get("question_identity_policy") != "explicit_v1":
        result.error(
            "identity_policy_not_explicit",
            "Qualification banks must use explicit_v1 identity.",
            "authoring/bank.json",
        )
    expected_choice_count = metadata.get("expected_choice_count")
    if expected_choice_count is not None and expected_choice_count not in {3, 4, 5}:
        result.error(
            "invalid_expected_choice_count",
            "expected_choice_count must be 3, 4, or 5 when provided.",
            "authoring/bank.json",
        )
    as_of = _parse_date(
        str(metadata.get("content_as_of", "")),
        "content_as_of",
        result,
        "authoring/bank.json",
    )
    return as_of or date.min


def _validate_sources(
    inputs: BankInputs, result: ValidationResult
) -> dict[str, dict[str, Any]]:
    source_by_id: dict[str, dict[str, Any]] = {}
    for index, source in enumerate(inputs.sources, start=1):
        location = f"authoring/sources.json:sources[{index}]"
        source_id = str(source.get("source_id", "")).strip()
        if not source_id:
            result.error("missing_source_registry_id", "source_id is required.", location)
            continue
        if source_id in source_by_id:
            result.error(
                "duplicate_source_id",
                f"Duplicate source_id: {source_id}",
                location,
            )
        source_by_id[source_id] = source
        for field_name in ("title", "source_version", "usage_basis"):
            if not str(source.get(field_name, "")).strip():
                result.error(
                    "missing_source_registry_field",
                    f"{field_name} is required for {source_id}.",
                    location,
                )
        usage_basis = str(source.get("usage_basis", "")).strip()
        if usage_basis and usage_basis not in VALID_USAGE_BASES:
            result.error(
                "invalid_usage_basis",
                f"Unsupported usage_basis: {usage_basis}",
                location,
            )
        for field_name in ("published_at", "effective_from", "retrieved_at"):
            value = str(source.get(field_name, "")).strip()
            _parse_date(value, field_name, result, location)
    return source_by_id


def _validate_registry(
    inputs: BankInputs, result: ValidationResult
) -> dict[str, dict[str, str]]:
    registry_by_id: dict[str, dict[str, str]] = {}
    for index, row in enumerate(inputs.id_registry, start=2):
        location = f"authoring/question_id_registry.csv:{index}"
        question_id = row.get("question_id", "")
        if not question_id:
            result.error("missing_registry_id", "question_id is required.", location)
            continue
        if question_id in registry_by_id:
            result.error(
                "duplicate_registry_id",
                f"Duplicate registry question_id: {question_id}",
                location,
            )
        registry_by_id[question_id] = row
        if not QUESTION_ID_PATTERN.fullmatch(question_id):
            result.error(
                "invalid_registry_question_id",
                f"Invalid permanent question ID: {question_id}",
                location,
            )
        if row.get("status") not in {"used", "retired"}:
            result.error(
                "invalid_registry_status",
                "Registry status must be used or retired.",
                location,
            )
        if row.get("status") == "retired":
            retired_at = row.get("retired_at", "")
            if not retired_at:
                result.error(
                    "missing_retired_tombstone_date",
                    "Retired registry entries require retired_at.",
                    location,
                )
            else:
                _parse_date(retired_at, "retired_at", result, location)
        replacement_id = row.get("replacement_id", "")
        if replacement_id == question_id:
            result.error(
                "invalid_replacement_id",
                "replacement_id cannot equal question_id.",
                location,
            )
    for question_id, row in registry_by_id.items():
        replacement_id = row.get("replacement_id", "")
        if replacement_id and replacement_id not in registry_by_id:
            result.error(
                "unknown_replacement_id",
                f"replacement_id is absent from the registry: {replacement_id}",
                f"authoring/question_id_registry.csv:{question_id}",
            )
    return registry_by_id


def _validate_identity_and_structure(
    row: dict[str, str],
    question_by_id: dict[str, dict[str, str]],
    deck_ids: set[str],
    unit_ids: set[str],
    result: ValidationResult,
    location: str,
) -> None:
    question_id = row.get("question_id", "")
    if not question_id:
        result.error("missing_question_id", "question_id is required.", location)
        result.error(
            "explicit_identity_missing_id",
            "explicit_v1 identity cannot fall back to a content hash.",
            location,
        )
    elif not QUESTION_ID_PATTERN.fullmatch(question_id):
        result.error(
            "invalid_question_id",
            f"Invalid permanent question ID: {question_id}",
            location,
        )
    if question_id in question_by_id:
        result.error(
            "duplicate_question_id",
            f"Duplicate question_id: {question_id}",
            location,
        )
    elif question_id:
        question_by_id[question_id] = row

    _as_positive_int(
        row.get("question_version", ""),
        "question_version",
        result,
        location,
    )
    status = row.get("status", "")
    if status not in VALID_STATUSES:
        result.error("invalid_status", f"Invalid status: {status!r}", location)

    deck_id = row.get("deck_id", "")
    unit_id = row.get("unit_id", "")
    if not deck_id:
        result.error("missing_deck_id", "deck_id is required.", location)
    elif deck_id not in deck_ids:
        result.error("unknown_deck_id", f"Unknown deck_id: {deck_id}", location)
    if not unit_id:
        result.error("missing_unit_id", "unit_id is required.", location)
    elif unit_id not in unit_ids:
        result.error("unknown_unit_id", f"Unknown unit_id: {unit_id}", location)
    if not row.get("question", ""):
        result.error("empty_question", "question must not be empty.", location)


def _validate_choices(
    row: dict[str, str], result: ValidationResult, location: str, expected_choice_count: int | None
) -> None:
    choices = question_choices(row)
    if len(choices) < 3:
        result.error(
            "insufficient_choices",
            "At least three contiguous choices are required.",
            location,
        )
    first_empty = next(
        (number for number in range(1, 6) if not row.get(f"choice{number}", "")),
        6,
    )
    if any(row.get(f"choice{number}", "") for number in range(first_empty + 1, 6)):
        result.error(
            "non_contiguous_choices",
            "Choices must be contiguous from choice1.",
            location,
        )
    if expected_choice_count is not None and len(choices) != expected_choice_count:
        result.error(
            "unexpected_choice_count",
            f"Question requires exactly {expected_choice_count} choices for this qualification.",
            location,
        )
    normalized_choices = [_normalized(choice) for choice in choices]
    if len(normalized_choices) != len(set(normalized_choices)):
        result.error(
            "duplicate_choices",
            "Choices must be unique after whitespace normalization.",
            location,
        )

    correct_choice = row.get("correct_choice", "")
    if correct_choice not in {"A", "B", "C", "D", "E"}:
        result.error(
            "invalid_correct_choice",
            "correct_choice must be A, B, C, D, or E.",
            location,
        )
    elif ord(correct_choice) - ord("A") >= len(choices):
        result.error(
            "invalid_correct_choice",
            f"correct_choice {correct_choice} points to a missing choice.",
            location,
        )


def _validate_content(
    row: dict[str, str],
    source_by_id: dict[str, dict[str, Any]],
    result: ValidationResult,
    location: str,
) -> None:
    if not row.get("explanation", ""):
        result.error("empty_explanation", "explanation is required.", location)
    source_id = row.get("source_id", "")
    if not source_id:
        result.error("missing_source_id", "source_id is required.", location)
    elif source_id not in source_by_id:
        result.error(
            "unresolved_source_id",
            f"source_id is not in the source registry: {source_id}",
            location,
        )
    if not row.get("source_locator", ""):
        result.error("missing_source_locator", "source_locator is required.", location)

    for field_name in ("difficulty", "importance"):
        value = _as_positive_int(
            row.get(field_name, ""), field_name, result, location
        )
        if value is not None and value not in {1, 2, 3}:
            result.error(
                f"invalid_{field_name}",
                f"{field_name} must be 1, 2, or 3.",
                location,
            )
    if row.get("is_free", "") not in {"true", "false"}:
        result.error("invalid_is_free", "is_free must be true or false.", location)


def _validate_dates(
    row: dict[str, str],
    as_of: date,
    review_due_days: int,
    result: ValidationResult,
    location: str,
) -> None:
    valid_from = _parse_date(
        row.get("valid_from", ""), "valid_from", result, location
    )
    valid_until = _parse_date(
        row.get("valid_until", ""), "valid_until", result, location
    )
    last_reviewed = _parse_date(
        row.get("last_reviewed_at", ""),
        "last_reviewed_at",
        result,
        location,
    )
    if valid_from and valid_until and valid_from > valid_until:
        result.error(
            "invalid_validity_range",
            "valid_from must not be after valid_until.",
            location,
        )
    if row.get("status") != "active":
        return
    if last_reviewed is None:
        result.error(
            "active_missing_last_reviewed_at",
            "Active questions require last_reviewed_at.",
            location,
        )
    if valid_from and valid_from > as_of:
        result.error(
            "active_question_not_yet_valid",
            f"Active question starts after content_as_of: {valid_from}",
            location,
        )
    if valid_until and valid_until < as_of:
        result.error(
            "expired_active_question",
            f"Active question expired before content_as_of: {valid_until}",
            location,
        )
    if (
        last_reviewed
        and review_due_days > 0
        and last_reviewed + timedelta(days=review_due_days) < as_of
    ):
        result.warning(
            "review_overdue",
            f"Review is older than {review_due_days} days.",
            location,
        )


def _validate_registry_membership(
    row: dict[str, str],
    registry_by_id: dict[str, dict[str, str]],
    result: ValidationResult,
    location: str,
) -> None:
    question_id = row.get("question_id", "")
    registry_row = registry_by_id.get(question_id)
    if question_id and registry_row is None:
        result.error(
            "unregistered_question_id",
            f"question_id is absent from the permanent ID registry: {question_id}",
            location,
        )
        return
    if not registry_row:
        return
    registry_status = registry_row.get("status")
    status = row.get("status")
    if registry_status == "retired" and status != "retired":
        result.error(
            "retired_id_reuse",
            f"Retired question ID cannot be reused: {question_id}",
            location,
        )
    if status == "retired" and registry_status != "retired":
        result.error(
            "missing_retired_tombstone",
            f"Retired question requires a retired registry tombstone: {question_id}",
            location,
        )


def _validate_questions(
    inputs: BankInputs,
    result: ValidationResult,
    source_by_id: dict[str, dict[str, Any]],
    registry_by_id: dict[str, dict[str, str]],
    as_of: date,
) -> dict[str, dict[str, str]]:
    question_by_id: dict[str, dict[str, str]] = {}
    deck_ids, unit_ids = _metadata_ids(inputs.metadata)
    review_due_days = int(inputs.metadata.get("review_due_days", 0) or 0)
    for index, row in enumerate(inputs.questions, start=2):
        location = f"authoring/questions.csv:{index}"
        _validate_identity_and_structure(
            row, question_by_id, deck_ids, unit_ids, result, location
        )
        expected = inputs.metadata.get("expected_choice_count")
        _validate_choices(
            row,
            result,
            location,
            expected if isinstance(expected, int) and not isinstance(expected, bool) else None,
        )
        _validate_content(row, source_by_id, result, location)
        _validate_dates(row, as_of, review_due_days, result, location)
        _validate_registry_membership(row, registry_by_id, result, location)
    return question_by_id


def _validate_released_contract(
    inputs: BankInputs,
    result: ValidationResult,
    question_by_id: dict[str, dict[str, str]],
) -> None:
    registry_by_id = {row["question_id"]: row for row in inputs.id_registry}
    released_ids = {
        str(released.get("question_id", "")).strip()
        for released in inputs.released_questions
    }
    for released in inputs.released_questions:
        question_id = str(released.get("question_id", "")).strip()
        registry_row = registry_by_id.get(question_id)
        if registry_row is None:
            result.error(
                "released_question_missing_registry_entry",
                "Released question is absent from the permanent ID registry.",
                f"authoring/released_questions.json:{question_id}",
            )
        elif not registry_row.get("first_used_bank_revision", ""):
            result.error(
                "released_question_missing_first_used_bank_revision",
                "Released question requires its immutable first_used_bank_revision.",
                f"authoring/question_id_registry.csv:{question_id}",
            )
        current = question_by_id.get(question_id)
        if current is None:
            continue
        location = f"authoring/questions.csv:{question_id}"
        if current.get("correct_choice") != str(released.get("correct_choice", "")):
            result.error(
                "released_correct_choice_changed",
                "A released question changed its correct choice; issue a new question ID.",
                location,
            )

        changed_fields: list[str] = []
        old_question = str(released.get("question", ""))
        new_question = current.get("question", "")
        if old_question and old_question != new_question:
            ratio = difflib.SequenceMatcher(
                None, _normalized(old_question), _normalized(new_question)
            ).ratio()
            if ratio < 0.8:
                result.warning(
                    "question_text_changed_significantly",
                    "Released question text changed significantly.",
                    location,
                )
            changed_fields.append("question")

        released_choices = released.get("choices")
        if isinstance(released_choices, list):
            old_choices = [str(choice) for choice in released_choices]
            if old_choices != question_choices(current):
                result.warning(
                    "released_choices_changed",
                    f"Released choices changed for {question_id}.",
                    location,
                )
                changed_fields.append("choices")

        warning_codes = {
            "source_id": "source_changed",
            "difficulty": "difficulty_changed",
            "importance": "importance_changed",
            "is_free": "free_paid_changed",
        }
        for field_name, code in warning_codes.items():
            if str(released.get(field_name, "")) != current.get(field_name, ""):
                result.warning(
                    code,
                    f"Released {field_name} changed for {question_id}.",
                    location,
                )
                changed_fields.append(field_name)

        try:
            old_version = int(released.get("question_version", 0))
            new_version = int(current.get("question_version", 0))
        except (TypeError, ValueError):
            old_version = new_version = 0
        if changed_fields and new_version <= old_version:
            result.warning(
                "question_version_not_incremented",
                "Released metadata changed without incrementing question_version.",
                location,
            )

    for question_id, registry_row in registry_by_id.items():
        if (
            question_id not in released_ids
            and registry_row.get("first_used_bank_revision", "")
            and registry_row.get("status") != "retired"
        ):
            result.error(
                "unreleased_question_has_first_used_bank_revision",
                "An unreleased question must not have first_used_bank_revision.",
                f"authoring/question_id_registry.csv:{question_id}",
            )


def _validate_similar_questions(
    question_by_id: dict[str, dict[str, str]], result: ValidationResult
) -> None:
    active = [
        (question_id, row)
        for question_id, row in sorted(question_by_id.items())
        if row.get("status") == "active"
    ]
    for index, (left_id, left) in enumerate(active):
        for right_id, right in active[index + 1 :]:
            ratio = difflib.SequenceMatcher(
                None,
                _normalized(left.get("question", "")),
                _normalized(right.get("question", "")),
            ).ratio()
            if ratio >= 0.9:
                result.warning(
                    "similar_questions",
                    f"Possibly similar questions: {left_id} and {right_id}",
                )


def validate_bank(bank_root: Path, *, check_generated: bool = False) -> ValidationResult:
    result = ValidationResult()
    question_header, _ = read_csv(bank_root / "authoring" / "questions.csv")
    missing_headers = [field for field in REQUIRED_QUESTION_FIELDS if field not in question_header]
    if missing_headers:
        result.error(
            "missing_question_columns",
            f"Missing question CSV columns: {', '.join(missing_headers)}",
            "authoring/questions.csv",
        )

    registry_header, _ = read_csv(bank_root / "authoring" / "question_id_registry.csv")
    required_registry_headers = {
        "question_id",
        "status",
        "first_used_bank_revision",
        "retired_at",
        "replacement_id",
        "notes",
    }
    missing_registry_headers = sorted(required_registry_headers - set(registry_header))
    if missing_registry_headers:
        result.error(
            "missing_registry_columns",
            f"Missing registry CSV columns: {', '.join(missing_registry_headers)}",
            "authoring/question_id_registry.csv",
        )

    inputs = load_bank_inputs(bank_root)
    as_of = _validate_metadata(inputs, result)
    source_by_id = _validate_sources(inputs, result)
    registry_by_id = _validate_registry(inputs, result)
    question_by_id = _validate_questions(
        inputs, result, source_by_id, registry_by_id, as_of
    )
    _, unit_ids = _metadata_ids(inputs.metadata)
    validate_coverage(inputs, question_by_id, unit_ids, result)
    validate_source_verifications(inputs, question_by_id, source_by_id, result)
    _validate_released_contract(inputs, result, question_by_id)
    _validate_similar_questions(question_by_id, result)
    if check_generated and result.is_valid:
        from generation import validate_generated_files

        validate_generated_files(inputs, result)
    return result
