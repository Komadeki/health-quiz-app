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
from expansion import validate_expansion_batch  # noqa: E402

AUTOPILOT_DIR = REPOSITORY_ROOT / "tooling" / "komadeki_autopilot"
sys.path.insert(0, str(AUTOPILOT_DIR))
from question_acceptance import accepted, validate_packet  # noqa: E402


class B2AcceptancePacketTest(unittest.TestCase):
    accepted_ids = (
        "B2-RM-C001", "B2-RM-C002", "B2-RM-C003", "B2-RM-C004",
        "B2-RM-C005", "B2-RM-C007", "B2-RM-C008", "B2-RM-C009",
        "B2-RM-C010", "B2-RM-C011", "B2-RM-C013", "B2-RM-C014",
        "B2-RM-C015", "B2-RM-C016", "B2-RM-C017", "B2-RM-C018",
        "B2-RM-C019", "B2-RM-C020", "B2-RM-C021", "B2-RM-C022",
        "B2-RM-C023", "B2-RM-C024", "B2-RM-C025",
    )
    rejected_ids = ("B2-RM-C006", "B2-RM-C012")
    actor_ids = {
        "author": "chatgpt-director-authoring-run-20260824-b2",
        "reviewer": "autopilot-b2-risk-reviewer-r1",
        "director": "chatgpt-b2-risk-director-adjudicator-r1",
    }

    def setUp(self) -> None:
        self.source_batch = (
            REPOSITORY_ROOT
            / "question_banks/drone_second_class/authoring/batches/batch_002"
        )
        self.rows = self._rows(self.source_batch)

    @staticmethod
    def _rows(batch: Path) -> dict[str, dict[str, str]]:
        with (batch / "candidates.csv").open(encoding="utf-8", newline="") as handle:
            return {row["candidate_id"]: row for row in csv.DictReader(handle)}

    def _copy_batch(self) -> tuple[tempfile.TemporaryDirectory[str], Path]:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        batch = Path(temporary.name) / "batch_002"
        shutil.copytree(self.source_batch, batch)
        return temporary, batch

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
        review = json.loads((self.source_batch / "independent_review_r1.json").read_text(encoding="utf-8"))
        director = json.loads((self.source_batch / "director_adjudication_r1.json").read_text(encoding="utf-8"))
        review_rationale = {item["candidate_id"]: item["rationale"] for item in review["decisions"]}

        packets = sorted((self.source_batch / "acceptance_packets").glob("*.json"))
        self.assertEqual(set(self.accepted_ids), set(director["accepted_candidate_ids"]))
        self.assertEqual(23, len(packets))
        self.assertTrue(all(not (self.source_batch / "acceptance_packets" / f"{candidate_id}.json").exists() for candidate_id in self.rejected_ids))

        for candidate_id in self.accepted_ids:
            packet = json.loads((self.source_batch / "acceptance_packets" / f"{candidate_id}.json").read_text(encoding="utf-8"))
            candidate = self.rows[candidate_id]
            self.assertEqual([], validate_packet(packet), candidate_id)
            self.assertTrue(accepted(packet), candidate_id)
            self.assertEqual(candidate_fingerprint(candidate), packet["candidate_fingerprint"])
            self.assertEqual("AI_PRE_ACCEPT", packet["candidate_state"])
            self.assertEqual({name: {"id": actor_id, "role": f"AI_{name.upper()}"} for name, actor_id in self.actor_ids.items()}, packet["actors"])
            self.assertEqual(review_rationale[candidate_id], packet["independent_review"]["rationale"])
            self.assertEqual(director["director_rationale"], packet["director_adjudication"]["rationale"])
            self.assertEqual({
                "source": {field: candidate[field] for field in ("source_id", "source_version", "source_locator")},
                "answer_defining_proposition": candidate["answer_defining_proposition"],
                "tested_misconception": candidate["tested_misconception"],
                "reasoning_path": candidate["reasoning_path"],
                "collision": {
                    "released_bank_checked": True,
                    "canonical_drafts_checked": True,
                    "batch_checked": True,
                    "note": candidate["collision_note"],
                },
            }, packet["evidence"])

    def test_only_accepted_candidates_are_integrated_with_new_permanent_ids(self) -> None:
        expected_ids = {
            candidate_id: f"DRONE-Q-{number:06d}"
            for candidate_id, number in zip(self.accepted_ids, range(119, 142))
        }
        self.assertEqual({candidate_id: "INTEGRATED" for candidate_id in self.accepted_ids}, {candidate_id: self.rows[candidate_id]["state"] for candidate_id in self.accepted_ids})
        self.assertEqual(expected_ids, {candidate_id: self.rows[candidate_id]["permanent_question_id"] for candidate_id in self.accepted_ids})
        self.assertEqual({candidate_id: "AI_PRE_ACCEPT" for candidate_id in self.rejected_ids}, {candidate_id: self.rows[candidate_id]["state"] for candidate_id in self.rejected_ids})
        self.assertTrue(all(not self.rows[candidate_id]["permanent_question_id"] for candidate_id in self.rejected_ids))
        with (self.source_batch / "reviews.csv").open(encoding="utf-8", newline="") as handle:
            self.assertEqual([], list(csv.DictReader(handle)))
        with (REPOSITORY_ROOT / "question_banks/drone_second_class/authoring/questions.csv").open(encoding="utf-8", newline="") as handle:
            questions = {row["question_id"]: row for row in csv.DictReader(handle)}
        with (REPOSITORY_ROOT / "question_banks/drone_second_class/authoring/question_id_registry.csv").open(encoding="utf-8", newline="") as handle:
            registry = {row["question_id"]: row for row in csv.DictReader(handle)}
        for candidate_id, question_id in expected_ids.items():
            candidate = self.rows[candidate_id]
            self.assertEqual("draft", questions[question_id]["status"])
            self.assertEqual(candidate["question"], questions[question_id]["question"])
            self.assertEqual(candidate["proposed_correct"], questions[question_id]["correct_choice"])
            self.assertEqual(candidate["source_locator"], questions[question_id]["source_locator"])
            self.assertEqual("used", registry[question_id]["status"])
            self.assertEqual("", registry[question_id]["first_used_bank_revision"])
            self.assertEqual(f"Expansion pre-release allocation: {candidate_id}", registry[question_id]["notes"])
        self.assertEqual([], validate_expansion_batch(self.source_batch))

    def test_promotion_path_promotes_all_23_atomically(self) -> None:
        _, batch = self._copy_batch()
        self._reset_accepted_states(batch)
        self.assertEqual(self.accepted_ids, promote_ai_governed_candidates(batch, self.accepted_ids))
        rows = self._rows(batch)
        self.assertTrue(all(rows[candidate_id]["state"] == "READY_FOR_ID" for candidate_id in self.accepted_ids))
        self.assertTrue(all(rows[candidate_id]["state"] == "AI_PRE_ACCEPT" for candidate_id in self.rejected_ids))

    def test_source_or_collision_mismatch_fails_closed(self) -> None:
        _, batch = self._copy_batch()
        self._reset_accepted_states(batch)
        packet_path = batch / "acceptance_packets" / "B2-RM-C001.json"
        packet = json.loads(packet_path.read_text(encoding="utf-8"))
        packet["evidence"]["source"]["source_locator"] = "stale"
        packet_path.write_text(json.dumps(packet, ensure_ascii=False), encoding="utf-8")
        with self.assertRaises(AIGovernanceError):
            promote_ai_governed_candidates(batch, self.accepted_ids)
        self.assertTrue(all(self._rows(batch)[candidate_id]["state"] == "AI_PRE_ACCEPT" for candidate_id in self.accepted_ids))

        packet["evidence"]["source"]["source_locator"] = self.rows["B2-RM-C001"]["source_locator"]
        packet["evidence"]["collision"]["note"] = "stale"
        packet_path.write_text(json.dumps(packet, ensure_ascii=False), encoding="utf-8")
        with self.assertRaises(AIGovernanceError):
            promote_ai_governed_candidates(batch, self.accepted_ids)
        self.assertTrue(all(self._rows(batch)[candidate_id]["state"] == "AI_PRE_ACCEPT" for candidate_id in self.accepted_ids))


if __name__ == "__main__":
    unittest.main()
