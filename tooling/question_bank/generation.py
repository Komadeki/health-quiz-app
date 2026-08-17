"""Deterministic runtime bank and manifest generation."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any, Iterable

from contract import (
    GENERATED_NOTICE,
    BankInputs,
    ValidationResult,
    canonical_json_bytes,
    load_bank_inputs,
    pretty_json_bytes,
    question_choices,
    read_json,
)


def build_generated_files(inputs: BankInputs) -> dict[Path, bytes]:
    metadata = inputs.metadata
    source_by_id = {
        str(source["source_id"]): source for source in inputs.sources
    }
    active_rows = sorted(
        (row for row in inputs.questions if row.get("status") == "active"),
        key=lambda row: (row["deck_id"], row["unit_id"], row["question_id"]),
    )

    cards_by_unit: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for row in active_rows:
        source = source_by_id[row["source_id"]]
        tags = [
            tag.strip()
            for tag in row.get("tags", "").split(";")
            if tag.strip()
        ]
        card = {
            "answerIndex": ord(row["correct_choice"]) - ord("A"),
            "choices": question_choices(row),
            "difficulty": int(row["difficulty"]),
            "explanation": row["explanation"],
            "importance": int(row["importance"]),
            "isPremium": row["is_free"] != "true",
            "question": row["question"],
            "questionVersion": int(row["question_version"]),
            "sourceId": row["source_id"],
            "sourceSection": row["source_locator"],
            "sourceTitle": str(source["title"]),
            "sourceVersion": str(source["source_version"]),
            "stableId": row["question_id"],
            "unitId": row["unit_id"],
            "unitTags": tags,
        }
        cards_by_unit.setdefault((row["deck_id"], row["unit_id"]), []).append(card)

    decks: list[dict[str, Any]] = []
    for deck in sorted(metadata.get("decks", []), key=lambda item: item["deck_id"]):
        units: list[dict[str, Any]] = []
        for unit in sorted(deck.get("units", []), key=lambda item: item["unit_id"]):
            cards = cards_by_unit.get((deck["deck_id"], unit["unit_id"]), [])
            if cards:
                units.append(
                    {
                        "cards": cards,
                        "id": unit["unit_id"],
                        "title": unit["title"],
                    }
                )
        if units:
            decks.append(
                {
                    "id": deck["deck_id"],
                    "isPurchased": False,
                    "title": deck["title"],
                    "units": units,
                }
            )

    runtime = {
        "appKey": metadata["app_key"],
        "bankRevision": metadata["bank_revision"],
        "contentAsOf": metadata["content_as_of"],
        "decks": decks,
        "examProfileVersion": metadata["exam_profile_version"],
        "generatedFileNotice": GENERATED_NOTICE,
        "schemaVersion": 2,
    }
    content_hash = hashlib.sha256(canonical_json_bytes(runtime)).hexdigest()
    referenced_sources = sorted({row["source_id"] for row in active_rows})
    manifest = {
        "app_key": metadata["app_key"],
        "bank_revision": metadata["bank_revision"],
        "content_as_of": metadata["content_as_of"],
        "content_hash": f"sha256:{content_hash}",
        "exam_profile_version": metadata["exam_profile_version"],
        "free_question_count": sum(
            row["is_free"] == "true" for row in active_rows
        ),
        "generated_file_notice": GENERATED_NOTICE,
        "question_count": len(active_rows),
        "schema_version": 1,
        "source_versions": {
            source_id: str(source_by_id[source_id]["source_version"])
            for source_id in referenced_sources
        },
    }

    return {
        Path(metadata["runtime_output"]): pretty_json_bytes(runtime),
        Path(metadata["manifest_output"]): pretty_json_bytes(manifest),
    }


def validate_generated_files(
    inputs: BankInputs, result: ValidationResult
) -> None:
    expected_files = build_generated_files(inputs)
    for relative_path, expected in expected_files.items():
        path = inputs.root / relative_path
        if not path.exists() or path.read_bytes() != expected:
            result.error(
                "generated_json_drift",
                f"Regenerate committed output: {relative_path}",
                str(relative_path),
            )

    manifest_path = inputs.root / Path(inputs.metadata["manifest_output"])
    if not manifest_path.exists():
        return
    try:
        committed_manifest = read_json(manifest_path)
    except (json.JSONDecodeError, ValueError):
        result.error(
            "invalid_generated_manifest",
            "Committed bank manifest is not valid JSON.",
            str(manifest_path.relative_to(inputs.root)),
        )
        return
    active_rows = [row for row in inputs.questions if row.get("status") == "active"]
    expected_counts = {
        "question_count": len(active_rows),
        "free_question_count": sum(
            row["is_free"] == "true" for row in active_rows
        ),
    }
    for field_name, expected in expected_counts.items():
        if committed_manifest.get(field_name) != expected:
            result.error(
                "bank_manifest_count_mismatch",
                f"{field_name} must be {expected}.",
                str(manifest_path.relative_to(inputs.root)),
            )


def write_generated_files(bank_root: Path) -> Iterable[Path]:
    from validation import validate_bank

    validation = validate_bank(bank_root)
    if not validation.is_valid:
        messages = "\n".join(str(issue) for issue in validation.errors)
        raise ValueError(f"Question bank validation failed:\n{messages}")
    inputs = load_bank_inputs(bank_root)
    written: list[Path] = []
    for relative_path, content in build_generated_files(inputs).items():
        path = bank_root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        written.append(path)
    return written
