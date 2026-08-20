from __future__ import annotations

import csv
import json
import shutil
import sys
import tempfile
import unittest
from collections import Counter
from dataclasses import replace
from pathlib import Path


TOOL_DIR = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(TOOL_DIR))

from contract import (  # noqa: E402
    file_sha256,
    formal_snapshot_source_hash,
    load_validation_inputs,
)
from v0_panel_validation import (  # noqa: E402
    build_generated_files,
    build_validation_documents,
    validate_contract,
)


class DroneV0PanelValidationContractTest(unittest.TestCase):
    BANK_ROOT = REPOSITORY_ROOT / "question_banks" / "drone_second_class"
    EXPECTED_SOURCE_HASH = (
        "sha256:19e4ce34e479c6a2b4afda12a30ada0efb173cf7fbe0c360c9e7b88006a82f08"
    )
    EXPECTED_BUNDLE_HASH = (
        "sha256:6c971d88bed58fd635891482f1d153c1787270e19aee61c6473ef50473a01ae2"
    )
    EXPECTED_ROLES = {
        "DEEP_OBSERVED": 14,
        "DEEP_HELDOUT": 6,
        "DEEP_REPLICATION_A": 1,
        "DEEP_REPLICATION_B": 1,
        "BREADTH_OBSERVED": 7,
        "BREADTH_HELDOUT": 7,
        "UNKNOWN_SENTINEL": 8,
        "COVERAGE": 56,
    }

    def setUp(self) -> None:
        self.inputs = load_validation_inputs(self.BANK_ROOT)
        self.bundle, self.manifest = build_validation_documents(self.inputs)
        self.by_slot = {
            question["validation_metadata"]["slot_id"]: question
            for question in self.bundle["questions"]
        }

    def test_complete_contract_and_generated_drift_check_pass(self) -> None:
        self.assertEqual(validate_contract(self.BANK_ROOT, check_generated=True), [])

    def test_snapshot_identity_and_bundle_payload_are_exact(self) -> None:
        self.assertEqual(len(self.bundle["questions"]), 100)
        self.assertEqual(
            {question["question_id"] for question in self.bundle["questions"]},
            {f"DRONE-Q-{number:06d}" for number in range(1, 101)},
        )
        self.assertEqual(
            {question["question_version"] for question in self.bundle["questions"]},
            {1},
        )
        self.assertEqual(
            self.bundle["bank_revision"],
            "drone-second-class-v0-core-2026-08-19",
        )
        self.assertEqual(
            self.bundle["formal_snapshot_commit_sha"],
            "61eb6962416e6cd91f22cbf96126244ff760fcc6",
        )
        for question in self.bundle["questions"]:
            self.assertTrue(question["question"])
            self.assertGreaterEqual(len(question["choices"]), 3)
            self.assertIn(question["correct_choice"], "ABCD")
            self.assertEqual(
                question["correct_index"],
                ord(question["correct_choice"]) - ord("A"),
            )
            self.assertTrue(question["explanation"])
            self.assertTrue(question["deck_id"])
            self.assertTrue(question["unit_id"])

    def test_all_slots_roles_and_typed_metadata_are_complete(self) -> None:
        self.assertEqual(
            set(self.by_slot),
            {f"VS-{number:03d}" for number in range(1, 101)},
        )
        roles = Counter(
            question["validation_metadata"]["primary_role"]
            for question in self.bundle["questions"]
        )
        self.assertEqual(dict(roles), self.EXPECTED_ROLES)
        required = {
            "slot_id",
            "primary_role",
            "kt_id",
            "item_family",
            "contamination_group",
            "alternate_of",
            "counterbalance",
            "administration_role_eligibility",
            "coverage_id",
            "sentinel_id",
            "replication_form",
            "routing_constraints",
        }
        for question in self.bundle["questions"]:
            self.assertTrue(required <= question["validation_metadata"].keys())
            self.assertTrue(question["validation_metadata"]["kt_id"])
        self.assertNotIn("notes_internal", json.dumps(self.bundle, ensure_ascii=False))

    def test_deep_mapping_alternates_and_m3_forms_are_fixed(self) -> None:
        expected = {
            "VS-001": "H1",
            "VS-002": "H2",
            "VS-003": "H2",
            "VS-004": "T1",
            "VS-005": "T2",
            "VS-006": "T2",
            "VS-007": "G1",
            "VS-008": "G2",
            "VS-009": "G1",
            "VS-010": "A1",
            "VS-011": "A4",
            "VS-012": "E1",
            "VS-013": "E2",
            "VS-014": "E1",
            "VS-015": "H5",
            "VS-016": "T3",
            "VS-017": "G3",
            "VS-018": "A2",
            "VS-019": "A3",
            "VS-020": "E3",
            "VS-021": "H3",
            "VS-022": "H4",
        }
        for slot_id, group in expected.items():
            metadata = self.by_slot[slot_id]["validation_metadata"]
            self.assertIn("item_family", metadata)
            self.assertIn("contamination_group", metadata)
            self.assertEqual(metadata["contamination_group"], group)
        alternates = {
            slot_id: self.by_slot[slot_id]["validation_metadata"]["alternate_of"]
            for slot_id in expected
            if self.by_slot[slot_id]["validation_metadata"]["alternate_of"]
        }
        self.assertEqual(
            alternates,
            {
                "VS-003": "VS-002",
                "VS-006": "VS-005",
                "VS-009": "VS-007",
                "VS-014": "VS-012",
            },
        )
        self.assertEqual(self.by_slot["VS-021"]["question_id"], "DRONE-Q-000009")
        self.assertEqual(self.by_slot["VS-022"]["question_id"], "DRONE-Q-000010")
        self.assertEqual(self.by_slot["VS-021"]["validation_metadata"]["replication_form"], "A")
        self.assertEqual(self.by_slot["VS-022"]["validation_metadata"]["replication_form"], "B")

    def test_breadth_mapping_and_counterbalance_are_fixed(self) -> None:
        expected = {
            "HB-1": ("VS-023", "VS-030", "YES"),
            "HB-2": ("VS-024", "VS-031", "PARTIAL_ONLY"),
            "HB-3": ("VS-025", "VS-032", "YES"),
            "HB-4": ("VS-026", "VS-033", "YES"),
            "HB-5": ("VS-027", "VS-034", "YES"),
            "HB-6": ("VS-028", "VS-035", "YES"),
            "HB-7": ("VS-029", "VS-036", "YES"),
        }
        for group, (observed, heldout, counterbalance) in expected.items():
            for slot_id, role in (
                (observed, "BREADTH_OBSERVED"),
                (heldout, "BREADTH_HELDOUT"),
            ):
                metadata = self.by_slot[slot_id]["validation_metadata"]
                self.assertEqual(metadata["contamination_group"], group)
                self.assertEqual(metadata["counterbalance"], counterbalance)
                self.assertEqual(metadata["primary_role"], role)
                self.assertEqual(
                    metadata["administration_role_eligibility"],
                    ["BREADTH_OBSERVED", "BREADTH_HELDOUT"],
                )

    def test_sentinel_registry_routing_and_feedback_lock_are_fixed(self) -> None:
        expected = {
            "US-A": ("VS-037", "DRONE-Q-000041"),
            "US-B": ("VS-038", "DRONE-Q-000042"),
            "US-C": ("VS-039", "DRONE-Q-000004"),
            "US-D": ("VS-040", "DRONE-Q-000043"),
            "US-E": ("VS-041", "DRONE-Q-000039"),
            "US-F": ("VS-042", "DRONE-Q-000040"),
            "US-G": ("VS-043", "DRONE-Q-000044"),
            "US-H": ("VS-044", "DRONE-Q-000045"),
        }
        for sentinel_id, (slot_id, question_id) in expected.items():
            question = self.by_slot[slot_id]
            self.assertEqual(question["question_id"], question_id)
            self.assertEqual(question["validation_metadata"]["sentinel_id"], sentinel_id)
            self.assertTrue(question["validation_metadata"]["routing_constraints"])
        self.assertEqual(
            self.bundle["sentinel_feedback_lock"],
            {
                "requires_all_bank_sentinels": False,
                "sentinel_scope": "PARTICIPANT_ASSIGNED",
                "unlock_condition": "ALL_ASSIGNED_SENTINEL_RESPONSES_DURABLY_COMMITTED",
            },
        )

    def test_coverage_mapping_is_exact_and_cov_52_is_non_thermal(self) -> None:
        coverage_ids = []
        for number in range(1, 57):
            slot_id = f"VS-{44 + number:03d}"
            coverage_id = f"COV-{number:02d}"
            metadata = self.by_slot[slot_id]["validation_metadata"]
            self.assertEqual(metadata["coverage_id"], coverage_id)
            coverage_ids.append(metadata["coverage_id"])
        self.assertEqual(len(coverage_ids), len(set(coverage_ids)))
        self.assertEqual(
            self.by_slot["VS-096"]["validation_metadata"]["routing_constraints"],
            [{"constraint_type": "ROUTE_CLASS_REQUIRED", "route_class": "NON_THERMAL_FOG"}],
        )

    def test_hashes_and_generated_bytes_are_deterministic(self) -> None:
        second_inputs = load_validation_inputs(self.BANK_ROOT)
        self.assertEqual(
            formal_snapshot_source_hash(self.inputs),
            formal_snapshot_source_hash(second_inputs),
        )
        self.assertEqual(
            build_generated_files(self.inputs),
            build_generated_files(second_inputs),
        )
        self.assertEqual(self.manifest["formal_snapshot_source_hash"], self.EXPECTED_SOURCE_HASH)
        self.assertEqual(self.manifest["validation_bundle_hash"], self.EXPECTED_BUNDLE_HASH)

    def test_semantic_source_hash_ignores_question_row_order(self) -> None:
        reordered = replace(self.inputs, questions=list(reversed(self.inputs.questions)))
        self.assertEqual(
            formal_snapshot_source_hash(self.inputs),
            formal_snapshot_source_hash(reordered),
        )

    def test_formal_change_under_same_revision_fails_instead_of_regenerating(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            bank = Path(temporary_directory) / "drone_second_class"
            shutil.copytree(self.BANK_ROOT, bank)
            questions_path = (
                bank
                / "validation"
                / "formal_snapshot"
                / "authoring"
                / "questions.csv"
            )
            with questions_path.open(newline="", encoding="utf-8-sig") as file:
                reader = csv.DictReader(file)
                fieldnames = list(reader.fieldnames or [])
                rows = list(reader)
            rows[0]["question"] += " changed"
            with questions_path.open("w", newline="", encoding="utf-8") as file:
                writer = csv.DictWriter(file, fieldnames=fieldnames)
                writer.writeheader()
                writer.writerows(rows)
            errors = validate_contract(bank, check_generated=False)
            self.assertTrue(
                any("formal_snapshot_source_hash_mismatch" in error for error in errors)
            )
            self.assertTrue(any("protected_file_drift" in error for error in errors))

    def test_generated_drift_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            bank = Path(temporary_directory) / "drone_second_class"
            shutil.copytree(self.BANK_ROOT, bank)
            (bank / "validation" / "generated" / "validation_bundle.json").write_text(
                "{}\n", encoding="utf-8"
            )
            errors = validate_contract(bank, check_generated=True)
            self.assertTrue(any("validation_generated_drift" in error for error in errors))

    def test_protected_files_match_formal_snapshot_bytes(self) -> None:
        for relative_path, expected_hash in self.inputs.protocol[
            "protected_file_byte_hashes"
        ].items():
            self.assertEqual(
                file_sha256(self.inputs.source_root / relative_path),
                expected_hash,
            )

    def test_live_production_authoring_is_not_a_validation_input(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            bank = Path(temporary_directory) / "drone_second_class"
            shutil.copytree(self.BANK_ROOT, bank)
            live_questions = bank / "authoring" / "questions.csv"
            live_questions.write_text("production state\n", encoding="utf-8")

            inputs = load_validation_inputs(bank)
            bundle, manifest = build_validation_documents(inputs)

            self.assertEqual(bundle, self.bundle)
            self.assertEqual(manifest, self.manifest)
            self.assertEqual(validate_contract(bank, check_generated=True), [])

    def test_source_release_and_production_runtime_remain_inactive(self) -> None:
        self.assertEqual({row["status"] for row in self.inputs.questions}, {"draft"})
        self.assertEqual(self.inputs.released["released_questions"], [])
        self.assertFalse(
            any(row["first_used_bank_revision"] for row in self.inputs.registry)
        )
        runtime = json.loads(
            (self.inputs.source_root / "generated" / "drone_second_class_bank.json").read_text(
                encoding="utf-8"
            )
        )
        production_manifest = json.loads(
            (self.inputs.source_root / "generated" / "bank_manifest.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(runtime["decks"], [])
        self.assertEqual(runtime["examProfileVersion"], "drone-second-class-unreleased")
        self.assertEqual(production_manifest["question_count"], 0)
        self.assertEqual(production_manifest["free_question_count"], 0)


if __name__ == "__main__":
    unittest.main()
