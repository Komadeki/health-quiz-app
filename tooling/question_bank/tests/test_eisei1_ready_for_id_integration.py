from __future__ import annotations

import csv
import json
import sys
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPOSITORY_ROOT / "tooling" / "question_bank"))

from expansion import validate_expansion_batch  # noqa: E402


EXPECTED = {
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
ALL_EXPECTED = {**EXPECTED, **B6_EXPECTED, **B7_EXPECTED}
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

    def test_integrated_inventory_is_contiguous_through_q10(self) -> None:
        questions = read_rows(self.authoring / "questions.csv")
        registry = read_rows(self.authoring / "question_id_registry.csv")
        self.assertEqual(set(ALL_EXPECTED.values()), set(questions))
        self.assertEqual(set(ALL_EXPECTED.values()), set(registry))
        for batch_name in ("batch_002", "batch_003", "batch_004"):
            candidates = read_rows(self.authoring / "batches" / batch_name / "candidates.csv")
            for candidate_id, question_id in EXPECTED.items():
                if candidate_id not in candidates:
                    continue
                candidate, question = candidates[candidate_id], questions[question_id]
                self.assertEqual("INTEGRATED", candidate["state"])
                self.assertEqual(question_id, candidate["permanent_question_id"])
                self.assertEqual("draft", question["status"])
                self.assertEqual("eisei1_exam", question["deck_id"])
                self.assertEqual(candidate["unit_id"], question["unit_id"])
                self.assertEqual("1", question["question_version"])
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
                self.assertEqual("used", registry[question_id]["status"])
                self.assertEqual("", registry[question_id]["first_used_bank_revision"])

    def test_rework_candidates_are_unchanged_and_q1_q10_are_source_verified(self) -> None:
        excluded = {
            "batch_003": ("E1-B3-HH-C001",),
            "batch_004": ("E1-B4-LH-C001", "E1-B4-LH-C003"),
        }
        for batch_name, candidate_ids in excluded.items():
            candidates = read_rows(self.authoring / "batches" / batch_name / "candidates.csv")
            for candidate_id in candidate_ids:
                self.assertEqual("AI_PRE_ACCEPT", candidates[candidate_id]["state"])
                self.assertEqual("", candidates[candidate_id]["permanent_question_id"])

        verifications = json.loads(
            (self.authoring / "source_verifications.json").read_text(encoding="utf-8")
        )["verifications"]
        self.assertEqual(set(EXPECTED_VERIFICATION_SOURCES), {row["question_id"] for row in verifications})
        for row in verifications:
            self.assertEqual(EXPECTED_VERIFICATION_SOURCES[row["question_id"]], row["source_id"])
            self.assertEqual("author_source_verified", row["verification_state"])
            self.assertEqual("2026-08-27", row["verified_at"])

        self.assertEqual(
            [],
            json.loads((self.authoring / "released_questions.json").read_text(encoding="utf-8"))[
                "released_questions"
            ],
        )
        self.assertEqual(
            [],
            json.loads((self.bank / "generated" / "eisei1_bank.json").read_text(encoding="utf-8"))[
                "decks"
            ],
        )

    def test_b6_and_b7_are_integrated_in_sequence(self) -> None:
        questions = read_rows(self.authoring / "questions.csv")
        registry = read_rows(self.authoring / "question_id_registry.csv")
        for batch_name, mapping in (("batch_006", B6_EXPECTED), ("batch_007", B7_EXPECTED)):
            batch = self.authoring / "batches" / batch_name
            candidates = read_rows(batch / "candidates.csv")
            self.assertEqual(set(mapping), {path.stem for path in (batch / "acceptance_packets").glob("*.json")})
            for candidate_id, question_id in mapping.items():
                candidate = candidates[candidate_id]
                self.assertEqual("INTEGRATED", candidate["state"])
                self.assertEqual(question_id, candidate["permanent_question_id"])
                self.assertIn(question_id, questions)
                self.assertIn(question_id, registry)
                for field in ("question", "choice1", "choice2", "choice3", "choice4", "choice5", "explanation", "source_id", "source_locator"):
                    self.assertEqual(candidate[field], questions[question_id][field])
                self.assertEqual(candidate["proposed_correct"], questions[question_id]["correct_choice"])
                self.assertEqual("used", registry[question_id]["status"])

    def test_all_touched_expansion_batches_validate(self) -> None:
        for batch_name in ("batch_002", "batch_003", "batch_004", "batch_006", "batch_007"):
            self.assertEqual(
                [],
                validate_expansion_batch(self.authoring / "batches" / batch_name),
            )


if __name__ == "__main__":
    unittest.main()
