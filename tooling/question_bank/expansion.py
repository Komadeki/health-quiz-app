from __future__ import annotations

import csv
import json
import re
from collections import Counter
from datetime import date
from pathlib import Path
from typing import Any

from ai_governance import ai_acceptance_errors
from contract import QUESTION_ID_PATTERN, question_choices
from validation import validate_bank

ALLOWED_STATES = {
    "DRAFT", "AI_PRE_ACCEPT", "HUMAN_ACCEPT", "READY_FOR_ID", "ID_ALLOCATED",
    "INTEGRATED", "VERIFIED", "RELEASED", "REWORK", "HOLD", "REJECT",
}
HUMAN_DECISIONS = {"ACCEPT", "REWORK", "REJECT", "HOLD"}
PRODUCTION_STATES = {"ID_ALLOCATED", "INTEGRATED", "VERIFIED", "RELEASED"}
POST_ACCEPT_STATES = {"READY_FOR_ID", "ID_ALLOCATED", "INTEGRATED", "VERIFIED", "RELEASED"}
REQUIRED_FILES = ("batch.json", "candidates.csv", "reviews.csv")
CANDIDATE_COLUMNS = (
    "candidate_id", "state", "unit_id", "domain", "knowledge_target_id", "family",
    "question", "choice1", "choice2", "choice3", "choice4", "choice5", "proposed_correct",
    "explanation", "source_id", "source_version", "source_locator",
    "answer_defining_proposition", "tested_misconception", "reasoning_path",
    "collision_note", "permanent_question_id",
)
OPTIONAL_CANDIDATE_COLUMNS = frozenset({"choice5"})
REQUIRED_CANDIDATE_COLUMNS = tuple(
    column for column in CANDIDATE_COLUMNS if column not in OPTIONAL_CANDIDATE_COLUMNS
)
REVIEW_COLUMNS = (
    "candidate_id", "review_round", "decision", "reason_code", "reason_detail",
    "collided_question_id", "collided_candidate_id", "reviewed_at", "reviewer_role",
    "resume_condition",
)
TARGET_DECISION_FIELDS = (
    "decision_id", "previous_approved_target", "current_released_count",
    "proposed_target_min", "proposed_target_max", "approved_new_target", "rationale",
    "decision_date", "evidence",
)
SCHEMA_VERSION = "1.0"
BATCH_ID_PATTERN = re.compile(r"^B[1-9][0-9]*$")

CANDIDATE_CANONICAL_FIELDS = (
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
)


def _read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), [
            {key: (value or "").strip() for key, value in row.items()}
            for row in reader
        ]


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected object: {path}")
    return value


def _nonempty(row: dict[str, str], *keys: str) -> bool:
    return any((row.get(key) or "").strip() for key in keys)


def _review_state(decision: str) -> str:
    return {"ACCEPT": "HUMAN_ACCEPT", "REWORK": "REWORK", "REJECT": "REJECT", "HOLD": "HOLD"}[decision]


def _normalized(value: str) -> str:
    """Match the canonical Question validator's choice normalization."""
    return " ".join(value.split()).casefold()


def _bank_root(batch_dir: Path) -> Path | None:
    if batch_dir.parent.name != "batches" or batch_dir.parent.parent.name != "authoring":
        return None
    return batch_dir.parent.parent.parent


def _latest_human_reviews(reviews: list[dict[str, str]]) -> dict[str, dict[str, str]]:
    latest: dict[str, dict[str, str]] = {}
    for row in reviews:
        if row.get("reviewer_role", "").strip() != "HUMAN":
            continue
        candidate_id = row.get("candidate_id", "").strip()
        try:
            round_number = int(row.get("review_round", ""))
        except ValueError:
            continue
        prior = latest.get(candidate_id)
        if prior is None or round_number > int(prior["review_round"]):
            latest[candidate_id] = row
    return latest


