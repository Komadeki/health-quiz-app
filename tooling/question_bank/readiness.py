"""Deterministic evidence report for a Question Factory bank."""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Any

from contract import ValidationResult, load_bank_inputs
from factory_contracts import validate_coverage, validate_source_verifications
from validation import _metadata_ids, validate_bank


def _count_by(rows: list[dict[str, str]], field_name: str) -> dict[str, int]:
    return dict(sorted(Counter(row.get(field_name, "") for row in rows).items()))


def _runtime_count(bank_root: Path, runtime_output: str) -> int | None:
    path = bank_root / runtime_output
    try:
        runtime = json.loads(path.read_text(encoding="utf-8"))
        return sum(
            len(unit.get("cards", []))
            for deck in runtime.get("decks", [])
            for unit in deck.get("units", [])
        )
    except (OSError, TypeError, ValueError):
        return None


def build_readiness_report(
    bank_root: Path, *, check_generated: bool = False
) -> tuple[dict[str, Any], ValidationResult]:
    """Return deterministic evidence; it does not assert semantic sufficiency."""
    validation = validate_bank(bank_root, check_generated=check_generated)
    inputs = load_bank_inputs(bank_root)
    question_by_id = {row.get("question_id", ""): row for row in inputs.questions}
    source_by_id = {
        str(source.get("source_id", "")): source for source in inputs.sources
    }
    analysis = ValidationResult()
    _, unit_ids = _metadata_ids(inputs.metadata)
    coverage = validate_coverage(inputs, question_by_id, unit_ids, analysis)
    verifications = validate_source_verifications(
        inputs, question_by_id, source_by_id, analysis
    )
    active_rows = [row for row in inputs.questions if row.get("status") == "active"]
    status_counts = _count_by(inputs.questions, "status")
    answer_counts = Counter(row.get("correct_choice", "") for row in active_rows)
    active_count = len(active_rows)
    generated_issues = [
        issue.code
        for issue in validation.issues
        if issue.code in {"generated_json_drift", "bank_manifest_count_mismatch", "invalid_generated_manifest"}
    ]
    registry_issue_codes = sorted(
        {
            issue.code
            for issue in validation.issues
            if "registry" in issue.code
            or "tombstone" in issue.code
            or "replacement" in issue.code
        }
    )
    first_used_issues = sorted(
        {
            issue.code
            for issue in validation.issues
            if "first_used_bank_revision" in issue.code
        }
    )
    report: dict[str, Any] = {
        "app_key": inputs.metadata.get("app_key", ""),
        "bank_revision": inputs.metadata.get("bank_revision", ""),
        "question_counts": {
            "total": len(inputs.questions),
            "active": status_counts.get("active", 0),
            "draft": status_counts.get("draft", 0),
            "retired": status_counts.get("retired", 0),
            "free_active": sum(row.get("is_free") == "true" for row in active_rows),
            "premium_active": sum(row.get("is_free") != "true" for row in active_rows),
            "by_unit": _count_by(active_rows, "unit_id"),
            "by_importance": _count_by(active_rows, "importance"),
        },
        "target_bank_size": {
            "approved_question_count": coverage["declared_target_bank_size"],
            "rationale": coverage["bank_size_decision_rationale"],
            "active_question_count": active_count,
            "active_minus_target": (
                active_count - coverage["declared_target_bank_size"]
                if coverage["declared_target_bank_size"] is not None
                else None
            ),
        },
        "coverage": coverage,
        "question_verification": verifications,
        "source_usage_counts": _count_by(active_rows, "source_id"),
        "near_duplicate_candidates": sorted(
            issue.message
            for issue in validation.warnings
            if issue.code == "similar_questions"
        ),
        "correct_choice_position_distribution": {
            choice: {
                "count": answer_counts[choice],
                "percent": round((answer_counts[choice] * 100 / active_count), 1)
                if active_count
                else 0.0,
            }
            for choice in ("A", "B", "C", "D")
        },
        "registry_consistency": {
            "entry_count": len(inputs.id_registry),
            "released_question_count": len(inputs.released_questions),
            "issue_codes": registry_issue_codes,
        },
        "first_used_bank_revision_issues": first_used_issues,
        "generated_runtime_count": _runtime_count(
            bank_root, str(inputs.metadata.get("runtime_output", ""))
        ),
        "generated_drift": {
            "requested": check_generated,
            "status": (
                "not_requested"
                if not check_generated
                else "drift_detected"
                if generated_issues
                else "up_to_date"
                if validation.is_valid
                else "not_checked_due_to_validation_errors"
            ),
            "issue_codes": generated_issues,
        },
        "deterministic_validation": {
            "error_codes": sorted({issue.code for issue in validation.errors}),
            "warning_codes": sorted({issue.code for issue in validation.warnings}),
        },
        "semantic_review_boundary": (
            "Bank size, source authority, semantic correctness, and knowledge-target "
            "adequacy require Human judgment. Semantic/material overlap review is "
            "AI-assisted or Human-decided and is outside deterministic CI."
        ),
    }
    return report, validation


def format_readiness_report(report: dict[str, Any]) -> str:
    """Render a concise deterministic summary alongside JSON mode."""
    counts = report["question_counts"]
    target = report["target_bank_size"]
    coverage = report["coverage"]
    verification = report["question_verification"]
    distribution = report["correct_choice_position_distribution"]
    return "\n".join(
        [
            f"Question Factory readiness: {report['app_key']} ({report['bank_revision']})",
            f"Questions: total={counts['total']} active={counts['active']} draft={counts['draft']} retired={counts['retired']} free={counts['free_active']} premium={counts['premium_active']}",
            f"Target bank size: {target['approved_question_count']} active={target['active_question_count']} delta={target['active_minus_target']}",
            f"Coverage: required missing={coverage['missing_required_knowledge_target_ids']} variations missing={coverage['missing_required_variations']} optional targets={len(coverage['optional_targets'])}",
            f"Verification: complete={verification['complete_active_question_count']}/{verification['active_question_count']} missing={verification['missing_question_ids']} source-version mismatches={verification['source_version_mismatches']}",
            "Correct choices: " + ", ".join(f"{choice}={distribution[choice]['count']} ({distribution[choice]['percent']}%)" for choice in ("A", "B", "C", "D")),
            f"Generated runtime count: {report['generated_runtime_count']}; drift={report['generated_drift']['status']}",
            "Semantic/material overlap and taxonomy adequacy remain AI-assisted/Human review, not deterministic CI.",
        ]
    )
