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
        "VS-010": "DRONE-Q-000018",
        "VS-011": "DRONE-Q-000019",
        "VS-018": "DRONE-Q-000020",
        "VS-019": "DRONE-Q-000021",
        "VS-012": "DRONE-Q-000022",
        "VS-013": "DRONE-Q-000023",
        "VS-014": "DRONE-Q-000024",
        "VS-020": "DRONE-Q-000025",
        "VS-023": "DRONE-Q-000026",
        "VS-030": "DRONE-Q-000027",
        "VS-024": "DRONE-Q-000028",
        "VS-031": "DRONE-Q-000029",
        "VS-025": "DRONE-Q-000030",
        "VS-032": "DRONE-Q-000031",
        "VS-026": "DRONE-Q-000032",
        "VS-033": "DRONE-Q-000033",
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
    B1C_EXPECTATIONS = {
        "DRONE-Q-000018": {
            "correct_choice": "B",
            "source_locator": (
                "教則 第5章 5.2.2(4)"
                "（教則表示ページ60 / PDF viewer 66）"
            ),
            "notes": (
                "slot_id=VS-010",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D3-T02-KT008",
                "family=A1",
                "construct=transition_trigger",
            ),
        },
        "DRONE-Q-000019": {
            "correct_choice": "A",
            "source_locator": (
                "教則 第5章 5.2.2(4)"
                "（教則表示ページ60 / PDF viewer 66）"
            ),
            "notes": (
                "slot_id=VS-011",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D3-T02-KT008",
                "family=A4",
                "construct=takeover_preparedness",
            ),
        },
        "DRONE-Q-000020": {
            "correct_choice": "C",
            "source_locator": (
                "教則 第5章 5.2.2(4)"
                "（教則表示ページ60 / PDF viewer 66）"
            ),
            "notes": (
                "slot_id=VS-018",
                "primary_role=DEEP_HELDOUT",
                "kt_id=D3-T02-KT008",
                "family=A2",
                "construct=immediate_flight_control_concern",
            ),
        },
        "DRONE-Q-000021": {
            "correct_choice": "A",
            "source_locator": (
                "教則 第5章 5.2.2(4)"
                "（教則表示ページ60 / PDF viewer 66）; "
                "supporting 4.1.4(1)"
                "（教則表示ページ35 / PDF viewer 41）"
            ),
            "notes": (
                "slot_id=VS-019",
                "primary_role=DEEP_HELDOUT",
                "kt_id=D3-T02-KT008",
                "family=A3",
                "construct=situational_verification",
                "aircraft_scope=multirotor",
            ),
        },
        "DRONE-Q-000022": {
            "correct_choice": "A",
            "source_locator": (
                "教則 第5章 5.4.1"
                "（教則表示ページ62 / PDF viewer 68）"
            ),
            "notes": (
                "slot_id=VS-012",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D3-T04-KT002",
                "family=E1",
                "variant=primary",
                "construct=stage_classification",
            ),
        },
        "DRONE-Q-000023": {
            "correct_choice": "B",
            "source_locator": (
                "教則 第5章 5.4.1"
                "（教則表示ページ62 / PDF viewer 68）"
            ),
            "notes": (
                "slot_id=VS-013",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D3-T04-KT002",
                "family=E2",
                "construct=early_threat_management",
            ),
        },
        "DRONE-Q-000024": {
            "correct_choice": "B",
            "source_locator": (
                "教則 第5章 5.4.1"
                "（教則表示ページ62 / PDF viewer 68）"
            ),
            "notes": (
                "slot_id=VS-014",
                "primary_role=DEEP_OBSERVED",
                "kt_id=D3-T04-KT002",
                "family=E1",
                "alternate_of=VS-012",
                "construct=stage_classification",
            ),
        },
        "DRONE-Q-000025": {
            "correct_choice": "B",
            "source_locator": (
                "教則 第5章 5.4.1"
                "（教則表示ページ62 / PDF viewer 68）"
            ),
            "notes": (
                "slot_id=VS-020",
                "primary_role=DEEP_HELDOUT",
                "kt_id=D3-T04-KT002",
                "family=E3",
                "construct=recovery_judgment",
            ),
        },
    }
    B2A_EXPECTATIONS = {
        "DRONE-Q-000026": {
            "unit_id": "drone_rules",
            "correct_choice": "A",
            "source_locator": (
                "教則 第3章 3.1.2(2)1)c"
                "（教則表示ページ15 / PDF viewer 21）"
            ),
            "notes": (
                "slot_id=VS-023",
                "primary_role=BREADTH_OBSERVED",
                "kt_id=D1-T01-KT006",
                "family=HB1-150",
                "construct=terrain_reference_airspace_classification",
                "counterbalance=YES",
            ),
        },
        "DRONE-Q-000027": {
            "unit_id": "drone_rules",
            "correct_choice": "B",
            "source_locator": (
                "教則 第3章 3.1.2(2)1)d"
                "（教則表示ページ15 / PDF viewer 21）"
            ),
            "notes": (
                "slot_id=VS-030",
                "primary_role=BREADTH_HELDOUT",
                "kt_id=D1-T01-KT006",
                "family=HB1-DID",
                "construct=did_industrial_only_zone_exception",
                "counterbalance=YES",
                "additional_authority=MLIT_NOTICE_435",
                "notice_promulgated=2026-03-31",
                "mlit_web_announcement=2026-06-30",
            ),
        },
        "DRONE-Q-000028": {
            "unit_id": "drone_rules",
            "correct_choice": "B",
            "source_locator": (
                "教則 第3章 3.1 飛行形態の分類"
                "（教則表示ページ8–9 / PDF viewer 14–15）"
            ),
            "notes": (
                "slot_id=VS-024",
                "primary_role=BREADTH_OBSERVED",
                "kt_id=D1-T01-KT009",
                "family=HB2-II-III",
                "construct=category_ii_vs_iii_classification",
                "counterbalance=PARTIAL_ONLY",
            ),
        },
        "DRONE-Q-000029": {
            "unit_id": "drone_rules",
            "correct_choice": "A",
            "source_locator": (
                "教則 第3章 3.1 飛行形態の分類"
                "（教則表示ページ9 / PDF viewer 15）"
            ),
            "notes": (
                "slot_id=VS-031",
                "primary_role=BREADTH_HELDOUT",
                "kt_id=D1-T01-KT009",
                "family=HB2-IIA-IIB",
                "construct=category_iia_vs_iib_classification",
                "counterbalance=PARTIAL_ONLY",
            ),
        },
        "DRONE-Q-000030": {
            "unit_id": "drone_rules",
            "correct_choice": "A",
            "source_locator": (
                "教則 第3章 3.1.2(2)3)c"
                "（教則表示ページ18 / PDF viewer 24）"
            ),
            "notes": (
                "slot_id=VS-025",
                "primary_role=BREADTH_OBSERVED",
                "kt_id=D1-T01-KT015",
                "family=HB3-CONDITIONS",
                "construct=tether_exception_qualification",
                "counterbalance=YES",
            ),
        },
        "DRONE-Q-000031": {
            "unit_id": "drone_rules",
            "correct_choice": "C",
            "source_locator": (
                "教則 第3章 3.1.2(2)3)c"
                "（教則表示ページ18 / PDF viewer 24）"
            ),
            "notes": (
                "slot_id=VS-032",
                "primary_role=BREADTH_HELDOUT",
                "kt_id=D1-T01-KT015",
                "family=HB3-TOWING",
                "construct=towing_nonexample_boundary",
                "counterbalance=YES",
            ),
        },
        "DRONE-Q-000032": {
            "unit_id": "drone_systems",
            "correct_choice": "B",
            "source_locator": (
                "教則 第4章 4.6.1(2)"
                "（教則表示ページ50 / PDF viewer 56）"
            ),
            "notes": (
                "slot_id=VS-026",
                "primary_role=BREADTH_OBSERVED",
                "kt_id=D2-T06-KT002",
                "family=HB4-STORAGE",
                "construct=long_term_storage_charge",
                "counterbalance=YES",
            ),
        },
        "DRONE-Q-000033": {
            "unit_id": "drone_systems",
            "correct_choice": "C",
            "source_locator": (
                "教則 第4章 4.6.1(3)"
                "（教則表示ページ51 / PDF viewer 57）"
            ),
            "notes": (
                "slot_id=VS-033",
                "primary_role=BREADTH_HELDOUT",
                "kt_id=D2-T06-KT002",
                "family=HB4-REPLACEMENT",
                "construct=swelling_replacement_decision",
                "counterbalance=YES",
            ),
        },
    }
    B2A_REGISTRY_NOTES = {
        "DRONE-Q-000026": (
            "VS-023; B2A HB1 150m; BREADTH_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000027": (
            "VS-030; B2A HB1 DID; BREADTH_HELDOUT; permanent ID; pre-release"
        ),
        "DRONE-Q-000028": (
            "VS-024; B2A HB2 II-III; BREADTH_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000029": (
            "VS-031; B2A HB2 IIA-IIB; BREADTH_HELDOUT; permanent ID; pre-release"
        ),
        "DRONE-Q-000030": (
            "VS-025; B2A HB3 conditions; BREADTH_OBSERVED; permanent ID; "
            "pre-release"
        ),
        "DRONE-Q-000031": (
            "VS-032; B2A HB3 towing; BREADTH_HELDOUT; permanent ID; pre-release"
        ),
        "DRONE-Q-000032": (
            "VS-026; B2A HB4 storage; BREADTH_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000033": (
            "VS-033; B2A HB4 replacement; BREADTH_HELDOUT; permanent ID; "
            "pre-release"
        ),
    }
    B2A_PAIR_EXPECTATIONS = (
        ("DRONE-Q-000026", "DRONE-Q-000027", "D1-T01-KT006", "YES"),
        (
            "DRONE-Q-000028",
            "DRONE-Q-000029",
            "D1-T01-KT009",
            "PARTIAL_ONLY",
        ),
        ("DRONE-Q-000030", "DRONE-Q-000031", "D1-T01-KT015", "YES"),
        ("DRONE-Q-000032", "DRONE-Q-000033", "D2-T06-KT002", "YES"),
    )
    B1C_REGISTRY_NOTES = {
        "DRONE-Q-000018": (
            "VS-010; B1C A1; DEEP_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000019": (
            "VS-011; B1C A4; DEEP_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000020": (
            "VS-018; B1C A2; DEEP_HELDOUT; permanent ID; pre-release"
        ),
        "DRONE-Q-000021": (
            "VS-019; B1C A3; DEEP_HELDOUT; permanent ID; pre-release"
        ),
        "DRONE-Q-000022": (
            "VS-012; B1C E1 primary; DEEP_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000023": (
            "VS-013; B1C E2; DEEP_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000024": (
            "VS-014; B1C E1 alternate; DEEP_OBSERVED; permanent ID; pre-release"
        ),
        "DRONE-Q-000025": (
            "VS-020; B1C E3; DEEP_HELDOUT; permanent ID; pre-release"
        ),
    }
    B2A_CONTENT_FREEZE_EXPECTATIONS = {
        "DRONE-Q-000026": {
            "question": (
                "離陸地点から130m上方を飛行している無人航空機がある。現在の"
                "機体直下の地表は、離陸地点の地表より40m低い。\n\n"
                "このとき「高度150m以上の空域」の判定として最も適切なものは"
                "どれか。"
            ),
            "choice1": "高度150m以上の空域に該当する",
            "choice2": "離陸地点からの高度差が130mなので該当しない",
            "choice3": "海抜高度が示されていないため判定できない",
            "correct_choice": "A",
            "explanation": (
                "150mの基準は離陸地点や海抜高度ではなく、飛行中の機体直下の"
                "地表・水面との高度差である。この場合、その高度差は170mになる。"
            ),
            "source_locator": (
                "教則 第3章 3.1.2(2)1)c"
                "（教則表示ページ15 / PDF viewer 21）"
            ),
        },
        "DRONE-Q-000027": {
            "question": (
                "地図上では人口集中地区（DID）として表示されている区域で飛行を"
                "計画している。確認したところ、その場所は都市計画法第8条第1項"
                "第1号の工業専用地域内である。\n\n他の規制対象空域や飛行方法"
                "には該当しないものとすると、DIDに係る扱いとして最も適切な"
                "ものはどれか。"
            ),
            "choice1": (
                "地図上でDIDと表示されているため、DIDに係る許可手続き等が"
                "必要である"
            ),
            "choice2": (
                "工業専用地域内の除外区域に該当するため、DIDに係る許可手続き等"
                "は不要である"
            ),
            "choice3": (
                "DIDに係る許可手続き等の要否は、操縦者が技能証明を保有して"
                "いるかだけで決まる"
            ),
            "correct_choice": "B",
            "explanation": (
                "現行制度では、都市計画法上の工業専用地域内の区域は「人又は"
                "家屋の密集している地域」から除外され、DIDに係る飛行許可は"
                "不要となる。その他の空域・飛行方法の規制は別途判定する。"
            ),
            "source_locator": (
                "教則 第3章 3.1.2(2)1)d"
                "（教則表示ページ15 / PDF viewer 21）"
            ),
        },
        "DRONE-Q-000028": {
            "question": (
                "ある特定飛行について、飛行経路下に第三者が立ち入らないよう"
                "立入管理措置を講じたうえで飛行する。\n\nこの飛行形態の分類"
                "として最も適切なものはどれか。"
            ),
            "choice1": "カテゴリーI",
            "choice2": "カテゴリーII",
            "choice3": "カテゴリーIII",
            "correct_choice": "B",
            "explanation": (
                "特定飛行のうち、飛行経路下への第三者の立入りを管理する措置を"
                "講じて行うものがCategory IIである。Category IIIは、そのような"
                "立入管理措置を講じず第三者上空で行う特定飛行である。"
            ),
            "source_locator": (
                "教則 第3章 3.1 飛行形態の分類"
                "（教則表示ページ8–9 / PDF viewer 14–15）"
            ),
        },
        "DRONE-Q-000029": {
            "question": (
                "いずれも立入管理措置を講じ、最大離陸重量25kg未満の無人航空機"
                "で行う特定飛行とする。また、記載した条件以外にカテゴリーII-A"
                "に該当する条件はないものとする。\n\n* 飛行X：危険物を輸送する"
                "\n* 飛行Y：夜間に飛行する\n\nカテゴリーII-A / II-Bの分類"
                "として最も適切なものはどれか。"
            ),
            "choice1": "X = II-A、Y = II-B",
            "choice2": "X = II-B、Y = II-A",
            "choice3": "X = II-A、Y = II-A",
            "correct_choice": "A",
            "explanation": (
                "Category IIのうち危険物輸送はII-Aに含まれる。一方、25kg未満で、"
                "他のII-A条件に該当しない夜間飛行は「その他のCategory II」"
                "としてII-Bに分類される。"
            ),
            "source_locator": (
                "教則 第3章 3.1 飛行形態の分類"
                "（教則表示ページ9 / PDF viewer 15）"
            ),
        },
        "DRONE-Q-000030": {
            "question": (
                "係留飛行の例外に必要な条件の組合せとして、教則に最も合うものは"
                "どれか。"
            ),
            "choice1": (
                "十分な強度の25mの紐で係留し、飛行可能範囲への第三者の"
                "立入管理措置を講じる"
            ),
            "choice2": (
                "十分な強度の35mの紐で係留し、飛行可能範囲への第三者の"
                "立入管理措置を講じる"
            ),
            "choice3": (
                "十分な強度の25mの紐で係留するが、飛行可能範囲への第三者の"
                "立入管理措置は講じない"
            ),
            "correct_choice": "A",
            "explanation": (
                "係留飛行の例外では、十分な強度を持つ30m以下の紐等による係留と、"
                "飛行可能範囲への第三者立入管理等が条件となる。"
            ),
            "source_locator": (
                "教則 第3章 3.1.2(2)3)c"
                "（教則表示ページ18 / PDF viewer 24）"
            ),
        },
        "DRONE-Q-000031": {
            "question": (
                "無人航空機を紐につなぎ、その紐を操縦者が手に持って歩いて移動"
                "しながら飛行させている。\n\nこの飛行の扱いとして、教則に"
                "最も合うものはどれか。"
            ),
            "choice1": (
                "無人航空機が紐につながっているため、係留飛行として扱う"
            ),
            "choice2": "操縦者が紐を直接管理しているため、係留飛行として扱う",
            "choice3": (
                "人が紐を持って移動しながら行う飛行はえい航であり、係留には"
                "該当しない"
            ),
            "correct_choice": "C",
            "explanation": (
                "人が紐等を持って移動しながら無人航空機を飛行させる行為は"
                "えい航であり、係留には該当しない。"
            ),
            "source_locator": (
                "教則 第3章 3.1.2(2)3)c"
                "（教則表示ページ18 / PDF viewer 24）"
            ),
        },
        "DRONE-Q-000032": {
            "question": (
                "LiPoバッテリーを長期間使用しない場合の保管方法として、教則に"
                "最も合うものはどれか。"
            ),
            "choice1": "満充電にして保管する",
            "choice2": "充電60%程度を目安にして保管する",
            "choice3": "飛行終了後の放電状態のまま保管する",
            "correct_choice": "B",
            "explanation": (
                "長期間使用しない場合は、劣化を遅らせるため充電60%程度を目安に"
                "保管する。満充電状態や飛行後の放電状態での長期保管は避ける。"
            ),
            "source_locator": (
                "教則 第4章 4.6.1(2)"
                "（教則表示ページ50 / PDF viewer 56）"
            ),
        },
        "DRONE-Q-000033": {
            "question": (
                "飛行前点検でLiPoバッテリーが膨らんでいることに気付いた。充電"
                "自体は可能で、直前の飛行でも大きな容量低下は感じていない。"
                "\n\n教則に沿った対応として最も適切なものはどれか。"
            ),
            "choice1": (
                "充放電できる間は使用を続け、飛行時間を短くして経過を見る"
            ),
            "choice2": (
                "膨張の程度を記録し、容量低下が明確になった時点で交換する"
            ),
            "choice3": (
                "内部に可燃性ガスが発生している可能性を考慮し、早めに交換する"
            ),
            "correct_choice": "C",
            "explanation": (
                "教則では、LiPoが膨らんでいる場合は内部に可燃性ガスが発生して"
                "いる可能性があるため、早めに交換するとしている。"
            ),
            "source_locator": (
                "教則 第4章 4.6.1(3)"
                "（教則表示ページ51 / PDF viewer 57）"
            ),
        },
    }
    B1C_CONTENT_FREEZE_EXPECTATIONS = {
        "DRONE-Q-000018": {
            "question": (
                "自動操縦で飛行している無人航空機について、飛行状態が次第に"
                "不安定になり、操縦者も「安定した自動飛行を維持できていない」"
                "と判断した。\n\n教則の考え方に最も合う判断はどれか。"
            ),
            "choice1": "自動操縦の設定を変更しながら、まず現在のmodeを維持する",
            "choice2": (
                "不安定な飛行と判断した状況として、手動操作への切り替えを"
                "検討する"
            ),
            "choice3": (
                "不安定となった原因を特定してから、操縦modeを変更するか決める"
            ),
            "correct_choice": "B",
            "explanation": (
                "教則は、自動操縦中に何らかの原因で不安定な飛行と判断した"
                "場合を、手動操作へ切り替える場合の一つとして示している。"
            ),
            "source_locator": (
                "教則 第5章 5.2.2(4)"
                "（教則表示ページ60 / PDF viewer 66）"
            ),
        },
        "DRONE-Q-000019": {
            "question": (
                "自動操縦を中心とする飛行を計画している。飛行中には状況変化に"
                "よって手動操縦への切り替えが必要になる可能性もある。\n\n"
                "事前の運航体制として教則の考え方に最も合うものはどれか。"
            ),
            "choice1": (
                "必要となった場合に速やかに手動操縦へ切り替えられる体制を"
                "事前に整えておく"
            ),
            "choice2": (
                "状況変化が起きた時点で、その場の状況に合わせて手動切替の"
                "対応方法を組み立てる"
            ),
            "choice3": (
                "自動操縦を継続できるかの判断方法を事前に決め、手動切替の体制は"
                "必要になった後に整える"
            ),
            "correct_choice": "A",
            "explanation": (
                "教則は、必要に応じて手動操縦への切り替えを速やかに行える"
                "体制をあらかじめ整えておくとしている。"
            ),
            "source_locator": (
                "教則 第5章 5.2.2(4)"
                "（教則表示ページ60 / PDF viewer 66）"
            ),
        },
        "DRONE-Q-000020": {
            "question": (
                "自動操縦から手動操縦へ切り替えた直後である。切り替え自体は"
                "正常に完了した。\n\nこの直後の操縦上の備えとして、教則が示す"
                "内容に最も合うものはどれか。"
            ),
            "choice1": (
                "自動操縦中の設定値を確認し、手動操作の入力値をそれに合わせる"
                "ことを優先する"
            ),
            "choice2": (
                "現在位置と飛行計画上の予定位置との差を確認し、経路修正を"
                "優先する"
            ),
            "choice3": "急な飛行速度の低下や失速に備えた操作準備を行う",
            "correct_choice": "C",
            "explanation": (
                "教則は、手動操縦へ切り替えた後、急な飛行速度の低下や失速に"
                "備えた操作準備が必要としている。"
            ),
            "source_locator": (
                "教則 第5章 5.2.2(4)"
                "（教則表示ページ60 / PDF viewer 66）"
            ),
        },
        "DRONE-Q-000021": {
            "question": (
                "ホバリングが可能な回転翼航空機（マルチローター）を、自動操縦"
                "から手動操縦へ切り替えた。切り替えを終え、飛行速度についても"
                "安定した状態を確認している。\n\nこの後の確認として、教則の内容に"
                "最も合うものはどれか。"
            ),
            "choice1": (
                "機体の向きと障害物への接近を確認し、ホバリングで機体の安定性と"
                "周囲の安全を確認する"
            ),
            "choice2": (
                "自動操縦時のroute設定と予定速度を確認し、自動操縦へ戻す条件を"
                "整理する"
            ),
            "choice3": (
                "送信機のflight logと作業進捗を確認し、予定経路との差を記録する"
            ),
            "correct_choice": "A",
            "explanation": (
                "手動操縦への切り替え後は、障害物への接近を避けるための機体方向"
                "確認に加え、ホバリングして機体の安定性や周囲の安全を確認する"
                "必要がある。今回の機体はホバリング可能なマルチローターとして"
                "stemで固定している。"
            ),
            "source_locator": (
                "教則 第5章 5.2.2(4)"
                "（教則表示ページ60 / PDF viewer 66）; "
                "supporting 4.1.4(1)"
                "（教則表示ページ35 / PDF viewer 41）"
            ),
        },
        "DRONE-Q-000022": {
            "question": (
                "飛行中、次の二つの状態が生じた。\n\n"
                "① 周囲の気象状況が変化し、運航へ影響を及ぼし得る状況となった。"
                "\n\n② その後、運航上の問題を経て、機体の安全マージンが低下した"
                "状態に至った。\n\nTEMにおける①と②の分類として、最も適切な"
                "ものはどれか。"
            ),
            "choice1": "① Threat ／ ② UAS",
            "choice2": "① Threat ／ ② Error",
            "choice3": "① Error ／ ② UAS",
            "correct_choice": "A",
            "explanation": (
                "教則は気象の変化をErrorにつながり得るThreatの例として挙げて"
                "いる。また、安全マージンが低下した航空機の状態をUASとしている。"
            ),
            "source_locator": (
                "教則 第5章 5.4.1"
                "（教則表示ページ62 / PDF viewer 68）"
            ),
        },
        "DRONE-Q-000023": {
            "question": (
                "飛行中、飛行空域周辺の最新情報から天候が変化しつつあることを"
                "把握した。まだ操縦上のErrorやUASは生じていない。\n\n"
                "TEMの考え方に最も合う対応はどれか。"
            ),
            "choice1": (
                "実際の操縦Errorが確認されるまでは初期計画を基準とし、天候情報は"
                "継続監視にとどめる"
            ),
            "choice2": (
                "利用可能な最新情報等を使い、Errorにつながり得るThreatとして"
                "早期に把握・管理する"
            ),
            "choice3": (
                "機体がUASに入ったかどうかを確認してから、天候変化への対応を"
                "開始する"
            ),
            "correct_choice": "B",
            "explanation": (
                "TEMでは、利用可能なresourceを活用して、Errorにつながりかねない"
                "Threatの発生状況を早期に把握・管理する。教則は周辺状況の最新情報"
                "などをresourceの例としている。"
            ),
            "source_locator": (
                "教則 第5章 5.4.1"
                "（教則表示ページ62 / PDF viewer 68）"
            ),
        },
        "DRONE-Q-000024": {
            "question": (
                "ある飛行の運航記録に、次の二つの状態が記録されていた。\n\n"
                "記録P：飛行中に機材不具合が発生した。\n\n"
                "記録Q：その後、機体は安全マージンが低下した状態に至った。\n\n"
                "TEMにおけるPとQの分類として、最も適切なものはどれか。"
            ),
            "choice1": "P = Error ／ Q = UAS",
            "choice2": "P = Threat ／ Q = UAS",
            "choice3": "P = Threat ／ Q = Error",
            "correct_choice": "B",
            "explanation": (
                "教則は機材不具合をErrorにつながり得るThreatの例として挙げて"
                "いる。また、安全マージンが低下した航空機の状態はUASに"
                "位置付けられる。"
            ),
            "source_locator": (
                "教則 第5章 5.4.1"
                "（教則表示ページ62 / PDF viewer 68）"
            ),
        },
        "DRONE-Q-000025": {
            "question": (
                "運航中に操縦Errorが発生し、機体は安全マージンの低下したUASに"
                "至った。ただし、まだ事故等は発生していない。\n\n"
                "TEMの考え方に最も合うものはどれか。"
            ),
            "choice1": (
                "まず最初のThreatの原因分析を完了し、その後に機体状態への対応を"
                "決める"
            ),
            "choice2": (
                "ErrorやUASに至った後でも、事故等へ進ませないための適切な対応を"
                "行う"
            ),
            "choice3": (
                "UASに至った段階でTEMによるmanagementは終了し、その後は運航"
                "終了後の分析を中心とする"
            ),
            "correct_choice": "B",
            "explanation": (
                "TEMはThreatの早期管理だけでなく、万一ErrorやUASに至った場合でも"
                "事故等へ至らないよう適切に対処する考え方を含む。"
            ),
            "source_locator": (
                "教則 第5章 5.4.1"
                "（教則表示ページ62 / PDF viewer 68）"
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

    def test_b1c_measurement_bindings_and_content_freeze(self) -> None:
        inputs = load_bank_inputs(self.bank)
        question_by_id = {row["question_id"]: row for row in inputs.questions}
        registry_by_id = {row["question_id"]: row for row in inputs.id_registry}

        for question_id, expected in self.B1C_EXPECTATIONS.items():
            question = question_by_id[question_id]
            self.assertEqual(question["question_version"], "1")
            self.assertEqual(question["status"], "draft")
            self.assertEqual(question["deck_id"], "drone_second_class_exam")
            self.assertEqual(question["unit_id"], "drone_operations")
            self.assertEqual(question["difficulty"], "2")
            self.assertEqual(question["importance"], "2")
            self.assertEqual(question["is_free"], "false")
            self.assertEqual(question["valid_from"], "2026-07-14")
            self.assertEqual(question["valid_until"], "")
            self.assertEqual(question["last_reviewed_at"], "2026-08-18")
            self.assertEqual(question["supersedes_id"], "")
            self.assertEqual(question["tags"], "")
            self.assertEqual(question["choice4"], "")
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

            registry = registry_by_id[question_id]
            self.assertEqual(registry["status"], "used")
            self.assertEqual(registry["first_used_bank_revision"], "")
            self.assertEqual(registry["retired_at"], "")
            self.assertEqual(registry["replacement_id"], "")
            self.assertEqual(registry["notes"], self.B1C_REGISTRY_NOTES[question_id])

        for question_id, fields in self.B1C_CONTENT_FREEZE_EXPECTATIONS.items():
            question = question_by_id[question_id]
            for field, expected_text in fields.items():
                self.assertEqual(question[field], expected_text)

        vs_019 = question_by_id["DRONE-Q-000021"]
        self.assertIn(
            "ホバリングが可能な回転翼航空機（マルチローター）",
            vs_019["question"],
        )
        self.assertIn("5.2.2(4)", vs_019["source_locator"])
        self.assertIn("4.1.4(1)", vs_019["source_locator"])

        vs_012 = question_by_id["DRONE-Q-000022"]
        self.assertNotIn("操作上のエラーが生じた", vs_012["question"])

        vs_014 = question_by_id["DRONE-Q-000024"]
        self.assertIn("機材不具合", vs_014["question"])
        self.assertNotIn("操縦者の疲労という", vs_014["question"])

    def test_b2a_measurement_bindings_and_content_freeze(self) -> None:
        inputs = load_bank_inputs(self.bank)
        question_by_id = {row["question_id"]: row for row in inputs.questions}
        registry_by_id = {row["question_id"]: row for row in inputs.id_registry}

        for question_id, expected in self.B2A_EXPECTATIONS.items():
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
            self.assertEqual(question["tags"], "")
            self.assertEqual(question["choice4"], "")
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

            registry = registry_by_id[question_id]
            self.assertEqual(registry["status"], "used")
            self.assertEqual(registry["first_used_bank_revision"], "")
            self.assertEqual(registry["retired_at"], "")
            self.assertEqual(registry["replacement_id"], "")
            self.assertEqual(registry["notes"], self.B2A_REGISTRY_NOTES[question_id])

        for question_id, fields in self.B2A_CONTENT_FREEZE_EXPECTATIONS.items():
            question = question_by_id[question_id]
            for field, expected_text in fields.items():
                self.assertEqual(question[field], expected_text)

        for observed_id, held_out_id, kt_id, counterbalance in (
            self.B2A_PAIR_EXPECTATIONS
        ):
            observed_notes = question_by_id[observed_id]["notes_internal"]
            held_out_notes = question_by_id[held_out_id]["notes_internal"]
            self.assertIn("primary_role=BREADTH_OBSERVED", observed_notes)
            self.assertIn("primary_role=BREADTH_HELDOUT", held_out_notes)
            for notes in (observed_notes, held_out_notes):
                self.assertIn(f"kt_id={kt_id}", notes)
                self.assertIn(f"counterbalance={counterbalance}", notes)

        vs_032 = question_by_id["DRONE-Q-000031"]
        vs_032_content = " ".join(
            vs_032[field]
            for field in (
                "question",
                "choice1",
                "choice2",
                "choice3",
                "explanation",
            )
        )
        for leaked_condition in ("第三者の立入管理", "30m", "十分な強度"):
            self.assertNotIn(leaked_condition, vs_032_content)

        vs_030 = question_by_id["DRONE-Q-000027"]
        self.assertIn(
            "他の規制対象空域や飛行方法には該当しないものとすると",
            vs_030["question"],
        )
        self.assertIn(
            "その他の空域・飛行方法の規制は別途判定する",
            vs_030["explanation"],
        )
        vs_030_metadata = {
            key: value
            for item in vs_030["notes_internal"].split(";")
            if "=" in item
            for key, value in (item.strip().split("=", 1),)
        }
        self.assertEqual(
            vs_030_metadata["additional_authority"], "MLIT_NOTICE_435"
        )
        self.assertEqual(vs_030_metadata["notice_promulgated"], "2026-03-31")
        self.assertEqual(vs_030_metadata["mlit_web_announcement"], "2026-06-30")
        self.assertNotEqual(
            vs_030_metadata["notice_promulgated"],
            vs_030_metadata["mlit_web_announcement"],
        )

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