def _canonical_evidence(bank_root: Path, errors: list[str]) -> dict[str, Any]:
    authoring = bank_root / "authoring"
    evidence: dict[str, Any] = {
        "registry_ids": set(),
        "prerelease_registry_ids": set(),
        "released_registry_ids": set(),
        "question_ids": set(),
        "verified_ids": set(),
        "released_ids": set(),
        "generated_ids": set(),
        "registry_by_id": {},
        "question_by_id": {},
        "source_by_id": {},
        "released_by_id": {},
        "bank_app_key": None,
        "expected_choice_count": None,
    }
    try:
        bank = _read_json(authoring / "bank.json")
        evidence["bank_app_key"] = bank.get("app_key")
        evidence["expected_choice_count"] = bank.get("expected_choice_count")
        _, registry = _read_csv(authoring / "question_id_registry.csv")
        _, questions = _read_csv(authoring / "questions.csv")
        sources = _read_json(authoring / "sources.json").get("sources", [])
        released = _read_json(authoring / "released_questions.json").get("released_questions", [])
        verifications = _read_json(authoring / "source_verifications.json").get("verifications", [])
        runtime_output = str(bank.get("runtime_output", "")).strip()
        if not runtime_output:
            raise ValueError("canonical bank.json missing runtime_output")
        runtime = _read_json(bank_root / runtime_output)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        errors.append(f"canonical evidence unavailable: {exc}")
        return evidence

    registry_by_id: dict[str, list[dict[str, str]]] = {}
    for row in registry:
        if row.get("question_id"):
            registry_by_id.setdefault(row["question_id"], []).append(row)
    evidence["registry_ids"] = set(registry_by_id)
    evidence["registry_by_id"] = registry_by_id
    evidence["prerelease_registry_ids"] = {
        question_id
        for question_id, rows in registry_by_id.items()
        if (
            len(rows) == 1
            and rows[0].get("status") == "used"
            and not rows[0].get("retired_at")
            and not rows[0].get("first_used_bank_revision")
        )
    }
    evidence["released_registry_ids"] = {
        question_id
        for question_id, rows in registry_by_id.items()
        if (
            len(rows) == 1
            and rows[0].get("status") == "used"
            and not rows[0].get("retired_at")
            and bool(rows[0].get("first_used_bank_revision"))
        )
    }

    question_rows_by_id: dict[str, list[dict[str, str]]] = {}
    for row in questions:
        if row.get("question_id"):
            question_rows_by_id.setdefault(row["question_id"], []).append(row)
    question_by_id = {
        question_id: rows[0]
        for question_id, rows in question_rows_by_id.items()
        if len(rows) == 1
    }
    evidence["question_ids"] = set(question_by_id)
    evidence["question_by_id"] = question_by_id

    source_by_id = {
        str(source.get("source_id", "")).strip(): source
        for source in sources
        if isinstance(source, dict) and str(source.get("source_id", "")).strip()
    }
    evidence["source_by_id"] = source_by_id
    released_rows_by_id: dict[str, list[dict[str, Any]]] = {}
    for row in released:
        if not isinstance(row, dict):
            continue
        question_id = str(row.get("question_id", "")).strip()
        if question_id:
            released_rows_by_id.setdefault(question_id, []).append(row)
    released_by_id = {
        question_id: rows[0]
        for question_id, rows in released_rows_by_id.items()
        if len(rows) == 1
    }
    evidence["released_by_id"] = released_by_id
    evidence["released_ids"] = {
        str(row.get("question_id", "")).strip()
        for row in released if isinstance(row, dict) and str(row.get("question_id", "")).strip()
    }
    verification_rows_by_id: dict[str, list[dict[str, Any]]] = {}
    for row in verifications:
        if not isinstance(row, dict):
            continue
        question_id = str(row.get("question_id", "")).strip()
        if question_id:
            verification_rows_by_id.setdefault(question_id, []).append(row)
    verified_ids: set[str] = set()
    for question_id, rows in verification_rows_by_id.items():
        if len(rows) != 1 or question_id not in question_by_id:
            continue
        row = rows[0]
        question = question_by_id[question_id]
        source_id = str(row.get("source_id", "")).strip()
        source = source_by_id.get(source_id)
        verified_at = str(row.get("verified_at", "")).strip()
        try:
            date.fromisoformat(verified_at)
        except ValueError:
            continue
        if (
            row.get("verification_state") == "author_source_verified"
            and source_id == question.get("source_id")
            and source is not None
            and str(row.get("source_version", "")).strip()
            == str(source.get("source_version", "")).strip()
        ):
            verified_ids.add(question_id)
    evidence["verified_ids"] = verified_ids
    generated_ids: set[str] = set()
    for deck in runtime.get("decks", []):
        if not isinstance(deck, dict):
            continue
        for unit in deck.get("units", []):
            if not isinstance(unit, dict):
                continue
            for card in unit.get("cards", []):
                if isinstance(card, dict) and str(card.get("stableId", "")).strip():
                    generated_ids.add(str(card["stableId"]).strip())
    evidence["generated_ids"] = generated_ids
    return evidence


