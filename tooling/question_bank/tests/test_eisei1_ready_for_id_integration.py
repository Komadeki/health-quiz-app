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
ALL_INTEGRATED_IDS = {*EXPECTED.values(), "EISEI1-Q-000008"}


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

    def test_exact_ready_candidates_received_contiguous_initial_ids(self) -> None:
        questions = read_rows(self.authoring / "questions.csv")
        registry = read_rows(self.authoring / "question_id_registry.csv")
        self.assertEqual(ALL_INTEGRATED_IDS, set(questions))
        self.assertEqual(ALL_INTEGRATED_IDS, set(registry))
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

    def test_rework_candidates_and_release_artifacts_are_unchanged(self) -> None:
        excluded = {
            "batch_003": ("E1-B3-HH-C001",),
            "batch_004": ("E1-B4-LH-C001", "E1-B4-LH-C003"),
        }
        for batch_name, candidate_ids in excluded.items():
            candidates = read_rows(self.authoring / "batches" / batch_name / "candidates.csv")
            for candidate_id in candidate_ids:
                self.assertEqual("AI_PRE_ACCEPT", candidates[candidate_id]["state"])
                self.assertEqual("", candidates[candidate_id]["permanent_question_id"])
        self.assertEqual(
            [],
            json.loads((self.authoring / "source_verifications.json").read_text(encoding="utf-8"))[
                "verifications"
            ],
        )
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

    def test_b6_received_the_next_permanent_id(self) -> None:
        batch = self.authoring / "batches" / "batch_006"
        candidates = read_rows(batch / "candidates.csv")
        candidate = candidates["E1-B6-HH-C001"]
        self.assertEqual("INTEGRATED", candidate["state"])
        self.assertEqual("EISEI1-Q-000008", candidate["permanent_question_id"])
        self.assertEqual(
            {"E1-B6-HH-C001"},
            {path.stem for path in (batch / "acceptance_packets").glob("*.json")},
        )
        self.assertIn("EISEI1-Q-000008", read_rows(self.authoring / "questions.csv"))
        self.assertIn("EISEI1-Q-000008", read_rows(self.authoring / "question_id_registry.csv"))

    def test_all_touched_expansion_batches_validate(self) -> None:
        for batch_name in ("batch_002", "batch_003", "batch_004", "batch_006"):
            self.assertEqual(
                [],
                validate_expansion_batch(self.authoring / "batches" / batch_name),
            )


if __name__ == "__main__":
    unittest.main()
