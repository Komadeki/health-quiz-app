from __future__ import annotations

import csv
import json
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
BANK = REPOSITORY_ROOT / "question_banks" / "eisei1"
AUTHORING = BANK / "authoring"
BATCH = AUTHORING / "batches" / "batch_007"
EXPECTED = {
    "E1-B7-LH-C001": "EISEI1-Q-000009",
    "E1-B7-LH-C002": "EISEI1-Q-000010",
}
EXPECTED_SOURCES = {
    "EISEI1-Q-000009": "E1-LAW-SPEC-CHEM",
    "EISEI1-Q-000010": "E1-LAW-ASBESTOS",
}
B8_MAPPING = {
    "E1-B8-HH-C001": "EISEI1-Q-000011",
    "E1-B8-HH-C002": "EISEI1-Q-000012",
    "E1-B8-LH-C001": "EISEI1-Q-000013",
}
B9_IDS = {"E1-B9-LH-C001", "E1-B9-LH-C002", "E1-B9-LH-C003"}


def rows(path: Path, key: str) -> dict[str, dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return {row[key]: row for row in csv.DictReader(handle)}


class Eisei1B7IntegrationTests(unittest.TestCase):
    def test_b7_accepts_are_integrated_as_q9_q10(self) -> None:
        candidates = rows(BATCH / "candidates.csv", "candidate_id")
        questions = rows(AUTHORING / "questions.csv", "question_id")
        registry = rows(AUTHORING / "question_id_registry.csv", "question_id")

        self.assertEqual(
            {f"EISEI1-Q-{index:06d}" for index in range(1, 14)},
            set(questions),
        )
        self.assertEqual(set(questions), set(registry))
        self.assertEqual(set(EXPECTED), {path.stem for path in (BATCH / "acceptance_packets").glob("*.json")})

        for candidate_id, question_id in EXPECTED.items():
            candidate = candidates[candidate_id]
            question = questions[question_id]
            self.assertEqual("INTEGRATED", candidate["state"])
            self.assertEqual(question_id, candidate["permanent_question_id"])
            self.assertEqual("used", registry[question_id]["status"])
            self.assertEqual(f"Expansion pre-release allocation: {candidate_id}", registry[question_id]["notes"])
            self.assertEqual("1", question["question_version"])
            self.assertEqual("draft", question["status"])
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

    def test_q9_q10_are_source_verified_and_still_pre_release(self) -> None:
        verifications = {
            row["question_id"]: row
            for row in json.loads((AUTHORING / "source_verifications.json").read_text(encoding="utf-8"))[
                "verifications"
            ]
        }
        for question_id, source_id in EXPECTED_SOURCES.items():
            self.assertIn(question_id, verifications)
            self.assertEqual(source_id, verifications[question_id]["source_id"])
            self.assertEqual("author_source_verified", verifications[question_id]["verification_state"])
            self.assertEqual("2026-08-27", verifications[question_id]["verified_at"])
        self.assertEqual(
            [],
            json.loads((AUTHORING / "released_questions.json").read_text(encoding="utf-8"))[
                "released_questions"
            ],
        )
        self.assertEqual(
            [],
            json.loads((BANK / "generated" / "eisei1_bank.json").read_text(encoding="utf-8"))[
                "decks"
            ],
        )

    def test_b8_is_integrated_and_b9_remains_ready(self) -> None:
        questions = rows(AUTHORING / "questions.csv", "question_id")
        registry = rows(AUTHORING / "question_id_registry.csv", "question_id")
        b8_batch = AUTHORING / "batches" / "batch_008"
        b8 = rows(b8_batch / "candidates.csv", "candidate_id")
        self.assertEqual(set(B8_MAPPING), set(b8))
        self.assertEqual(set(B8_MAPPING), {path.stem for path in (b8_batch / "acceptance_packets").glob("*.json")})
        for candidate_id, question_id in B8_MAPPING.items():
            candidate = b8[candidate_id]
            self.assertEqual("INTEGRATED", candidate["state"])
            self.assertEqual(question_id, candidate["permanent_question_id"])
            self.assertIn(question_id, questions)
            self.assertIn(question_id, registry)

        b9_batch = AUTHORING / "batches" / "batch_009"
        b9 = rows(b9_batch / "candidates.csv", "candidate_id")
        self.assertEqual(B9_IDS, set(b9))
        self.assertTrue(all(row["state"] == "READY_FOR_ID" for row in b9.values()))
        self.assertTrue(all(not row["permanent_question_id"] for row in b9.values()))
        self.assertEqual(B9_IDS, {path.stem for path in (b9_batch / "acceptance_packets").glob("*.json")})


if __name__ == "__main__":
    unittest.main()