def _validate_candidate_binding(
    candidate: dict[str, str],
    canonical_question: dict[str, str],
    source_by_id: dict[str, dict[str, Any]],
    errors: list[str],
) -> None:
    candidate_id = candidate["candidate_id"]
    state = candidate["state"]
    for candidate_field, canonical_field in CANDIDATE_CANONICAL_FIELDS:
        if candidate.get(candidate_field, "") != canonical_question.get(canonical_field, ""):
            errors.append(
                f"{state} candidate {candidate_id} canonical content mismatch: {candidate_field}"
            )

    source = source_by_id.get(candidate["source_id"])
    current_source_version = (
        str(source.get("source_version", "")).strip() if source is not None else ""
    )
    if candidate["source_version"] != current_source_version:
        errors.append(
            f"{state} candidate {candidate_id} canonical content mismatch: source_version"
        )


def _released_identity_matches(
    canonical_question: dict[str, str], released: dict[str, Any]
) -> bool:
    try:
        released_version = int(released.get("question_version", 0))
        canonical_version = int(canonical_question.get("question_version", ""))
    except (TypeError, ValueError):
        return False
    released_choices = released.get("choices")
    return (
        str(released.get("question_id", "")).strip()
        == canonical_question.get("question_id", "")
        and released_version == canonical_version
        and str(released.get("question", "")) == canonical_question.get("question", "")
        and isinstance(released_choices, list)
        and [str(choice) for choice in released_choices] == question_choices(canonical_question)
        and str(released.get("correct_choice", ""))
        == canonical_question.get("correct_choice", "")
    )


