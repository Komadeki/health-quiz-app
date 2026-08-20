"""Shared types and canonical I/O for V0-Panel validation artifacts."""

from __future__ import annotations

import csv
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


GENERATED_NOTICE = "GENERATED FILE - DO NOT EDIT"
AUTHORING_FILES = (
    "authoring/bank.json",
    "authoring/questions.csv",
    "authoring/question_id_registry.csv",
    "authoring/released_questions.json",
    "authoring/sources.json",
)


@dataclass(frozen=True)
class ValidationInputs:
    bank_root: Path
    source_root: Path
    protocol: dict[str, Any]
    bank: dict[str, Any]
    questions: list[dict[str, str]]
    registry: list[dict[str, str]]
    released: dict[str, Any]
    sources: dict[str, Any]


def read_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as file:
        value = json.load(file)
    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object: {path}")
    return value


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as file:
        return [
            {key: (value or "").strip() for key, value in row.items()}
            for row in csv.DictReader(file)
        ]


def load_validation_inputs(bank_root: Path) -> ValidationInputs:
    source_root = bank_root / "validation" / "formal_snapshot"
    authoring = source_root / "authoring"
    return ValidationInputs(
        bank_root=bank_root,
        source_root=source_root,
        protocol=read_json(bank_root / "validation" / "protocol.json"),
        bank=read_json(authoring / "bank.json"),
        questions=read_csv(authoring / "questions.csv"),
        registry=read_csv(authoring / "question_id_registry.csv"),
        released=read_json(authoring / "released_questions.json"),
        sources=read_json(authoring / "sources.json"),
    )


def parse_control_metadata(raw_value: str) -> dict[str, str]:
    """Parse authoring-only controls before materializing typed bundle fields."""
    parsed: dict[str, str] = {}
    for segment in raw_value.split(";"):
        segment = segment.strip()
        if not segment:
            continue
        if "=" not in segment:
            raise ValueError(f"Invalid notes_internal segment: {segment!r}")
        key, value = (part.strip() for part in segment.split("=", 1))
        if not key or not value or key in parsed:
            raise ValueError(f"Invalid notes_internal property: {segment!r}")
        parsed[key] = value
    return parsed


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(
        value,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")


def pretty_json_bytes(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    ).encode("utf-8")


def sha256_value(content: bytes) -> str:
    return f"sha256:{hashlib.sha256(content).hexdigest()}"


def _normalized_bank(value: dict[str, Any]) -> dict[str, Any]:
    normalized = dict(value)
    normalized["decks"] = sorted(
        (
            {
                **deck,
                "units": sorted(
                    deck.get("units", []), key=lambda unit: unit.get("unit_id", "")
                ),
            }
            for deck in value.get("decks", [])
        ),
        key=lambda deck: deck.get("deck_id", ""),
    )
    return normalized


def formal_snapshot_source_document(inputs: ValidationInputs) -> dict[str, Any]:
    """Return a semantic, ordering-insensitive view of the five formal inputs."""
    return {
        "authoring/bank.json": _normalized_bank(inputs.bank),
        "authoring/question_id_registry.csv": sorted(
            inputs.registry, key=lambda row: row.get("question_id", "")
        ),
        "authoring/questions.csv": sorted(
            inputs.questions, key=lambda row: row.get("question_id", "")
        ),
        "authoring/released_questions.json": {
            **inputs.released,
            "released_questions": sorted(
                inputs.released.get("released_questions", []),
                key=lambda row: (
                    row.get("question_id", ""),
                    row.get("question_version", 0),
                ),
            ),
        },
        "authoring/sources.json": {
            **inputs.sources,
            "sources": sorted(
                inputs.sources.get("sources", []),
                key=lambda row: row.get("source_id", ""),
            ),
        },
    }


def formal_snapshot_source_hash(inputs: ValidationInputs) -> str:
    return sha256_value(canonical_json_bytes(formal_snapshot_source_document(inputs)))


def file_sha256(path: Path) -> str:
    return sha256_value(path.read_bytes())
