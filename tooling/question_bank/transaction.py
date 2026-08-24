"""Safe, staged lifecycle transaction for pre-release question expansion.

The production bank is deliberately not mutated by importing this module.  Callers
must opt in to :meth:`QuestionExpansionTransaction.apply` and provide a canonical
row factory for the target bank.
"""

from __future__ import annotations

import csv
import io
import os
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Iterable

from contract import QUESTION_FIELDS, QUESTION_ID_PATTERN, read_csv
from expansion import CANDIDATE_COLUMNS


class TransactionError(RuntimeError):
    """Raised when the transaction cannot safely proceed."""


@dataclass(frozen=True)
class Allocation:
    candidate_id: str
    permanent_question_id: str


@dataclass(frozen=True)
class TransactionPlan:
    allocations: tuple[Allocation, ...]
    candidate_bytes: bytes
    registry_bytes: bytes
    question_bytes: bytes | None

    @property
    def mapping(self) -> dict[str, str]:
        return {item.candidate_id: item.permanent_question_id for item in self.allocations}


FailureHook = Callable[[str, int], None]
QuestionFactory = Callable[[dict[str, str], str], dict[str, str]]


def _csv_bytes(fields: list[str], rows: list[dict[str, str]]) -> bytes:
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows({field: row.get(field, "") for field in fields} for row in rows)
    return output.getvalue().encode("utf-8")


