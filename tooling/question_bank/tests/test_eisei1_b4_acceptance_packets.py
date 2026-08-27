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

from ai_governance import AIGovernanceError, candidate_fingerprint, promote_ai_governed_candidates  # noqa: E402
from expansion import validate_expansion_batch  # noqa: E402


class Eisei1B4AcceptancePacketTest(unittest.TestCase):
    accepted_ids = ("E1-B4-LH-C002", "E1-B4-LH-C004")
    rework_ids = ("E1-B4-LH-C001", "E1-B4-LH-C003")

    def setUp(self) -> None:
        self.source_batch = REPOSITORY_ROOT / "question_banks/eisei1/authoring/batches/batch_004"
        self.rows = self._rows(self.source_batch)

    @staticmethod
    def _rows(batch: Path) -> dict[str, dict[str, str]]:
        with (batch / "candidates.csv").open(encoding="utf-8", newline="") as handle:
            return {row["candidate_id"]: row for row in csv.DictReader(handle)}

    def _copy_batch_with_pre_accept_states(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        batch = Path(temporary.name) / "batch_004"
        shutil.copytree(self.source_batch, batch)
        with (batch / "candidates.csv").open(encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            fields, rows = list(reader.fieldnames or []), list(reader)
        for row in rows:
            row["state"] = "AI_PRE_ACCEPT"
            row["permanent_question_id"] = ""
        with (batch / "candidates.csv").open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        return batch

    def test_only_authoritative_accepts_have_packets_and_integrated_state(self) -> None:
        review = json.loads((self.source_batch / "independent_review_r1.json").read_text(encoding="utf-8"))
        decisions = {item["candidate_id"]: item for item in review["decisions"]}
        packets = self.source_batch / "acceptance_packets"

        self.assertEqual(set(self.accepted_ids), {candidate_id for candidate_id, item in decisions.items() if item["decision"] == "ACCEPT"})
        self.assertEqual(set(self.rework_ids), {candidate_id for candidate_id, item in decisions.items() if item["decision"] == "REWORK"})
        self.assertEqual(set(self.accepted_ids), {path.stem for path in packets.glob("*.json")})
        self.assertEqual({candidate_id: "INTEGRATED" for candidate_id in self.accepted_ids}, {candidate_id: self.rows[candidate_id]["state"] for candidate_id in self.accepted_ids})
        self.assertEqual({candidate_id: "AI_PRE_ACCEPT" for candidate_id in self.rework_ids}, {candidate_id: self.rows[candidate_id]["state"] for candidate_id in self.rework_ids})

        for candidate_id in self.accepted_ids:
            packet = json.loads((packets / f"{candidate_id}.json").read_text(encoding="utf-8"))
            self.assertEqual(candidate_fingerprint(self.rows[candidate_id]), packet["candidate_fingerprint"])
            self.assertEqual(decisions[candidate_id]["rationale"], packet["independent_review"]["rationale"])
            self.assertEqual("ACCEPT", packet["director_adjudication"]["decision"])
            self.assertEqual("AI_GOVERNED_ACCEPT", packet["requested_state"])
            self.assertEqual(3, len({actor["id"] for actor in packet["actors"].values()}))
            self.assertTrue(all(actor["role"].startswith("AI_") for actor in packet["actors"].values()))
        self.assertEqual([], validate_expansion_batch(self.source_batch))

    def test_promotion_is_atomic_and_rework_candidates_cannot_be_selected(self) -> None:
        batch = self._copy_batch_with_pre_accept_states()
        self.assertEqual(self.accepted_ids, promote_ai_governed_candidates(batch, self.accepted_ids))
        rows = self._rows(batch)
        self.assertTrue(all(rows[candidate_id]["state"] == "READY_FOR_ID" for candidate_id in self.accepted_ids))
        self.assertTrue(all(rows[candidate_id]["state"] == "AI_PRE_ACCEPT" for candidate_id in self.rework_ids))

        batch = self._copy_batch_with_pre_accept_states()
        with self.assertRaises(AIGovernanceError):
            promote_ai_governed_candidates(batch, self.accepted_ids + (self.rework_ids[0],))
        rows = self._rows(batch)
        self.assertTrue(all(rows[candidate_id]["state"] == "AI_PRE_ACCEPT" for candidate_id in self.accepted_ids + self.rework_ids))

    def test_choice5_fingerprint_drift_fails_closed(self) -> None:
        batch = self._copy_batch_with_pre_accept_states()
        with (batch / "candidates.csv").open(encoding="utf-8", newline="") as handle:
            reader = csv.DictReader(handle)
            fields, rows = list(reader.fieldnames or []), list(reader)
        next(row for row in rows if row["candidate_id"] == "E1-B4-LH-C002")["choice5"] = "変更済み"
        with (batch / "candidates.csv").open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        with self.assertRaises(AIGovernanceError):
            promote_ai_governed_candidates(batch, self.accepted_ids)
        self.assertTrue(
            all(
                self._rows(batch)[candidate_id]["state"] == "AI_PRE_ACCEPT"
                for candidate_id in self.accepted_ids
            )
        )


if __name__ == "__main__":
    unittest.main()
