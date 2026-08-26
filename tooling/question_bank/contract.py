"""Shared types and deterministic I/O for question-bank tooling."""

from __future__ import annotations

import csv
import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


QUESTION_FIELDS = (
    "question_id",
    "question_version",
    "status",
    "deck_id",
    "unit_id",
    "question",
    "choice1",
    "choice2",
    "choice3",
    "choice4",
    "choice5",
    "correct_choice",
    "explanation",
    "source_id",
    "source_locator",
    "difficulty",
    "importance",
    "is_free",
    "valid_from",
    "valid_until",
    "last_reviewed_at",
    "supersedes_id",
    "tags",
    "notes_internal",
)

# choice5 was added after the original 3/4-choice contract.  Historical bank
# CSVs and expansion batches are intentionally allowed to omit it.
OPTIONAL_QUESTION_FIELDS = frozenset({"choice5"})
REQUIRED_QUESTION_FIELDS = tuple(
    field_name for field_name in QUESTION_FIELDS if field_name not in OPTIONAL_QUESTION_FIELDS
)

QUESTION_ID_PATTERN = re.compile(r"^[A-Z][A-Z0-9]*-Q-[0-9]{6}$")
VALID_STATUSES = {"draft", "active", "retired"}
VALID_USAGE_BASES = {
    "originally_authored",
    "public_legal_text",
    "licensed",
    "quotation",
    "permission_confirmed",
    "facts_only_independently_authored",
}
GENERATED_NOTICE = "GENERATED FILE - DO NOT EDIT"


@dataclass(frozen=True)
class ContractIssue:
    severity: str
    code: str
    message: str
    location: str = ""

    def __str__(self) -> str:
        suffix = f" ({self.location})" if self.location else ""
        return f"{self.severity.upper()} [{self.code}] {self.message}{suffix}"


@dataclass
class ValidationResult:
    issues: list[ContractIssue] = field(default_factory=list)

    @property
    def errors(self) -> list[ContractIssue]:
        return [issue for issue in self.issues if issue.severity == "error"]

    @property
    def warnings(self) -> list[ContractIssue]:
        return [issue for issue in self.issues if issue.severity == "warning"]

    @property
    def is_valid(self) -> bool:
        return not self.errors

    def error(self, code: str, message: str, location: str = "") -> None:
        self.issues.append(ContractIssue("error", code, message, location))

    def warning(self, code: str, message: str, location: str = "") -> None:
        self.issues.append(ContractIssue("warning", code, message, location))


@dataclass(frozen=True)
class BankInputs:
    root: Path
    metadata: dict[str, Any]
    questions: list[dict[str, str]]
    sources: list[dict[str, Any]]
    id_registry: list[dict[str, str]]
    released_questions: list[dict[str, Any]]
    coverage: dict[str, Any]
    source_verifications: dict[str, Any]


def read_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as file:
        value = json.load(file)
    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object: {path}")
    return value


def read_csv(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    with path.open(newline="", encoding="utf-8-sig") as file:
        reader = csv.DictReader(file)
        fieldnames = list(reader.fieldnames or [])
        rows = [
            {key: (value or "").strip() for key, value in row.items()}
            for row in reader
        ]
    return fieldnames, rows


def load_bank_inputs(bank_root: Path) -> BankInputs:
    _, questions = read_csv(bank_root / "authoring" / "questions.csv")
    _, registry = read_csv(bank_root / "authoring" / "question_id_registry.csv")
    sources = read_json(bank_root / "authoring" / "sources.json").get(
        "sources", []
    )
    released = read_json(
        bank_root / "authoring" / "released_questions.json"
    ).get("released_questions", [])
    coverage_path = bank_root / "authoring" / "coverage.json"
    verification_path = bank_root / "authoring" / "source_verifications.json"
    return BankInputs(
        root=bank_root,
        metadata=read_json(bank_root / "authoring" / "bank.json"),
        questions=questions,
        sources=list(sources),
        id_registry=registry,
        released_questions=list(released),
        coverage=read_json(coverage_path) if coverage_path.exists() else {},
        source_verifications=(
            read_json(verification_path) if verification_path.exists() else {}
        ),
    )


def question_choices(row: dict[str, str]) -> list[str]:
    return [
        row.get(f"choice{index}", "")
        for index in range(1, 6)
        if row.get(f"choice{index}", "")
    ]


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
