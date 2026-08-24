from __future__ import annotations

import csv
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
AUTHORING = ROOT / "question_banks" / "drone_second_class" / "authoring"
BATCH = AUTHORING / "batches" / "batch_004"
ACCEPTED = [
    "B4-OPS-C001", "B4-OPS-C002", "B4-OPS-C003", "B4-OPS-C004", "B4-OPS-C005",
    "B4-OPS-C006", "B4-OPS-C007", "B4-OPS-C008", "B4-OPS-C009", "B4-OPS-C010",
    "B4-OPS-C011", "B4-OPS-C012", "B4-OPS-C013", "B4-OPS-C014", "B4-OPS-C015",
    "B4-OPS-C017", "B4-OPS-C018", "B4-OPS-C019", "B4-OPS-C020",
]
EXPECTED_IDS = [f"DRONE-Q-{n:06d}" for n in range(170, 189)]


class B4SourceVerificationTest(unittest.TestCase):
    def test_exactly_19_b4_candidates_are_verified(self) -> None:
        with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as handle:
            rows = {row["candidate_id"]: row for row in csv.DictReader(handle)}
        self.assertEqual(19, sum(rows[cid]["state"] == "VERIFIED" for cid in ACCEPTED))
        for cid, qid in zip(ACCEPTED, EXPECTED_IDS):
            self.assertEqual("VERIFIED", rows[cid]["state"])
            self.assertEqual(qid, rows[cid]["permanent_question_id"])
        self.assertEqual("AI_PRE_ACCEPT", rows["B4-OPS-C016"]["state"])
        self.assertEqual("", rows["B4-OPS-C016"]["permanent_question_id"])

    def test_exactly_19_source_verifications_are_bound(self) -> None:
        doc = json.loads((AUTHORING / "source_verifications.json").read_text(encoding="utf-8"))
        by_id = {row["question_id"]: row for row in doc["verifications"]}
        self.assertEqual(EXPECTED_IDS, [qid for qid in EXPECTED_IDS if qid in by_id])
        for qid in EXPECTED_IDS:
            self.assertEqual(
                {
                    "question_id": qid,
                    "source_id": "MLIT-UAS-SAFETY-GUIDE-5",
                    "source_version": "5",
                    "verification_state": "author_source_verified",
                    "verified_at": "2026-08-24",
                },
                by_id[qid],
            )

    def test_canonical_and_release_invariants_remain(self) -> None:
        with (AUTHORING / "questions.csv").open(encoding="utf-8", newline="") as handle:
            questions = list(csv.DictReader(handle))
        self.assertEqual(188, len(questions))
        by_id = {row["question_id"]: row for row in questions}
        self.assertTrue(all(by_id[qid]["status"] == "draft" for qid in EXPECTED_IDS))
        self.assertTrue(all(by_id[qid]["unit_id"] == "drone_operations" for qid in EXPECTED_IDS))
        released = json.loads((AUTHORING / "released_questions.json").read_text(encoding="utf-8"))["released_questions"]
        self.assertEqual(100, len(released))


if __name__ == "__main__":
    unittest.main()
