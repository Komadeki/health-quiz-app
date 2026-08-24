from __future__ import annotations

import csv
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
AUTHORING = ROOT / "question_banks/drone_second_class/authoring"
BATCH = AUTHORING / "batches/batch_001"
QUESTION_IDS = [f"DRONE-Q-{n:06d}" for n in range(101, 119)]
CANDIDATE_IDS = [f"B1-R-C{i:03d}" for i in range(1, 17)] + ["B1-R-C023", "B1-R-C024"]


class B1SourceVerificationTest(unittest.TestCase):
    def test_b1_rules_are_verified_without_release_activation(self) -> None:
        with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as handle:
            rows = {row["candidate_id"]: row for row in csv.DictReader(handle)}

        self.assertEqual(CANDIDATE_IDS, [candidate_id for candidate_id in rows])
        for candidate_id, question_id in zip(CANDIDATE_IDS, QUESTION_IDS, strict=True):
            self.assertEqual("VERIFIED", rows[candidate_id]["state"])
            self.assertEqual(question_id, rows[candidate_id]["permanent_question_id"])

        verifications = json.loads(
            (AUTHORING / "source_verifications.json").read_text(encoding="utf-8")
        )["verifications"]
        by_question_id = {row["question_id"]: row for row in verifications}
        for question_id in QUESTION_IDS:
            verification = by_question_id[question_id]
            self.assertEqual("MLIT-UAS-SAFETY-GUIDE-5", verification["source_id"])
            self.assertEqual("5", verification["source_version"])
            self.assertEqual("author_source_verified", verification["verification_state"])
            self.assertEqual("2026-08-24", verification["verified_at"])

        released = json.loads(
            (AUTHORING / "released_questions.json").read_text(encoding="utf-8")
        )["released_questions"]
        self.assertEqual(100, len(released))


if __name__ == "__main__":
    unittest.main()
