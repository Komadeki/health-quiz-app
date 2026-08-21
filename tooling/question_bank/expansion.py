from __future__ import annotations

import csv
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any

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
    "question", "choice1", "choice2", "choice3", "choice4", "proposed_correct",
    "explanation", "source_id", "source_version", "source_locator",
    "answer_defining_proposition", "tested_misconception", "reasoning_path",
    "collision_note", "permanent_question_id",
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
ID_RE = re.compile(r"^[A-Z0-9]+(?:-[A-Z0-9]+)*-Q-\d{6}$")


def _read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), list(reader)


def _nonempty(row: dict[str, str], *keys: str) -> bool:
    return any((row.get(key) or "").strip() for key in keys)


def _review_state(decision: str) -> str:
    return {"ACCEPT": "HUMAN_ACCEPT", "REWORK": "REWORK", "REJECT": "REJECT", "HOLD": "HOLD"}[decision]


def validate_expansion_batch(batch_dir: Path | str) -> list[str]:
    batch_dir = Path(batch_dir)
    errors: list[str] = []
    for name in REQUIRED_FILES:
        if not (batch_dir / name).is_file():
            errors.append(f"missing required file: {name}")
    if errors:
        return errors

    try:
        batch = json.loads((batch_dir / "batch.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"invalid batch.json: {exc}"]

    for key in (
        "schema_version", "app_key", "batch_id", "baseline_sha", "batch_status",
        "expansion_trigger", "evidence", "target_size_decisions", "planned_scope",
        "coverage_limit_decisions",
    ):
        if key not in batch:
            errors.append(f"batch.json missing field: {key}")

    decisions = batch.get("target_size_decisions")
    if not isinstance(decisions, list) or not decisions:
        errors.append("target_size_decisions must be a non-empty list")
    else:
        seen_decisions: set[str] = set()
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
            elif decision["proposed_target_min"] > decision["proposed_target_max"]:
                errors.append(f"target decision {decision_id} has min greater than max")
            if not str(decision.get("rationale", "")).strip() or not str(decision.get("evidence", "")).strip():
                errors.append(f"target decision {decision_id} requires rationale and evidence")
            if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", str(decision.get("decision_date", ""))):
                errors.append(f"target decision {decision_id} has invalid decision_date")

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
    missing_candidate_columns = [c for c in CANDIDATE_COLUMNS if c not in candidate_fields]
    missing_review_columns = [c for c in REVIEW_COLUMNS if c not in review_fields]
    if missing_candidate_columns:
        errors.append("candidates.csv missing columns: " + ",".join(missing_candidate_columns))
    if missing_review_columns:
        errors.append("reviews.csv missing columns: " + ",".join(missing_review_columns))
    if missing_candidate_columns or missing_review_columns:
        return errors

    candidate_ids = [row["candidate_id"].strip() for row in candidates]
    duplicates = sorted(key for key, count in Counter(candidate_ids).items() if key and count > 1)
    if duplicates:
        errors.append("duplicate candidate_id: " + ",".join(duplicates))
    if any(not candidate_id for candidate_id in candidate_ids):
        errors.append("candidate_id must not be empty")

    reviews_by_candidate: dict[str, list[dict[str, str]]] = {}
    for row in reviews:
        candidate_id = row["candidate_id"].strip()
        reviews_by_candidate.setdefault(candidate_id, []).append(row)
        decision = row["decision"].strip()
        if decision not in HUMAN_DECISIONS:
            errors.append(f"invalid review decision for {candidate_id}: {decision}")
        if not row["reviewer_role"].strip():
            errors.append(f"reviewer_role is required for {candidate_id}")
        try:
            round_number = int(row["review_round"])
            if round_number < 1:
                raise ValueError
        except ValueError:
            errors.append(f"invalid review_round for {candidate_id}: {row['review_round']}")
        if decision == "REJECT" and not _nonempty(row, "reason_code", "reason_detail"):
            errors.append(f"REJECT review requires reason for {candidate_id}")
        if decision == "HOLD":
            if not _nonempty(row, "reason_code", "reason_detail"):
                errors.append(f"HOLD review requires reason for {candidate_id}")
            if not row["resume_condition"].strip():
                errors.append(f"HOLD review requires resume_condition for {candidate_id}")

    permanent_to_candidate: dict[str, str] = {}
    for row in candidates:
        candidate_id = row["candidate_id"].strip()
        state = row["state"].strip()
        if state not in ALLOWED_STATES:
            errors.append(f"invalid candidate state for {candidate_id}: {state}")
            continue
        if candidate_id in known_rejected_ids and state != "REJECT":
            errors.append(f"known rejected candidate_id reused: {candidate_id}")

        content_required = state not in {"DRAFT", "REWORK", "HOLD", "REJECT"}
        if content_required:
            for field in ("unit_id", "question", "choice1", "choice2", "proposed_correct", "explanation", "source_id", "source_version", "source_locator"):
                if not row[field].strip():
                    errors.append(f"{state} candidate {candidate_id} missing {field}")

        correct = row["proposed_correct"].strip()
        if correct:
            choice_map = {"A": "choice1", "B": "choice2", "C": "choice3", "D": "choice4"}
            if correct not in choice_map or not row[choice_map.get(correct, "choice1")].strip():
                errors.append(f"proposed_correct does not reference an existing choice for {candidate_id}")

        permanent_id = row["permanent_question_id"].strip()
        if state in PRODUCTION_STATES:
            if not permanent_id:
                errors.append(f"{state} candidate {candidate_id} requires permanent_question_id")
        elif permanent_id:
            errors.append(f"pre-ID candidate {candidate_id} must not have permanent_question_id")
        if permanent_id:
            if not ID_RE.fullmatch(permanent_id):
                errors.append(f"invalid permanent_question_id for {candidate_id}: {permanent_id}")
            prior = permanent_to_candidate.get(permanent_id)
            if prior and prior != candidate_id:
                errors.append(f"duplicate permanent ID mapping: {permanent_id}")
            permanent_to_candidate[permanent_id] = candidate_id

        candidate_reviews = reviews_by_candidate.get(candidate_id, [])
        latest_decision = ""
        if candidate_reviews:
            def review_key(review: dict[str, str]) -> int:
                try:
                    return int(review["review_round"])
                except ValueError:
                    return -1
            latest_decision = max(candidate_reviews, key=review_key)["decision"].strip()

        human_states = {"HUMAN_ACCEPT", "REWORK", "HOLD", "REJECT"}
        if state in human_states:
            if not candidate_reviews:
                errors.append(f"{state} candidate {candidate_id} has no Human review")
            elif latest_decision in HUMAN_DECISIONS and _review_state(latest_decision) != state:
                errors.append(f"latest Human review conflicts with candidate state for {candidate_id}")
        elif state in POST_ACCEPT_STATES:
            if not candidate_reviews or latest_decision != "ACCEPT":
                errors.append(f"{state} candidate {candidate_id} requires latest Human ACCEPT review")

    candidate_set = set(candidate_ids)
    for candidate_id in reviews_by_candidate:
        if candidate_id not in candidate_set:
            errors.append(f"review references unknown candidate_id: {candidate_id}")

    return errors


def build_status_report(batch_dir: Path | str) -> dict[str, Any]:
    batch_dir = Path(batch_dir)
    batch = json.loads((batch_dir / "batch.json").read_text(encoding="utf-8"))
    _, candidates = _read_csv(batch_dir / "candidates.csv")
    state_counts = Counter(row["state"].strip() for row in candidates)
    decisions = batch.get("target_size_decisions") or []
    blockers = list(batch.get("migration_blockers") or [])
    blockers.extend(validate_expansion_batch(batch_dir))
    actionable = [
        state for state in (
            "DRAFT", "AI_PRE_ACCEPT", "REWORK", "HOLD", "HUMAN_ACCEPT",
            "READY_FOR_ID", "ID_ALLOCATED", "INTEGRATED", "VERIFIED",
        ) if state_counts.get(state)
    ]
    return {
        "batch_id": batch.get("batch_id"),
        "batch_status": batch.get("batch_status"),
        "current_target_decision": decisions[-1] if decisions else None,
        "count_by_candidate_state": dict(sorted(state_counts.items())),
        "human_accept_count": state_counts.get("HUMAN_ACCEPT", 0),
        "reject_count": state_counts.get("REJECT", 0),
        "hold_count": state_counts.get("HOLD", 0),
        "ready_for_id_count": state_counts.get("READY_FOR_ID", 0),
        "id_allocated_count": state_counts.get("ID_ALLOCATED", 0),
        "integrated_count": state_counts.get("INTEGRATED", 0),
        "verified_count": state_counts.get("VERIFIED", 0),
        "released_count": state_counts.get("RELEASED", 0),
        "blockers": blockers,
        "next_actionable_states": actionable,
    }
