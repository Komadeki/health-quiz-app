from __future__ import annotations

import csv
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(TOOL_DIR))

from contract import QUESTION_FIELDS, read_csv  # noqa: E402
from expansion import CANDIDATE_COLUMNS  # noqa: E402
from transaction import QuestionExpansionTransaction, TransactionError  # noqa: E402


class TransactionHelperTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.bank = Path(self.temp.name) / "question_banks" / "qualification_fixture"
        shutil.copytree(REPOSITORY_ROOT / "question_banks" / "qualification_fixture", self.bank)
        self.batch = self.bank / "authoring" / "batches" / "batch_001"
        self.batch.mkdir(parents=True)
        self._write_candidates(("B1-C001", "B1-C002"))

    def _write_candidates(self, candidate_ids: tuple[str, ...], *, state: str = "READY_FOR_ID") -> None:
        rows = []
        for candidate_id in candidate_ids:
            row = {field: "" for field in CANDIDATE_COLUMNS}
            row.update({
                "candidate_id": candidate_id,
                "state": state,
                "unit_id": "fixture_safety",
                "domain": "Rules",
                "knowledge_target_id": "R1",
                "family": "scenario",
                "question": f"Question {candidate_id}?",
                "choice1": "A1",
                "choice2": "A2",
                "choice3": "A3",
                "proposed_correct": "A",
                "explanation": "Because.",
                "source_id": "FIXTURE-SRC-001",
                "source_version": "2026.1",
                "source_locator": "p.1",
            })
            rows.append(row)
        with (self.batch / "candidates.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=CANDIDATE_COLUMNS)
            writer.writeheader()
            writer.writerows(rows)

    def _transaction(self, *, factory=None, failure_hook=None) -> QuestionExpansionTransaction:
        return QuestionExpansionTransaction(
            self.bank,
            self.batch,
            ("B1-C001", "B1-C002"),
            question_factory=factory,
            failure_hook=failure_hook,
        )

    def _factory(self, candidate: dict[str, str], question_id: str) -> dict[str, str]:
        row = {field: "" for field in QUESTION_FIELDS}
        row.update({
            "question_id": question_id,
            "question_version": "1",
            "status": "draft",
            "deck_id": "fixture_basics",
            "unit_id": candidate["unit_id"],
            "question": candidate["question"],
            "choice1": candidate["choice1"],
            "choice2": candidate["choice2"],
            "choice3": candidate["choice3"],
            "choice4": candidate["choice4"],
            "correct_choice": candidate["proposed_correct"],
            "explanation": candidate["explanation"],
            "source_id": candidate["source_id"],
            "source_locator": candidate["source_locator"],
            "is_free": "false",
            "notes_internal": "",
        })
        return row

    def test_dry_run_is_deterministic_and_does_not_write(self) -> None:
        before = {path: path.read_bytes() for path in self._transaction().target_paths}
        first = self._transaction().dry_run()
        second = self._transaction().dry_run()
        self.assertEqual(first, second)
        self.assertEqual(first, {"B1-C001": "FIXTURE-Q-000004", "B1-C002": "FIXTURE-Q-000005"})
        self.assertEqual(before, {path: path.read_bytes() for path in self._transaction().target_paths})

    def test_used_and_retired_ids_are_not_reused(self) -> None:
        mapping = self._transaction().dry_run()
        self.assertNotIn(mapping["B1-C001"], {"FIXTURE-Q-000001", "FIXTURE-Q-000002", "FIXTURE-Q-000003"})

    def test_apply_updates_all_targets_and_repeat_is_rejected(self) -> None:
        mapping = self._transaction(factory=self._factory).apply()
        self.assertEqual(len(mapping), 2)
        _, candidates = read_csv(self.batch / "candidates.csv")
        self.assertEqual({row["state"] for row in candidates}, {"INTEGRATED"})
        _, questions = read_csv(self.bank / "authoring" / "questions.csv")
        self.assertEqual(len(questions), 5)
        with self.assertRaises(TransactionError):
            self._transaction(factory=self._factory).apply()

    def test_partial_existing_candidate_mapping_is_rejected(self) -> None:
        fields, rows = read_csv(self.batch / "candidates.csv")
        rows[0]["permanent_question_id"] = "FIXTURE-Q-000004"
        with (self.batch / "candidates.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
        with self.assertRaises(TransactionError):
            self._transaction().dry_run()

    def test_partial_registry_mapping_is_rejected(self) -> None:
        path = self.bank / "authoring" / "question_id_registry.csv"
        fields, rows = read_csv(path)
        rows.append({field: "" for field in fields})
        rows[-1].update({
            "question_id": "FIXTURE-Q-000004",
            "status": "used",
            "notes": "Expansion pre-release allocation: B1-C001",
        })
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
        with self.assertRaises(TransactionError):
            self._transaction().dry_run()

    def test_partial_canonical_mapping_is_rejected(self) -> None:
        fields, rows = read_csv(self.bank / "authoring" / "questions.csv")
        row = dict(rows[0])
        row.update({
            "question_id": "FIXTURE-Q-000004",
            "status": "draft",
            "question": "Question B1-C001?",
            "choice1": "A1",
            "choice2": "A2",
            "choice3": "A3",
            "choice4": "",
            "correct_choice": "A",
        })
        rows.append(row)
        with (self.bank / "authoring" / "questions.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
        with self.assertRaises(TransactionError):
            self._transaction(factory=self._factory).dry_run()

    def test_failure_after_first_write_restores_every_target(self) -> None:
        transaction = self._transaction(factory=self._factory, failure_hook=lambda phase, index: (_ for _ in ()).throw(RuntimeError("injected")) if phase == "after_write" and index == 1 else None)
        before = {path: path.read_bytes() for path in transaction.target_paths}
        with self.assertRaises(RuntimeError):
            transaction.apply()
        self.assertEqual(before, {path: path.read_bytes() for path in transaction.target_paths})

    def test_failure_after_multiple_writes_and_post_write_validation_restore(self) -> None:
        for phase, index in (("after_write", 2), ("post_write_validation", 3)):
            transaction = self._transaction(factory=self._factory, failure_hook=lambda actual_phase, actual_index, phase=phase, index=index: (_ for _ in ()).throw(RuntimeError("injected")) if (actual_phase, actual_index) == (phase, index) else None)
            before = {path: path.read_bytes() for path in transaction.target_paths}
            with self.assertRaises(RuntimeError):
                transaction.apply()
            self.assertEqual(before, {path: path.read_bytes() for path in transaction.target_paths})


if __name__ == "__main__":
    unittest.main()
