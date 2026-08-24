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

from ai_governance import (  # noqa: E402
    AIGovernanceError,
    candidate_fingerprint,
    promote_ai_governed_candidates,
)

AUTOPILOT_DIR = REPOSITORY_ROOT / "tooling" / "komadeki_autopilot"
sys.path.insert(0, str(AUTOPILOT_DIR))
from question_acceptance import accepted, validate_packet  # noqa: E402


class B3AcceptancePacketTest(unittest.TestCase):
    accepted_ids = (
        "B3-SYS-C001", "B3-SYS-C002", "B3-SYS-C003", "B3-SYS-C004",
        "B3-SYS-C005", "B3-SYS-C006", "B3-SYS-C007", "B3-SYS-C008",
        "B3-SYS-C009", "B3-SYS-C010", "B3-SYS-C011", "B3-SYS-C012",
        "B3-SYS-C013", "B3-SYS-C014", "B3-SYS-C017", "B3-SYS-C018",
        "B3-SYS-C019", "B3-SYS-C020", "B3-SYS-C021", "B3-SYS-C022",
        "B3-SYS-C023", "B3-SYS-C024", "B3-SYS-C025", "B3-SYS-C026",
        "B3-SYS-C027", "B3-SYS-C028", "B3-SYS-C029", "B3-SYS-C030",
    )
    rejected_ids = ("B3-SYS-C015", "B3-SYS-C016")
    actor_ids = {
        "author": "chatgpt-b3-systems-author-r1",
        "reviewer": "autopilot-b3-systems-reviewer-r1",
        "director": "chatgpt-b3-systems-director-adjudicator-r1",
    }

    def setUp(self) -> None:
        self.source_batch = (
            REPOSITORY_ROOT
            / "question_banks/drone_second_class/authoring/batches/batch_003"
        )
        self.rows = self._rows(self.source_batch)

    @staticmethod
    def _rows(batch: Path) -> dict[str, dict[str, str]]:
        with (batch / "candidates.csv").open(encoding="utf-8", newline="") as handle:
            return {row["candidate_id"]: row for row in csv.DictReader(handle)}

    def _copy_batch(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        batch = Path(temporary.name) / "batch_003"
        shutil.copytree(self.source_batch, batch)
        return batch

    def _reset_accepted_states(self, batch: Path) -> None:
        with (batch / "candidates.csv").open(encoding="utf-8", newline="") as handle:
            fields = list((reader := csv.DictReader(handle)).fieldnames or [])
            rows = list(reader)
        for row in rows:
            if row["candidate_id"] in self.accepted_ids:
                row["state"] = "AI_PRE_ACCEPT"
                row["permanent_question_id"] = ""
        with (batch / "candidates.csv").open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)

    def test_packets_bind_exactly_to_director_accepted_candidates(self) -> None:
        review = json.loads(
            (self.source_batch / "independent_review_r1.json").read_text(encoding="utf-8")
        )
        director = json.loads(
            (self.source_batch / "director_adjudication_r1.json").read_text(encoding="utf-8")
        )
        review_rationale = {
            item["candidate_id"]: item["rationale"]
            for item in review["decisions"]
            if item["decision"] == "ACCEPT"
        }

        packets = sorted((self.source_batch / "acceptance_packets").glob("*.json"))
        self.assertEqual(set(self.accepted_ids), set(director["accepted_candidate_ids"]))
        self.assertEqual(28, len(packets))
        self.assertTrue(
            all(
                not (
                    self.source_batch
                    / "acceptance_packets"
                    / f"{candidate_id}.json"
                ).exists()
                for candidate_id in self.rejected_ids
            )
        )

        for candidate_id in self.accepted_ids:
            packet = json.loads(
                (
                    self.source_batch
                    / "acceptance_packets"
                    / f"{candidate_id}.json"
                ).read_text(encoding="utf-8")
            )
            candidate = self.rows[candidate_id]
            self.assertEqual([], validate_packet(packet), candidate_id)
            self.assertTrue(accepted(packet), candidate_id)
            self.assertEqual(
                candidate_fingerprint(candidate), packet["candidate_fingerprint"]
            )
            self.assertEqual("AI_PRE_ACCEPT", packet["candidate_state"])
            self.assertEqual(
                {
                    name: {"id": actor_id, "role": f"AI_{name.upper()}"}
                    for name, actor_id in self.actor_ids.items()
                },
                packet["actors"],
            )
            self.assertEqual(
                review_rationale[candidate_id],
                packet["independent_review"]["rationale"],
            )
            self.assertEqual(
                director["director_rationale"],
                packet["director_adjudication"]["rationale"],
            )
            self.assertEqual(
                {
                    "source": {
                        field: candidate[field]
                        for field in ("source_id", "source_version", "source_locator")
                    },
                    "answer_defining_proposition": candidate[
                        "answer_defining_proposition"
                    ],
                    "tested_misconception": candidate["tested_misconception"],
                    "reasoning_path": candidate["reasoning_path"],
                    "collision": {
                        "released_bank_checked": True,
                        "canonical_drafts_checked": True,
                        "batch_checked": True,
                        "note": candidate["collision_note"],
                    },
                },
                packet["evidence"],
            )

    def test_only_director_accepted_candidates_are_ready_for_id(self) -> None:
        self.assertTrue(
            all(self.rows[candidate_id]["state"] == "READY_FOR_ID"
                for candidate_id in self.accepted_ids)
        )
        self.assertTrue(
            all(not self.rows[candidate_id]["permanent_question_id"]
                for candidate_id in self.accepted_ids)
        )
        self.assertTrue(
            all(self.rows[candidate_id]["state"] == "AI_PRE_ACCEPT"
                for candidate_id in self.rejected_ids)
        )
        self.assertTrue(
            all(not self.rows[candidate_id]["permanent_question_id"]
                for candidate_id in self.rejected_ids)
        )
        with (self.source_batch / "reviews.csv").open(
            encoding="utf-8", newline=""
        ) as handle:
            self.assertEqual([], list(csv.DictReader(handle)))

    def test_promotion_path_promotes_all_28_atomically(self) -> None:
        batch = self._copy_batch()
        self._reset_accepted_states(batch)
        self.assertEqual(
            self.accepted_ids,
            promote_ai_governed_candidates(batch, self.accepted_ids),
        )
        rows = self._rows(batch)
        self.assertTrue(
            all(rows[candidate_id]["state"] == "READY_FOR_ID"
                for candidate_id in self.accepted_ids)
        )
        self.assertTrue(
            all(rows[candidate_id]["state"] == "AI_PRE_ACCEPT"
                for candidate_id in self.rejected_ids)
        )

    def test_source_or_collision_mismatch_fails_closed(self) -> None:
        batch = self._copy_batch()
        self._reset_accepted_states(batch)
        packet_path = batch / "acceptance_packets" / "B3-SYS-C001.json"
        packet = json.loads(packet_path.read_text(encoding="utf-8"))
        packet["evidence"]["source"]["source_locator"] = "stale"
        packet_path.write_text(
            json.dumps(packet, ensure_ascii=False), encoding="utf-8"
        )
        with self.assertRaises(AIGovernanceError):
            promote_ai_governed_candidates(batch, self.accepted_ids)
        self.assertTrue(
            all(self._rows(batch)[candidate_id]["state"] == "AI_PRE_ACCEPT"
                for candidate_id in self.accepted_ids)
        )

        packet["evidence"]["source"]["source_locator"] = self.rows[
            "B3-SYS-C001"
        ]["source_locator"]
        packet["evidence"]["collision"]["note"] = "stale"
        packet_path.write_text(
            json.dumps(packet, ensure_ascii=False), encoding="utf-8"
        )
        with self.assertRaises(AIGovernanceError):
            promote_ai_governed_candidates(batch, self.accepted_ids)
        self.assertTrue(
            all(self._rows(batch)[candidate_id]["state"] == "AI_PRE_ACCEPT"
                for candidate_id in self.accepted_ids)
        )


if __name__ == "__main__":
    unittest.main()
