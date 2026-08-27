from __future__ import annotations

import csv
import json
import sys
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPOSITORY_ROOT / "tooling" / "question_bank"))

from expansion import validate_expansion_batch  # noqa: E402


EARLY_EXPECTED = {
    "E1-B2-HH-C001": "EISEI1-Q-000001",
    "E1-B2-HH-C002": "EISEI1-Q-000002",
    "E1-B2-LH-C001": "EISEI1-Q-000003",
    "E1-B2-LH-C002": "EISEI1-Q-000004",
    "E1-B3-LH-C001": "EISEI1-Q-000005",
    "E1-B4-LH-C002": "EISEI1-Q-000006",
    "E1-B4-LH-C004": "EISEI1-Q-000007",
}
B6_EXPECTED = {"E1-B6-HH-C001": "EISEI1-Q-000008"}
B7_EXPECTED = {
    "E1-B7-LH-C001": "EISEI1-Q-000009",
    "E1-B7-LH-C002": "EISEI1-Q-000010",
}
B8_EXPECTED = {
    "E1-B8-HH-C001": "EISEI1-Q-000011",
    "E1-B8-HH-C002": "EISEI1-Q-000012",
    "E1-B8-LH-C001": "EISEI1-Q-000013",
}
ALL_EXPECTED = {**EARLY_EXPECTED, **B6_EXPECTED, **B7_EXPECTED, **B8_EXPECTED}
EXPECTED_VERIFICATION_SOURCES = {
    "EISEI1-Q-000001": "E1-MHLW-CHEM-RA",
    "EISEI1-Q-000002": "E1-MHLW-RPE-2023",
    "EISEI1-Q-000003": "E1-LAW-ORGANIC",
    "EISEI1-Q-000004": "E1-LAW-OXYGEN",
    "EISEI1-Q-000005": "E1-LAW-OXYGEN",
    "EISEI1-Q-000006": "E1-LAW-IONIZING",
    "EISEI1-Q-000007": "E1-LAW-SPEC-CHEM",
    "EISEI1-Q-000008": "E1-MHLW-RPE-2023",
    "EISEI1-Q-000009": "E1-LAW-SPEC-CHEM",
    "EISEI1-Q-000010": "E1-LAW-ASBESTOS",
    "EISEI1-Q-000011": "E1-MHLW-DUST-PREVENTION",
    "EISEI1-Q-000012": "E1-MHLW-CHEMICAL-HAZARDS",
    "EISEI1-Q-000013": "E1-MHLW-WORKENV-EVALUATION",
}


def read_rows(path: Path) -> dict[str, dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return {
            row["candidate_id"] if "candidates" in path.name else row["question_id"]: row
            for row in csv.DictReader(handle)
        }


class Eisei1ReadyForIdIntegrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bank = REPOSITORY_ROOT / "question_banks" / "eisei1"
        self.authoring = self.bank / "authoring"

    def test_integrated_inventory_is_contiguous_through_q13(self) -> None:
        questions = read_rows(self.authoring / "questions.csv")
        registry = read_rows(self.authoring / "question_id_registry.csv")
        self.assertEqual(set(ALL_EXPECTED.values()), set(questions))
        self.assertEqual(set(ALL_EXPECTED.values()), set(registry))

    def test_integrated_batches_bind_exactly_to_canonical_rows(self) -> None:
        questions = read_rows(self.authoring / "questions.csv")
        registry = read_rows(self.authoring / "question_id_registry.csv")
        for batch_name, mapping in (
            ("batch_002", {k: v for k, v in EARLY_EXPECTED.items() if k.startswith("E1-B2-")}),
            ("batch_003", {"E1-B3-LH-C001": "EISEI1-Q-000005"}),
            ("batch_004", {k: v for k, v in EARLY_EXPECTED.items() if k.startswith("E1-B4-")}),
            ("batch_006", B6_EXPECTED),
            ("batch_007", B7_EXPECTED),
            ("batch_008", B8_EXPECTED),
        ):
            batch = self.authoring / "batches" / batch_name
            candidates = read_rows(batch / "candidates.csv")
            for candidate_id, question_id in mapping.items():
                candidate = candidates[candidate_id]
                question = questions[question_id]
                self.assertEqual("INTEGRATED", candidate["state"])
                self.assertEqual(question_id, candidate["permanent_question_id"])
                self.assertEqual("used", registry[question_id]["status"])
                self.assertEqual("draft", question["status"])
                self.assertEqual("1", question["question_version"])
                self.assertEqual("eisei1_exam", question["deck_id"])
                self.assertEqual(candidate["unit_id"], question["unit_id"])
                self.assertEqual("2", question["difficulty"])
                self.assertEqual("3", question["importance"])
                self.assertEqual("false", question["is_free"])
                for field in (
                    "question",
                    "choice1",
                    "choice2",
                    "choice3",
                    "choice4",
                    "choice5",
                    "explanation",
                    "source_id",
                    "source_locator",
                ):
                    self.assertEqual(candidate[field], question[field])
                self.assertEqual(candidate["proposed_correct"], question["correct_choice"])

    def test_q1_q13_are_source_verified_and_pre_release(self) -> None:
        verifications = json.loads(
            (self.authoring / "source_verifications.json").read_text(encoding="utf-8")
        )["verifications"]
        self.assertEqual(set(EXPECTED_VERIFICATION_SOURCES), {row["question_id"] for row in verifications})
        for row in verifications:
            self.assertEqual(EXPECTED_VERIFICATION_SOURCES[row["question_id"]], row["source_id"])
            self.assertEqual("author_source_verified", row["verification_state"])
            self.assertEqual("2026-08-27", row["verified_at"])
        self.assertEqual([], json.loads((self.authoring / "released_questions.json").read_text(encoding="utf-8"))["released_questions"])
        self.assertEqual([], json.loads((self.bank / "generated" / "eisei1_bank.json").read_text(encoding="utf-8"))["decks"])

    def test_b9_remains_ready_for_next_ids(self) -> None:
        batch = self.authoring / "batches" / "batch_009"
        candidates = read_rows(batch / "candidates.csv")
        expected_ids = {"E1-B9-LH-C001", "E1-B9-LH-C002", "E1-B9-LH-C003"}
        self.assertEqual(expected_ids, set(candidates))
        self.assertEqual(expected_ids, {path.stem for path in (batch / "acceptance_packets").glob("*.json")})
        self.assertTrue(all(row["state"] == "READY_FOR_ID" for row in candidates.values()))
        self.assertTrue(all(not row["permanent_question_id"] for row in candidates.values()))

    def test_all_touched_expansion_batches_validate(self) -> None:
        for batch_name in ("batch_002", "batch_003", "batch_004", "batch_006", "batch_007", "batch_008", "batch_009"):
            self.assertEqual([], validate_expansion_batch(self.authoring / "batches" / batch_name))


if __name__ == "__main__":
    unittest.main()