def validate_expansion_batch(batch_dir: Path | str) -> list[str]:
    batch_dir = Path(batch_dir)
    errors: list[str] = []
    for name in REQUIRED_FILES:
        if not (batch_dir / name).is_file():
            errors.append(f"missing required file: {name}")
    if errors:
        return errors

    try:
        batch = _read_json(batch_dir / "batch.json")
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        return [f"invalid batch.json: {exc}"]

    for key in (
        "schema_version", "app_key", "batch_id", "directory_slug", "baseline_sha", "batch_status",
        "expansion_trigger", "evidence", "target_size_decisions", "planned_scope",
        "coverage_limit_decisions",
    ):
        if key not in batch:
            errors.append(f"batch.json missing field: {key}")

    if batch.get("schema_version") != SCHEMA_VERSION:
        errors.append(f"unsupported schema_version: {batch.get('schema_version')!r}")
    if batch.get("directory_slug") != batch_dir.name:
        errors.append("directory_slug must match batch directory name")
    batch_id = str(batch.get("batch_id", "")).strip()
    if not BATCH_ID_PATTERN.fullmatch(batch_id):
        errors.append(f"invalid logical batch_id: {batch_id!r}")

    bank_root = _bank_root(batch_dir)
    canonical: dict[str, Any] | None = None
    if bank_root is None:
        errors.append("batch directory must be under authoring/batches/<directory_slug>")
    else:
        canonical = _canonical_evidence(bank_root, errors)
        if batch.get("app_key") != bank_root.name:
            errors.append("app_key must match qualification bank directory")
        if canonical.get("bank_app_key") != batch.get("app_key"):
            errors.append("app_key must match canonical bank.json app_key")
        duplicate_dirs: list[str] = []
        for sibling in batch_dir.parent.iterdir():
            if sibling == batch_dir or not sibling.is_dir() or not (sibling / "batch.json").is_file():
                continue
            try:
                sibling_batch = _read_json(sibling / "batch.json")
            except (OSError, ValueError, json.JSONDecodeError):
                continue
            if str(sibling_batch.get("batch_id", "")).strip() == batch_id:
                duplicate_dirs.append(sibling.name)
        if duplicate_dirs:
            errors.append(
                f"duplicate logical batch_id {batch_id!r} also used by: {','.join(sorted(duplicate_dirs))}"
            )

    decisions = batch.get("target_size_decisions")
    if not isinstance(decisions, list) or not decisions:
        errors.append("target_size_decisions must be a non-empty list")
    else:
        seen_decisions: set[str] = set()
        prior_approved: int | None = None
        prior_decision_date: date | None = None
        for i, decision in enumerate(decisions):
            if not isinstance(decision, dict):
                errors.append(f"target_size_decisions[{i}] must be an object")
                continue
            missing = [field for field in TARGET_DECISION_FIELDS if field not in decision]
            if missing:
                errors.append(f"target_size_decisions[{i}] missing: {','.join(missing)}")
                continue
            decision_id = str(decision.get("decision_id", "")).strip()
            if not decision_id or decision_id in seen_decisions:
                errors.append(f"invalid or duplicate target decision_id: {decision_id!r}")
            seen_decisions.add(decision_id)
            numeric = [
                decision.get("previous_approved_target"), decision.get("current_released_count"),
                decision.get("proposed_target_min"), decision.get("proposed_target_max"),
                decision.get("approved_new_target"),
            ]
            if not all(isinstance(value, int) and value >= 0 for value in numeric):
                errors.append(f"target decision {decision_id} has invalid numeric target values")
            else:
                low = decision["proposed_target_min"]
                high = decision["proposed_target_max"]
                approved = decision["approved_new_target"]
                if low > high:
                    errors.append(f"target decision {decision_id} has min greater than max")
                if not low <= approved <= high:
                    errors.append(f"target decision {decision_id} approved target must be within proposed range")
                if prior_approved is not None and decision["previous_approved_target"] != prior_approved:
                    errors.append(f"target decision {decision_id} breaks approved-target chain continuity")
                prior_approved = approved
            if not str(decision.get("rationale", "")).strip() or not str(decision.get("evidence", "")).strip():
                errors.append(f"target decision {decision_id} requires rationale and evidence")
            decision_date_value = str(decision.get("decision_date", ""))
            parsed_decision_date: date | None = None
            if re.fullmatch(r"\d{4}-\d{2}-\d{2}", decision_date_value):
                try:
                    parsed_decision_date = date.fromisoformat(decision_date_value)
                except ValueError:
                    pass
            if parsed_decision_date is None:
                errors.append(f"target decision {decision_id} has invalid decision_date")
            elif prior_decision_date is not None and parsed_decision_date < prior_decision_date:
                errors.append(f"target decision {decision_id} decision_date moves backward")
            if parsed_decision_date is not None:
                prior_decision_date = parsed_decision_date

    coverage_limits = batch.get("coverage_limit_decisions", [])
    if not isinstance(coverage_limits, list):
        errors.append("coverage_limit_decisions must be a list")
    else:
        for i, item in enumerate(coverage_limits):
            if not isinstance(item, dict):
                errors.append(f"coverage_limit_decisions[{i}] must be an object")
                continue
            for field in ("decision_id", "status", "scope", "evidence"):
                if not str(item.get(field, "")).strip():
                    errors.append(f"coverage_limit_decisions[{i}] missing {field}")

    planned_scope = batch.get("planned_scope")
    known_rejected_ids: set[str] = set()
    if isinstance(planned_scope, dict):
        raw_rejected = planned_scope.get("known_rejected_ids", [])
        if isinstance(raw_rejected, list):
            known_rejected_ids = {str(value).strip() for value in raw_rejected if str(value).strip()}
        else:
            errors.append("planned_scope.known_rejected_ids must be a list when present")
    elif planned_scope is not None:
        errors.append("planned_scope must be an object")

    candidate_fields, candidates = _read_csv(batch_dir / "candidates.csv")
    review_fields, reviews = _read_csv(batch_dir / "reviews.csv")
    missing_candidate_columns = [c for c in REQUIRED_CANDIDATE_COLUMNS if c not in candidate_fields]
    missing_review_columns = [c for c in REVIEW_COLUMNS if c not in review_fields]
    if missing_candidate_columns:
        errors.append("candidates.csv missing columns: " + ",".join(missing_candidate_columns))
    if missing_review_columns:
        errors.append("reviews.csv missing columns: " + ",".join(missing_review_columns))
    if missing_candidate_columns or missing_review_columns:
        return errors

    candidate_ids = [row["candidate_id"] for row in candidates]
    duplicates = sorted(key for key, count in Counter(candidate_ids).items() if key and count > 1)
    if duplicates:
        errors.append("duplicate candidate_id: " + ",".join(duplicates))
    if any(not candidate_id for candidate_id in candidate_ids):
        errors.append("candidate_id must not be empty")

    reviews_by_candidate: dict[str, list[dict[str, str]]] = {}
    prior_round_by_candidate: dict[str, int] = {}
    seen_rounds_by_candidate: dict[str, set[int]] = {}
    for row in reviews:
        candidate_id = row["candidate_id"]
        reviews_by_candidate.setdefault(candidate_id, []).append(row)
        decision = row["decision"]
        if decision not in HUMAN_DECISIONS:
            errors.append(f"invalid review decision for {candidate_id}: {decision}")
        if row["reviewer_role"] != "HUMAN":
            errors.append(f"reviewer_role must be HUMAN for {candidate_id}")
        try:
            round_number = int(row["review_round"])
            if round_number < 1:
                raise ValueError
            seen = seen_rounds_by_candidate.setdefault(candidate_id, set())
            if round_number in seen:
                errors.append(f"duplicate review_round for {candidate_id}: {round_number}")
            seen.add(round_number)
            prior_round = prior_round_by_candidate.get(candidate_id)
            if prior_round is not None and round_number <= prior_round:
                errors.append(f"review_round must be strictly increasing for {candidate_id}")
            prior_round_by_candidate[candidate_id] = round_number
        except ValueError:
            errors.append(f"invalid review_round for {candidate_id}: {row['review_round']}")
        if decision == "REJECT" and not _nonempty(row, "reason_code", "reason_detail"):
            errors.append(f"REJECT review requires reason for {candidate_id}")
        if decision == "HOLD":
            if not _nonempty(row, "reason_code", "reason_detail"):
                errors.append(f"HOLD review requires reason for {candidate_id}")
            if not row["resume_condition"]:
                errors.append(f"HOLD review requires resume_condition for {candidate_id}")

    latest_human_reviews = _latest_human_reviews(reviews)
    permanent_to_candidate: dict[str, str] = {}
    for row in candidates:
        candidate_id = row["candidate_id"]
        state = row["state"]
        if state not in ALLOWED_STATES:
            errors.append(f"invalid candidate state for {candidate_id}: {state}")
            continue
        if candidate_id in known_rejected_ids and state != "REJECT":
            errors.append(f"known rejected candidate_id reused: {candidate_id}")

        content_required = state not in {"DRAFT", "REWORK", "HOLD", "REJECT"}
        if content_required:
            for field in (
                "unit_id", "question", "choice1", "choice2", "proposed_correct",
                "explanation", "source_id", "source_version", "source_locator",
            ):
                if not row[field]:
                    errors.append(f"{state} candidate {candidate_id} missing {field}")

        if content_required:
            choices = [row.get(f"choice{i}", "") for i in range(1, 6)]
            populated = [index for index, value in enumerate(choices, start=1) if value]
            expected_choice_count = canonical.get("expected_choice_count") if canonical else None
            allowed_counts = {expected_choice_count} if isinstance(expected_choice_count, int) else {3, 4, 5}
            if len(populated) not in allowed_counts or populated != list(range(1, len(populated) + 1)):
                expected_text = str(expected_choice_count) if isinstance(expected_choice_count, int) else "3-4 contiguous choices or 5"
                errors.append(f"{state} candidate {candidate_id} requires {expected_text} contiguous choices")
            normalized_choices = [_normalized(choice) for choice in choices if choice]
            if len(normalized_choices) != len(set(normalized_choices)):
                errors.append(
                    f"{state} candidate {candidate_id} requires unique normalized choices"
                )

        correct = row["proposed_correct"]
        if correct:
            choice_map = {"A": "choice1", "B": "choice2", "C": "choice3", "D": "choice4", "E": "choice5"}
            if correct not in choice_map or not row.get(choice_map.get(correct, "choice1"), ""):
                errors.append(f"proposed_correct does not reference an existing choice for {candidate_id}")

        permanent_id = row["permanent_question_id"]
        if state in PRODUCTION_STATES:
            if not permanent_id:
                errors.append(f"{state} candidate {candidate_id} requires permanent_question_id")
        elif permanent_id:
            errors.append(f"pre-ID candidate {candidate_id} must not have permanent_question_id")
        if permanent_id:
            if not QUESTION_ID_PATTERN.fullmatch(permanent_id):
                errors.append(f"invalid permanent_question_id for {candidate_id}: {permanent_id}")
            prior = permanent_to_candidate.get(permanent_id)
            if prior and prior != candidate_id:
                errors.append(f"duplicate permanent ID mapping: {permanent_id}")
            permanent_to_candidate[permanent_id] = candidate_id

        latest = latest_human_reviews.get(candidate_id)
        latest_decision = latest["decision"] if latest else ""
        human_states = {"HUMAN_ACCEPT", "REWORK", "HOLD", "REJECT"}
        if state in human_states:
            if latest is None:
                errors.append(f"{state} candidate {candidate_id} has no Human review")
            elif latest_decision in HUMAN_DECISIONS and _review_state(latest_decision) != state:
                errors.append(f"latest Human review conflicts with candidate state for {candidate_id}")
        elif state in POST_ACCEPT_STATES:
            has_human_accept = latest is not None and latest_decision == "ACCEPT"
            if not has_human_accept:
                ai_errors = ai_acceptance_errors(batch_dir, row)
                if ai_errors:
                    errors.append(
                        f"{state} candidate {candidate_id} requires latest Human ACCEPT "
                        "or valid AI-governed acceptance"
                    )
                    errors.extend(
                        f"{state} candidate {candidate_id} AI governance: {error}"
                        for error in ai_errors
                    )

        if permanent_id and canonical is not None:
            registry_ids = canonical["registry_ids"]
            prerelease_registry_ids = canonical["prerelease_registry_ids"]
            released_registry_ids = canonical["released_registry_ids"]
            question_ids = canonical["question_ids"]
            verified_ids = canonical["verified_ids"]
            released_ids = canonical["released_ids"]
            generated_ids = canonical["generated_ids"]
            registry_by_id = canonical["registry_by_id"]
            question_by_id = canonical["question_by_id"]
            if state in PRODUCTION_STATES and permanent_id not in registry_ids:
                errors.append(f"{state} candidate {candidate_id} permanent ID is absent from canonical registry")
            elif state in {"ID_ALLOCATED", "INTEGRATED", "VERIFIED"}:
                if permanent_id not in prerelease_registry_ids:
                    registry_rows = registry_by_id.get(permanent_id, [])
                    if (
                        len(registry_rows) == 1
                        and registry_rows[0].get("status") == "used"
                        and not registry_rows[0].get("retired_at")
                        and registry_rows[0].get("first_used_bank_revision")
                    ):
                        errors.append(
                            f"{state} candidate {candidate_id} requires blank "
                            "first_used_bank_revision"
                        )
                    else:
                        errors.append(
                            f"{state} candidate {candidate_id} permanent ID is not a valid "
                            "pre-release used registry entry"
                        )
            elif state == "RELEASED" and permanent_id not in released_registry_ids:
                registry_rows = registry_by_id.get(permanent_id, [])
                if (
                    len(registry_rows) == 1
                    and registry_rows[0].get("status") == "used"
                    and not registry_rows[0].get("retired_at")
                    and not registry_rows[0].get("first_used_bank_revision")
                ):
                    errors.append(
                        f"RELEASED candidate {candidate_id} requires non-empty "
                        "first_used_bank_revision"
                    )
                else:
                    errors.append(
                        f"RELEASED candidate {candidate_id} permanent ID is not a valid "
                        "released used registry entry"
                    )
            if state in {"INTEGRATED", "VERIFIED", "RELEASED"} and permanent_id not in question_ids:
                errors.append(f"{state} candidate {candidate_id} permanent ID is absent from canonical questions")
            elif state in {"INTEGRATED", "VERIFIED", "RELEASED"}:
                canonical_question = question_by_id[permanent_id]
                expected_status = "active" if state == "RELEASED" else "draft"
                if canonical_question.get("status") != expected_status:
                    errors.append(
                        f"{state} candidate {candidate_id} requires canonical status {expected_status}"
                    )
                _validate_candidate_binding(
                    row,
                    canonical_question,
                    canonical["source_by_id"],
                    errors,
                )
            if state in {"VERIFIED", "RELEASED"} and permanent_id not in verified_ids:
                errors.append(f"{state} candidate {candidate_id} lacks canonical source verification")
            if state == "RELEASED":
                if permanent_id not in released_ids:
                    errors.append(f"RELEASED candidate {candidate_id} is absent from released snapshot")
                elif permanent_id in question_by_id and not _released_identity_matches(
                    question_by_id[permanent_id], canonical["released_by_id"].get(permanent_id, {})
                ):
                    errors.append(
                        f"RELEASED candidate {candidate_id} released snapshot identity mismatch"
                    )
                if permanent_id not in generated_ids:
                    errors.append(f"RELEASED candidate {candidate_id} is absent from generated runtime")

    production_validation_state = ""
    if canonical is not None and any(row["state"] == "RELEASED" for row in candidates):
        production_validation_state = "RELEASED"
    elif canonical is not None and any(row["state"] == "VERIFIED" for row in candidates):
        production_validation_state = "VERIFIED"
    if production_validation_state and bank_root is not None:
        try:
            canonical_validation = validate_bank(
                bank_root,
                check_generated=production_validation_state == "RELEASED",
            )
        except (OSError, ValueError, json.JSONDecodeError) as exc:
            errors.append(
                f"{production_validation_state} canonical bank validation failed: {exc}"
            )
        else:
            if canonical_validation.errors:
                codes = ",".join(sorted({issue.code for issue in canonical_validation.errors}))
                errors.append(
                    f"{production_validation_state} canonical bank validation failed: {codes}"
                )

    candidate_set = set(candidate_ids)
    for candidate_id in reviews_by_candidate:
        if candidate_id not in candidate_set:
            errors.append(f"review references unknown candidate_id: {candidate_id}")

    return errors


