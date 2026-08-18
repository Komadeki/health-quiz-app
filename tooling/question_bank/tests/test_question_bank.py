from __future__ import annotations

import csv
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path


TOOL_DIR = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(TOOL_DIR))

from question_bank import (  # noqa: E402
    build_generated_files,
    load_bank_inputs,
    validate_bank,
    write_generated_files,
)
from contract import QUESTION_ID_PATTERN  # noqa: E402


class QuestionBankContractTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        source = REPOSITORY_ROOT / "question_banks" / "qualification_fixture"
        self.bank = Path(self.temporary_directory.name) / "qualification_fixture"
        shutil.copytree(source, self.bank)

    @property
    def questions_path(self) -> Path:
        return self.bank / "authoring" / "questions.csv"

    def _mutate_question(self, index: int, **changes: str) -> None:
        with self.questions_path.open(newline="", encoding="utf-8") as file:
            reader = csv.DictReader(file)
            fieldnames = list(reader.fieldnames or [])
            rows = list(reader)
        rows[index].update(changes)
        with self.questions_path.open("w", newline="", encoding="utf-8") as file:
            writer = csv.DictWriter(file, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

    def _error_codes(self) -> set[str]:
        return {issue.code for issue in validate_bank(self.bank).errors}

    def test_valid_fixture_generates_and_decodes_expected_contract(self) -> None:
        result = validate_bank(self.bank)
        self.assertTrue(result.is_valid, [str(issue) for issue in result.issues])

        written = list(write_generated_files(self.bank))
        self.assertEqual(len(written), 2)
        checked = validate_bank(self.bank, check_generated=True)
        self.assertTrue(checked.is_valid, [str(issue) for issue in checked.issues])

        runtime = json.loads(
            (self.bank / "generated" / "qualification_fixture_bank.json")
            .read_text(encoding="utf-8")
        )
        all_cards = [
            card
            for deck in runtime["decks"]
            for unit in deck["units"]
            for card in unit["cards"]
        ]
        three_choice = next(
            card for card in all_cards if card["stableId"] == "FIXTURE-Q-000001"
        )
        self.assertEqual(three_choice["questionVersion"], 1)
        self.assertEqual(three_choice["answerIndex"], 0)
        self.assertEqual(len(three_choice["choices"]), 3)
        self.assertEqual(len(all_cards), 2)
        self.assertEqual({card["isPremium"] for card in all_cards}, {True, False})

    def test_generation_is_deterministic(self) -> None:
        inputs = load_bank_inputs(self.bank)
        first = build_generated_files(inputs)
        second = build_generated_files(load_bank_inputs(self.bank))
        self.assertEqual(first, second)

    def test_duplicate_question_id_fails(self) -> None:
        self._mutate_question(1, question_id="FIXTURE-Q-000001")
        self.assertIn("duplicate_question_id", self._error_codes())

    def test_retired_question_id_reuse_fails(self) -> None:
        self._mutate_question(
            2,
            status="active",
            last_reviewed_at="2026-08-01",
            valid_until="2027-01-01",
        )
        self.assertIn("retired_id_reuse", self._error_codes())

    def test_invalid_correct_choice_fails(self) -> None:
        self._mutate_question(0, correct_choice="D")
        self.assertIn("invalid_correct_choice", self._error_codes())

    def test_missing_source_fails(self) -> None:
        self._mutate_question(0, source_id="MISSING-SOURCE")
        self.assertIn("unresolved_source_id", self._error_codes())

    def test_missing_explicit_id_fails_without_hash_fallback(self) -> None:
        self._mutate_question(0, question_id="")
        codes = self._error_codes()
        self.assertIn("missing_question_id", codes)
        self.assertIn("explicit_identity_missing_id", codes)

    def test_active_question_requires_last_reviewed_at(self) -> None:
        self._mutate_question(0, last_reviewed_at="")
        self.assertIn("active_missing_last_reviewed_at", self._error_codes())

    def test_expired_active_question_fails_against_content_as_of(self) -> None:
        self._mutate_question(0, valid_until="2026-08-16")
        self.assertIn("expired_active_question", self._error_codes())

    def test_future_valid_from_active_question_fails(self) -> None:
        self._mutate_question(0, valid_from="2026-10-01")
        self.assertIn("active_question_not_yet_valid", self._error_codes())

    def test_generated_drift_fails(self) -> None:
        write_generated_files(self.bank)
        generated = self.bank / "generated" / "qualification_fixture_bank.json"
        generated.write_text("{}\n", encoding="utf-8")
        codes = {
            issue.code
            for issue in validate_bank(self.bank, check_generated=True).errors
        }
        self.assertIn("generated_json_drift", codes)

    def test_manifest_count_mismatch_fails(self) -> None:
        write_generated_files(self.bank)
        manifest_path = self.bank / "generated" / "bank_manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest["question_count"] = 99
        manifest_path.write_text(
            json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
            encoding="utf-8",
        )
        codes = {
            issue.code
            for issue in validate_bank(self.bank, check_generated=True).errors
        }
        self.assertIn("bank_manifest_count_mismatch", codes)

    def test_released_correct_choice_change_fails(self) -> None:
        self._mutate_question(1, correct_choice="A", question_version="3")
        self.assertIn("released_correct_choice_changed", self._error_codes())

    def test_released_choice_text_change_warns_without_version_increment(self) -> None:
        self._mutate_question(1, choice2="所定の電子様式に残す")
        result = validate_bank(self.bank)
        warning_codes = {issue.code for issue in result.warnings}
        error_codes = {issue.code for issue in result.errors}

        self.assertIn("released_choices_changed", warning_codes)
        self.assertIn("question_version_not_incremented", warning_codes)
        self.assertNotIn("released_correct_choice_changed", error_codes)

    def test_released_metadata_change_warns(self) -> None:
        self._mutate_question(0, difficulty="2")
        warnings = {issue.code for issue in validate_bank(self.bank).warnings}
        self.assertIn("difficulty_changed", warnings)
        self.assertIn("question_version_not_incremented", warnings)


class DroneQuestionBankBootstrapTest(unittest.TestCase):
    DRONE_IDS = tuple(f"DRONE-Q-{number:06d}" for number in range(1, 6))

    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary_directory.cleanup)
        source = REPOSITORY_ROOT / "question_banks" / "drone_second_class"
        self.bank = Path(self.temporary_directory.name) / "drone_second_class"
        shutil.copytree(source, self.bank)

    @property
    def questions_path(self) -> Path:
        return self.bank / "authoring" / "questions.csv"

    @property
    def registry_path(self) -> Path:
        return self.bank / "authoring" / "question_id_registry.csv"

    def _read_csv(self, path: Path) -> tuple[list[str], list[dict[str, str]]]:
        with path.open(newline="", encoding="utf-8") as file:
            reader = csv.DictReader(file)
            return list(reader.fieldnames or []), list(reader)

    def _write_csv(
        self,
        path: Path,
        fieldnames: list[str],
        rows: list[dict[str, str]],
    ) -> None:
        with path.open("w", newline="", encoding="utf-8") as file:
            writer = csv.DictWriter(file, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(rows)

    def _error_codes(self) -> set[str]:
        return {issue.code for issue in validate_bank(self.bank).errors}

    def test_drone_namespace_registers_exactly_five_draft_questions(self) -> None:
        result = validate_bank(self.bank)
        self.assertTrue(result.is_valid, [str(issue) for issue in result.issues])

        inputs = load_bank_inputs(self.bank)
        question_ids = [row["question_id"] for row in inputs.questions]
        registry_ids = [row["question_id"] for row in inputs.id_registry]

        self.assertEqual(question_ids, list(self.DRONE_IDS))
        self.assertEqual(registry_ids, list(self.DRONE_IDS))
        self.assertEqual(len(question_ids), len(set(question_ids)))
        self.assertTrue(
            all(
                QUESTION_ID_PATTERN.fullmatch(question_id)
                for question_id in question_ids
            )
        )
        self.assertTrue(all(row["question_version"] == "1" for row in inputs.questions))
        self.assertTrue(all(row["status"] == "draft" for row in inputs.questions))
        self.assertTrue(
            all(
                "verification_state=author_source_verified" in row["notes_internal"]
                for row in inputs.questions
            )
        )
        self.assertTrue(all(row["status"] == "used" for row in inputs.id_registry))
        self.assertTrue(
            all(not row["first_used_bank_revision"] for row in inputs.id_registry)
        )
        self.assertEqual(inputs.metadata["app_key"], "drone_second_class")
        self.assertEqual(inputs.metadata["question_identity_policy"], "explicit_v1")
        self.assertEqual(inputs.released_questions, [])

        sentinel = inputs.questions[3]
        sentinel_neighbor = inputs.questions[4]
        self.assertEqual(sentinel["question_id"], "DRONE-Q-000004")
        self.assertEqual(sentinel_neighbor["question_id"], "DRONE-Q-000005")
        neighbor_content = " ".join(
            sentinel_neighbor[field]
            for field in (
                "question",
                "choice1",
                "choice2",
                "choice3",
                "choice4",
                "explanation",
            )
        ).casefold()
        forbidden_terms = (
            "送信機",
            "受信機",
            "transmitter",
            "receiver",
            "remote command",
        )
        for forbidden in forbidden_terms:
            self.assertNotIn(forbidden, neighbor_content)

    def test_unregistered_drone_id_is_rejected(self) -> None:
        fieldnames, rows = self._read_csv(self.questions_path)
        rows[0]["question_id"] = "DRONE-Q-000006"
        self._write_csv(self.questions_path, fieldnames, rows)

        self.assertIn("unregistered_question_id", self._error_codes())

    def test_retired_drone_id_reuse_is_rejected(self) -> None:
        fieldnames, rows = self._read_csv(self.registry_path)
        rows[0]["status"] = "retired"
        rows[0]["retired_at"] = "2026-08-18"
        self._write_csv(self.registry_path, fieldnames, rows)

        self.assertIn("retired_id_reuse", self._error_codes())

    def test_drone_bank_requires_explicit_identity(self) -> None:
        metadata_path = self.bank / "authoring" / "bank.json"
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        metadata["question_identity_policy"] = "legacy_hash_v1"
        metadata_path.write_text(
            json.dumps(metadata, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
            encoding="utf-8",
        )

        self.assertIn("identity_policy_not_explicit", self._error_codes())

    def test_drone_generation_is_deterministic_and_drafts_stay_out(self) -> None:
        first = build_generated_files(load_bank_inputs(self.bank))
        second = build_generated_files(load_bank_inputs(self.bank))
        self.assertEqual(first, second)

        write_generated_files(self.bank)
        checked = validate_bank(self.bank, check_generated=True)
        self.assertTrue(checked.is_valid, [str(issue) for issue in checked.issues])

        runtime = json.loads(
            (self.bank / "generated" / "drone_second_class_bank.json").read_text(
                encoding="utf-8"
            )
        )
        manifest = json.loads(
            (self.bank / "generated" / "bank_manifest.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(runtime["decks"], [])
        self.assertEqual(manifest["question_count"], 0)

    def test_qualification_fixture_remains_valid(self) -> None:
        fixture = REPOSITORY_ROOT / "question_banks" / "qualification_fixture"
        result = validate_bank(fixture, check_generated=True)
        self.assertTrue(result.is_valid, [str(issue) for issue in result.issues])


if __name__ == "__main__":
    unittest.main()