def _read_rows(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    fields, rows = read_csv(path)
    return fields, rows


def _candidate_sort_key(row: dict[str, str]) -> tuple[str, int]:
    value = row.get("candidate_id", "")
    suffix = value.rsplit("C", 1)[-1]
    return (value[: -len(suffix)] if suffix.isdigit() else value, int(suffix) if suffix.isdigit() else -1)


class QuestionExpansionTransaction:
    """Plan and atomically apply a candidate allocation/integration transaction.

    The helper operates on three files: candidates, the permanent-ID registry, and
    optionally canonical questions.  All output is staged before any target is
    replaced; every replacement is restored from the original bytes on failure.
    """

    def __init__(
        self,
        bank_root: Path,
        batch_dir: Path,
        candidate_ids: Iterable[str],
        *,
        question_factory: QuestionFactory | None = None,
        failure_hook: FailureHook | None = None,
    ) -> None:
        self.bank_root = Path(bank_root)
        self.batch_dir = Path(batch_dir)
        self.candidate_ids = tuple(candidate_ids)
        self.question_factory = question_factory
        self.failure_hook = failure_hook
        self._plan: TransactionPlan | None = None

    @property
    def target_paths(self) -> tuple[Path, ...]:
        paths = (
            self.batch_dir / "candidates.csv",
            self.bank_root / "authoring" / "question_id_registry.csv",
        )
        if self.question_factory is not None:
            paths += (self.bank_root / "authoring" / "questions.csv",)
        return paths

    def _load(self) -> tuple[list[str], list[dict[str, str]], list[str], list[dict[str, str]], list[str], list[dict[str, str]] | None]:
        candidate_fields, candidates = _read_rows(self.batch_dir / "candidates.csv")
        registry_fields, registry = _read_rows(self.bank_root / "authoring" / "question_id_registry.csv")
        if candidate_fields != list(CANDIDATE_COLUMNS):
            raise TransactionError("candidate schema does not match the expansion contract")
        if not {"question_id", "status", "first_used_bank_revision", "retired_at"}.issubset(registry_fields):
            raise TransactionError("registry schema is missing permanent-ID fields")
        if self.question_factory is None:
            return candidate_fields, candidates, registry_fields, registry, [], None
        question_fields, questions = _read_rows(self.bank_root / "authoring" / "questions.csv")
        if question_fields != list(QUESTION_FIELDS):
            raise TransactionError("canonical question schema does not match the Question contract")
        return candidate_fields, candidates, registry_fields, registry, question_fields, questions

    def _validate_pre_state(self, candidates: list[dict[str, str]], registry: list[dict[str, str]], questions: list[dict[str, str]] | None) -> list[dict[str, str]]:
        wanted = set(self.candidate_ids)
        rows = [row for row in candidates if row.get("candidate_id") in wanted]
        if len(rows) != len(wanted) or len(rows) != len(self.candidate_ids):
            raise TransactionError("candidate set is incomplete or contains duplicates")
        if any(row.get("state") not in {"HUMAN_ACCEPT", "READY_FOR_ID"} for row in rows):
            raise TransactionError("all candidates must be pre-ID accepted candidates")
        if any(row.get("permanent_question_id") for row in rows):
            raise TransactionError("partial candidate permanent-ID mapping detected")
        registry_ids = [row.get("question_id", "") for row in registry]
        if len(registry_ids) != len(set(registry_ids)):
            raise TransactionError("duplicate permanent IDs in registry")
        if questions is not None:
            question_ids = [row.get("question_id", "") for row in questions]
            if len(question_ids) != len(set(question_ids)):
                raise TransactionError("duplicate permanent IDs in canonical questions")
            if any(candidate_id in question_ids for candidate_id in self.candidate_ids):
                raise TransactionError("candidate identity is already present in canonical questions")
            for candidate in rows:
                if any(
                    all(candidate.get(field, "") == question.get(canonical, "") for field, canonical in (
                        ("question", "question"),
                        ("choice1", "choice1"),
                        ("choice2", "choice2"),
                        ("choice3", "choice3"),
                        ("choice4", "choice4"),
                        ("proposed_correct", "correct_choice"),
                    ))
                    for question in questions
                ):
                    raise TransactionError("partial canonical draft mapping detected")
        if any(
            candidate_id in row.get("notes", "")
            for row in registry
            for candidate_id in self.candidate_ids
        ):
            raise TransactionError("partial registry mapping detected")
        return sorted(rows, key=_candidate_sort_key)

    @staticmethod
    def _allocate(registry: list[dict[str, str]], count: int) -> list[str]:
        occupied: set[int] = set()
        prefix: str | None = None
        for row in registry:
            question_id = row.get("question_id", "")
            match = QUESTION_ID_PATTERN.fullmatch(question_id)
            if not match:
                continue
            current_prefix, suffix = question_id.rsplit("-Q-", 1)
            prefix = prefix or current_prefix
            if current_prefix == prefix:
                occupied.add(int(suffix))
        if prefix is None:
            raise TransactionError("cannot determine permanent-ID prefix from registry")
        allocated: list[str] = []
        candidate = 1
        while len(allocated) < count:
            if candidate not in occupied:
                allocated.append(f"{prefix}-Q-{candidate:06d}")
                occupied.add(candidate)
            candidate += 1
        return allocated

    def plan(self) -> TransactionPlan:
        candidate_fields, candidates, registry_fields, registry, question_fields, questions = self._load()
        selected = self._validate_pre_state(candidates, registry, questions)
        ids = self._allocate(registry, len(selected))
        allocations = tuple(Allocation(row["candidate_id"], question_id) for row, question_id in zip(selected, ids))
        mapping = {item.candidate_id: item.permanent_question_id for item in allocations}
        updated_candidates = []
        for row in candidates:
            if row.get("candidate_id") in mapping:
                row = dict(row)
                row["state"] = "INTEGRATED" if self.question_factory is not None else "ID_ALLOCATED"
                row["permanent_question_id"] = mapping[row["candidate_id"]]
            updated_candidates.append(row)
        updated_registry = list(registry)
        for item in allocations:
            updated_registry.append({field: (item.permanent_question_id if field == "question_id" else "used" if field == "status" else "" if field in {"first_used_bank_revision", "retired_at", "replacement_id"} else f"Expansion pre-release allocation: {item.candidate_id}") for field in registry_fields})
        updated_questions: list[dict[str, str]] | None = None
        question_bytes: bytes | None = None
        if self.question_factory is not None and questions is not None:
            updated_questions = list(questions)
            for row in selected:
                updated = self.question_factory(row, mapping[row["candidate_id"]])
                if set(updated) != set(QUESTION_FIELDS):
                    raise TransactionError("question factory returned an invalid canonical row")
                updated_questions.append(updated)
            question_bytes = _csv_bytes(question_fields, updated_questions)
        self._plan = TransactionPlan(
            allocations,
            _csv_bytes(candidate_fields, updated_candidates),
            _csv_bytes(registry_fields, updated_registry),
            question_bytes,
        )
        return self._plan

    def dry_run(self) -> dict[str, str]:
        return dict(self.plan().mapping)

    def apply(self) -> dict[str, str]:
        plan = self._plan or self.plan()
        originals = {path: path.read_bytes() for path in self.target_paths}
        payloads = [plan.candidate_bytes, plan.registry_bytes]
        if plan.question_bytes is not None:
            payloads.append(plan.question_bytes)
        replaced: list[Path] = []
        try:
            with tempfile.TemporaryDirectory(prefix="question-transaction-") as staging:
                for index, (path, payload) in enumerate(zip(self.target_paths, payloads), start=1):
                    staged = Path(staging) / f"target-{index}"
                    staged.write_bytes(payload)
                    os.replace(staged, path)
                    replaced.append(path)
                    if self.failure_hook is not None:
                        self.failure_hook("after_write", index)
            if self.failure_hook is not None:
                self.failure_hook("post_write_validation", len(replaced))
        except Exception:
            for path in replaced:
                path.write_bytes(originals[path])
            raise
        return dict(plan.mapping)