def build_status_report(batch_dir: Path | str) -> dict[str, Any]:
    batch_dir = Path(batch_dir)
    batch = _read_json(batch_dir / "batch.json")
    _, candidates = _read_csv(batch_dir / "candidates.csv")
    _, reviews = _read_csv(batch_dir / "reviews.csv")
    state_counts = Counter(row["state"] for row in candidates)
    latest_human = _latest_human_reviews(reviews)
    latest_human_counts = Counter(row["decision"] for row in latest_human.values())
    decisions = batch.get("target_size_decisions") or []
    validation_errors = validate_expansion_batch(batch_dir)
    blockers = list(batch.get("migration_blockers") or [])
    blockers.extend(validation_errors)
    actionable = [
        state for state in (
            "DRAFT", "AI_PRE_ACCEPT", "REWORK", "HOLD", "HUMAN_ACCEPT",
            "READY_FOR_ID", "ID_ALLOCATED", "INTEGRATED", "VERIFIED",
        ) if state_counts.get(state)
    ]
    return {
        "batch_id": batch.get("batch_id"),
        "batch_status": batch.get("batch_status"),
        "current_target_decision": (
            decisions[-1] if decisions and not validation_errors else None
        ),
        "current_target_decision_status": (
            "valid" if decisions and not validation_errors else "validation_invalid"
        ),
        "count_by_candidate_state": dict(sorted(state_counts.items())),
        "human_accept_count": latest_human_counts.get("ACCEPT", 0),
        "reject_count": latest_human_counts.get("REJECT", 0),
        "hold_count": latest_human_counts.get("HOLD", 0),
        "ready_for_id_count": state_counts.get("READY_FOR_ID", 0),
        "id_allocated_count": state_counts.get("ID_ALLOCATED", 0),
        "integrated_count": state_counts.get("INTEGRATED", 0),
        "verified_count": state_counts.get("VERIFIED", 0),
        "released_count": state_counts.get("RELEASED", 0),
        "blockers": blockers,
        "next_actionable_states": actionable,
    }
