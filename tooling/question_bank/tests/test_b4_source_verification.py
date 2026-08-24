from __future__ import annotations
import csv, json, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
A = ROOT / "question_banks/drone_second_class/authoring"
B = A / "batches/batch_004"
IDS = [f"DRONE-Q-{n:06d}" for n in range(170, 189)]
ACCEPTED = {
    "B4-OPS-C001", "B4-OPS-C002", "B4-OPS-C003", "B4-OPS-C004", "B4-OPS-C005",
    "B4-OPS-C006", "B4-OPS-C007", "B4-OPS-C008", "B4-OPS-C009", "B4-OPS-C010",
    "B4-OPS-C011", "B4-OPS-C012", "B4-OPS-C013", "B4-OPS-C014", "B4-OPS-C015",
    "B4-OPS-C017", "B4-OPS-C018", "B4-OPS-C019", "B4-OPS-C020",
}


class B4SourceVerificationTest(unittest.TestCase):
    def test_b4_verified_and_rejected_candidate_excluded(self):
        with (B / "candidates.csv").open(encoding="utf-8", newline="") as handle:
            rows = {row["candidate_id"]: row for row in csv.DictReader(handle)}

        self.assertTrue(all(rows[cid]["state"] == "RELEASED" for cid in ACCEPTED))
        self.assertEqual("AI_PRE_ACCEPT", rows["B4-OPS-C016"]["state"])
        self.assertEqual("", rows["B4-OPS-C016"]["permanent_question_id"])

        verifications = json.loads((A / "source_verifications.json").read_text(encoding="utf-8"))["verifications"]
        by_id = {row["question_id"]: row for row in verifications}
        for question_id in IDS:
            self.assertEqual("MLIT-UAS-SAFETY-GUIDE-5", by_id[question_id]["source_id"])
            self.assertEqual("5", by_id[question_id]["source_version"])
            self.assertEqual("author_source_verified", by_id[question_id]["verification_state"])
            self.assertEqual("2026-08-24", by_id[question_id]["verified_at"])

        released = json.loads((A / "released_questions.json").read_text(encoding="utf-8"))["released_questions"]
        self.assertEqual(188, len(released))


if __name__ == "__main__":
    unittest.main()
