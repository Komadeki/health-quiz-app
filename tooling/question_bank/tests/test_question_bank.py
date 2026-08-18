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


class DroneQuestionBankTest(unittest.TestCase):
    PERMANENT_SLOT_TO_ID = {
        "VS-001": "DRONE-Q-000001",
        "VS-004": "DRONE-Q-000002",
        "VS-027": "DRONE-Q-000003",
        "VS-039": "DRONE-Q-000004",
        "VS-069": "DRONE-Q-000005",
        "VS-002": "DRONE-Q-000006",
        "VS-003": "DRONE-Q-000007",
        "VS-015": "DRONE-Q-000008",
        "VS-021": "DRONE-Q-000009",
        "VS-022": "DRONE-Q-000010",
        "VS-005": "DRONE-Q-000011",
        "VS-006": "DRONE-Q-000012",
        "VS-016": "DRONE-Q-000013",
        "VS-007": "DRONE-Q-000014",
        "VS-008": "DRONE-Q-000015",
        "VS-009": "DRONE-Q-000016",
        "VS-017": "DRONE-Q-000017",
    }
    B1A_EXPECTATIONS = {
        "DRONE-Q-000006": {
            "correct_choice": "B",
            "source_locator": "教則 第6章 6.1.4（教則表示ページ65 / PDF viewer 71）",
            "notes": (
                "slot_id=VS-002",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D4-T01-KT001",
                "family=H2",
                "variant=primary",
            ),
        },
        "DRONE-Q-000007": {
            "correct_choice": "C",
            "source_locator": "教則 第6章 6.1.4（教則表示ページ65 / PDF viewer 71）",
            "notes": (
                "slot_id=VS-003",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D4-T01-KT001",
                "family=H2",
                "alternate_of=VS-002",
            ),
        },
        "DRONE-Q-000008": {
            "correct_choice": "A",
            "source_locator": "教則 第6章 6.1.5（教則表示ページ65 / PDF viewer 71）",
            "notes": (
                "slot_id=VS-015",
                "primary_role=DEEP_HELDOUT",
                "kt_id=D4-T01-KT001",
                "family=H5",
            ),
        },
        "DRONE-Q-000009": {
            "correct_choice": "C",
            "source_locator": "教則 第6章 6.1.5（教則表示ページ65 / PDF viewer 71）",
            "notes": (
                "slot_id=VS-021",
                "primary_role=DEEP_REPLICATION_A",
                "kt_id=D4-T01-KT001",
                "family=H3",
                "form=A",
            ),
        },
        "DRONE-Q-000010": {
            "correct_choice": "B",
            "source_locator": "教則 第6章 6.1.5（教則表示ページ65 / PDF viewer 71）",
            "notes": (
                "slot_id=VS-022",
                "primary_role=DEEP_REPLICATION_B",
                "kt_id=D4-T01-KT001",
                "family=H4",
                "form=B",
            ),
        },
    }
    B1B_EXPECTATIONS = {
        "DRONE-Q-000011": {
            "unit_id": "drone_rules",
            "correct_choice": "B",
            "source_locator": (
                "教則 第3章 3.1.2(2)4)a(2)"
                "（教則表示ページ19 / PDF viewer 25）"
            ),
            "notes": (
                "slot_id=VS-005",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D1-T01-KT010",
                "family=T2",
                "variant=primary",
            ),
        },
        "DRONE-Q-000012": {
            "unit_id": "drone_rules",
            "correct_choice": "C",
            "source_locator": (
                "教則 第3章 3.1.2(2)4)a(2)"
                "（教則表示ページ19 / PDF viewer 25）"
            ),
            "notes": (
                "slot_id=VS-006",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D1-T01-KT010",
                "family=T2",
                "alternate_of=VS-005",
            ),
        },
        "DRONE-Q-000013": {
            "unit_id": "drone_rules",
            "correct_choice": "A",
            "source_locator": (
                "教則 第3章 3.1.2(2)4)a(2)①"
                "（教則表示ページ19 / PDF viewer 25）"
            ),
            "notes": (
                "slot_id=VS-016",
                "primary_role=DEEP_HELDOUT",
                "kt_id=D1-T01-KT010",
                "family=T3",
                "ordinary_shielding_exception=true",
                "level_3_5=false",
            ),
        },
        "DRONE-Q-000014": {
            "unit_id": "drone_systems",
            "correct_choice": "C",
            "source_locator": (
                "教則 第4章 4.5.3(3)（教則表示ページ50 / PDF viewer 56）; "
                "supporting 4.5.1(1)2)"
                "（教則表示ページ47 / PDF viewer 53）"
            ),
            "notes": (
                "slot_id=VS-007",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D2-T05-KT011",
                "family=G1",
                "variant=primary",
            ),
        },
        "DRONE-Q-000015": {
            "unit_id": "drone_systems",
            "correct_choice": "A",
            "source_locator": (
                "教則 第4章 4.5.3(3)"
                "（教則表示ページ50 / PDF viewer 56）"
            ),
            "notes": (
                "slot_id=VS-008",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D2-T05-KT011",
                "family=G2",
            ),
        },
        "DRONE-Q-000016": {
            "unit_id": "drone_systems",
            "correct_choice": "B",
            "source_locator": (
                "教則 第4章 4.5.3(3)（教則表示ページ50 / PDF viewer 56）; "
                "supporting 4.5.1(1)2)"
                "（教則表示ページ47 / PDF viewer 53）"
            ),
            "notes": (
                "slot_id=VS-009",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D2-T05-KT011",
                "family=G1",
                "alternate_of=VS-007",
            ),
        },
        "DRONE-Q-000017": {
            "unit_id": "drone_systems",
            "correct_choice": "C",
            "source_locator": (
                "教則 第4章 4.5.3(3)"
                "（教則表示ページ50 / PDF viewer 56）"
            ),
            "notes": (
                "slot_id=VS-017",
                "primary_role=DEEP_HELDOUT",
                "kt_id=D2-T05-KT011",
                "family=G3",
            ),
        },
    }
    B1B_CONTENT_FREEZE_EXPECTATIONS = {
        "DRONE-Q-000012": {
            "question": (
                "飛行範囲の外周からの保証された落下距離が6mである。\n\n"
                "飛行に関与しない第三者Xは、飛行範囲の外周の最も近い点から"
                "外側へ4m、第三者Yは、外側へ9m離れた位置にいる。どちらも"
                "飛行経路の直下ではなく、遮蔽物については考慮しないものとする。"
                "\n\n第三者上空の判定として適切なものはどれか。"
            ),
            "choice1": "XとYの両方について、第三者上空に該当する",
            "choice2": "Yについてのみ、第三者上空に該当する",
            "choice3": "Xについてのみ、第三者上空に該当する",
        },
        "DRONE-Q-000014": {
            "question": (
                "飛行中、GNSSの測位精度が不安定になった。捕捉している衛星数は"
                "十分で、受信環境のノイズも大きくない。一方、周囲の建物で反射"
                "した衛星信号が、複数の経路から受信機へ届いている。\n\n"
                "この状況から直接読み取れる、測位精度へ影響している要因として"
                "最も適切なものはどれか。"
            ),
        },
        "DRONE-Q-000016": {
            "question": (
                "同じ無人航空機のGNSS受信状態を、同じ時間帯に2か所で確認した。"
                "\n\n地点Pは上空が開け、周囲に大きな建物が少ない。地点Qは周囲"
                "に建物が多く、建物で反射した衛星信号が複数の経路から受信機へ"
                "届き得る環境である。捕捉している衛星数と受信環境のノイズには、"
                "2地点で大きな差は確認されていない。\n\n地点QでGNSS測位精度が"
                "悪化した場合、この状況から直接考えられる要因として最も適切な"
                "ものはどれか。"
            ),
        },
    }

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

    def test_drone_namespace_preserves_permanent_mappings_and_invariants(self) -> None:
        result = validate_bank(self.bank)
        self.assertTrue(result.is_valid, [str(issue) for issue in result.issues])

        inputs = load_bank_inputs(self.bank)
        question_ids = [row["question_id"] for row in inputs.questions]
        registry_ids = [row["question_id"] for row in inputs.id_registry]
        question_by_id = {row["question_id"]: row for row in inputs.questions}
        registry_by_id = {row["question_id"]: row for row in inputs.id_registry}

        self.assertEqual(len(question_ids), len(set(question_ids)))
        self.assertEqual(len(registry_ids), len(set(registry_ids)))
        self.assertTrue(set(question_ids).issubset(registry_ids))
        self.assertTrue(
            all(
                QUESTION_ID_PATTERN.fullmatch(question_id)
                for question_id in question_ids
            )
        )
        self.assertTrue(all(row["status"] == "used" for row in inputs.id_registry))
        self.assertTrue(
            all(not row["first_used_bank_revision"] for row in inputs.id_registry)
        )
        self.assertEqual(inputs.metadata["app_key"], "drone_second_class")
        self.assertEqual(inputs.metadata["question_identity_policy"], "explicit_v1")
        self.assertEqual(inputs.released_questions, [])

        for slot_id, question_id in self.PERMANENT_SLOT_TO_ID.items():
            self.assertIn(question_id, question_by_id)
            self.assertIn(question_id, registry_by_id)
            self.assertIn(
                f"slot_id={slot_id}", question_by_id[question_id]["notes_internal"]
            )
            self.assertIn(slot_id, registry_by_id[question_id]["notes"])

        for question_id, expected in self.B1A_EXPECTATIONS.items():
            question = question_by_id[question_id]
            self.assertEqual(question["question_version"], "1")
            self.assertEqual(question["status"], "draft")
            self.assertEqual(
                question["correct_choice"], expected["correct_choice"]
            )
            self.assertEqual(question["source_id"], "MLIT-UAS-SAFETY-GUIDE-5")
            self.assertEqual(
                question["source_locator"], expected["source_locator"]
            )
            self.assertIn(
                "verification_state=author_source_verified",
                question["notes_internal"],
            )
            self.assertIn(
                "independent_reviewed=false", question["notes_internal"]
            )
            self.assertIn(
                "subject_matter_expert_reviewed=false",
                question["notes_internal"],
            )
            self.assertIn("release_approved=false", question["notes_internal"])
            for note in expected["notes"]:
                self.assertIn(note, question["notes_internal"])

        for question_id, expected in self.B1B_EXPECTATIONS.items():
            question = question_by_id[question_id]
            self.assertEqual(question["question_version"], "1")
            self.assertEqual(question["status"], "draft")
            self.assertEqual(question["deck_id"], "drone_second_class_exam")
            self.assertEqual(question["unit_id"], expected["unit_id"])
            self.assertEqual(question["difficulty"], "2")
            self.assertEqual(question["importance"], "2")
            self.assertEqual(question["is_free"], "false")
            self.assertEqual(question["valid_from"], "2026-07-14")
            self.assertEqual(question["valid_until"], "")
            self.assertEqual(question["last_reviewed_at"], "2026-08-18")
            self.assertEqual(question["supersedes_id"], "")
            self.assertEqual(question["correct_choice"], expected["correct_choice"])
            self.assertEqual(question["source_id"], "MLIT-UAS-SAFETY-GUIDE-5")
            self.assertEqual(question["source_locator"], expected["source_locator"])
            self.assertIn(
                "verification_state=author_source_verified",
                question["notes_internal"],
            )
            self.assertIn("independent_reviewed=false", question["notes_internal"])
            self.assertIn(
                "subject_matter_expert_reviewed=false",
                question["notes_internal"],
            )
            self.assertIn("release_approved=false", question["notes_internal"])
            for note in expected["notes"]:
                self.assertIn(note, question["notes_internal"])

        held_out_t3 = question_by_id["DRONE-Q-000013"]
        self.assertNotIn("level_3_5=true", held_out_t3["notes_internal"])
        self.assertNotIn("moving_vehicle=", held_out_t3["notes_internal"])

        for question_id, fields in self.B1B_CONTENT_FREEZE_EXPECTATIONS.items():
            question = question_by_id[question_id]
            for field, expected_text in fields.items():
                self.assertEqual(question[field], expected_text)

        sentinel = question_by_id["DRONE-Q-000004"]
        sentinel_neighbor = question_by_id["DRONE-Q-000005"]
        self.assertIn("slot_id=VS-039", sentinel["notes_internal"])
        self.assertIn("family=US-C", sentinel["notes_internal"])
        self.assertIn("slot_id=VS-069", sentinel_neighbor["notes_internal"])
        self.assertIn("coverage=COV-25", sentinel_neighbor["notes_internal"])
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
        rows[0]["question_id"] = "DRONE-Q-999999"
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
