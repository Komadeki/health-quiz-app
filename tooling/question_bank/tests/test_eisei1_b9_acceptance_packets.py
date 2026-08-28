from __future__ import annotations

import csv
import json
import sys
import unittest
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(TOOL_DIR))

from ai_governance import candidate_fingerprint  # noqa: E402
from expansion import validate_expansion_batch  # noqa: E402


class Eisei1B9AcceptancePacketTest(unittest.TestCase):
    mapping = {
        "E1-B9-LH-C001": "EISEI1-Q-000014",
        "E1-B9-LH-C002": "EISEI1-Q-000015",
        "E1-B9-LH-C003": "EISEI1-Q-000016",
    }

    def setUp(self) -> None:
        self.batch = REPOSITORY_ROOT / "question_banks/eisei1/authoring/batches/batch_009"
        with (self.batch / "candidates.csv").open(encoding="utf-8", newline="") as handle:
            self.rows = {row["candidate_id"]: row for row in csv.DictReader(handle)}
        self.review = json.loads((self.batch / "independent_review_r1.json").read_text(encoding="utf-8"))

    def test_exact_independent_accepts_are_integrated_with_bound_packets(self) -> None:
        decisions = {item["candidate_id"]: item for item in self.review["decisions"]}
        packet_dir = self.batch / "acceptance_packets"
        self.assertEqual(set(self.mapping), {cid for cid, item in decisions.items() if item["decision"] == "ACCEPT"})
        self.assertEqual(set(self.mapping), {path.stem for path in packet_dir.glob("*.json")})
        self.assertEqual(
            {candidate_id: "INTEGRATED" for candidate_id in self.mapping},
            {candidate_id: self.rows[candidate_id]["state"] for candidate_id in self.mapping},
        )
        self.assertEqual(
            self.mapping,
            {candidate_id: self.rows[candidate_id]["permanent_question_id"] for candidate_id in self.mapping},
        )

        for candidate_id in self.mapping:
            packet = json.loads((packet_dir / f"{candidate_id}.json").read_text(encoding="utf-8"))
            self.assertEqual(candidate_id, packet["candidate_id"])
            self.assertEqual("AI_PRE_ACCEPT", packet["candidate_state"])
            self.assertEqual(candidate_fingerprint(self.rows[candidate_id]), packet["candidate_fingerprint"])
            self.assertEqual(decisions[candidate_id]["rationale"], packet["independent_review"]["rationale"])
            self.assertEqual("ACCEPT", packet["director_adjudication"]["decision"])
            self.assertEqual("AI_GOVERNED_ACCEPT", packet["requested_state"])
            self.assertEqual(3, len({actor["id"] for actor in packet["actors"].values()}))
            self.assertEqual(
                {"AI_AUTHOR", "AI_REVIEWER", "AI_DIRECTOR"},
                {actor["role"] for actor in packet["actors"].values()},
            )

        self.assertEqual([], validate_expansion_batch(self.batch))


if __name__ == "__main__":
    unittest.main()
