from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL_DIR))

from question_acceptance import accepted, validate_packet  # noqa: E402


def valid_packet() -> dict:
    return {
        "schema_version": "1.0",
        "candidate_id": "B2-RM-C001",
        "candidate_state": "AI_PRE_ACCEPT",
        "candidate_fingerprint": "a" * 64,
        "actors": {
            "author": {"role": "AI_AUTHOR", "id": "author-model-a"},
            "reviewer": {"role": "AI_REVIEWER", "id": "reviewer-model-b"},
            "director": {"role": "AI_DIRECTOR", "id": "director-model-c"},
        },
        "evidence": {
            "source": {
                "source_id": "MLIT-UAS-SAFETY-GUIDE-5",
                "source_version": "5",
                "source_locator": "6.2",
            },
            "answer_defining_proposition": "Distinct proposition.",
            "tested_misconception": "Distinct misconception.",
            "reasoning_path": "condition -> hazard -> control -> decision",
            "collision": {
                "released_bank_checked": True,
                "canonical_drafts_checked": True,
                "batch_checked": True,
                "note": "No semantic collision identified.",
            },
        },
        "independent_review": {
            "decision": "ACCEPT",
            "rationale": "Source support and collision evidence pass.",
        },
        "director_adjudication": {
            "decision": "ACCEPT",
            "rationale": "Independent evidence supports acceptance.",
        },
        "requested_state": "AI_GOVERNED_ACCEPT",
    }


class AutonomousQuestionAcceptanceTest(unittest.TestCase):
    def test_valid_packet_is_accepted(self) -> None:
        packet = valid_packet()
        self.assertEqual([], validate_packet(packet))
        self.assertTrue(accepted(packet))

    def test_candidate_fingerprint_is_required(self) -> None:
        packet = valid_packet()
        packet["candidate_fingerprint"] = ""
        self.assertTrue(any("candidate_fingerprint" in error for error in validate_packet(packet)))
        packet["candidate_fingerprint"] = "A" * 64
        self.assertTrue(any("candidate_fingerprint" in error for error in validate_packet(packet)))

    def test_roles_must_be_pairwise_distinct(self) -> None:
        packet = valid_packet()
        packet["actors"]["reviewer"]["id"] = packet["actors"]["author"]["id"]
        self.assertTrue(any("pairwise distinct" in error for error in validate_packet(packet)))

    def test_autonomous_path_cannot_claim_human_role(self) -> None:
        packet = valid_packet()
        packet["actors"]["reviewer"]["role"] = "HUMAN"
        errors = validate_packet(packet)
        self.assertTrue(any("AI_REVIEWER" in error for error in errors))
        self.assertTrue(any("HUMAN role" in error for error in errors))

    def test_accept_requires_independent_reviewer_accept(self) -> None:
        packet = valid_packet()
        packet["independent_review"]["decision"] = "REWORK"
        self.assertTrue(any("reviewer ACCEPT" in error for error in validate_packet(packet)))
        self.assertFalse(accepted(packet))

    def test_accept_requires_director_accept(self) -> None:
        packet = valid_packet()
        packet["director_adjudication"]["decision"] = "HOLD"
        self.assertTrue(any("director ACCEPT" in error for error in validate_packet(packet)))
        self.assertFalse(accepted(packet))

    def test_source_and_collision_evidence_are_required(self) -> None:
        packet = valid_packet()
        packet["evidence"]["source"]["source_locator"] = ""
        packet["evidence"]["collision"]["canonical_drafts_checked"] = False
        errors = validate_packet(packet)
        self.assertTrue(any("source_locator" in error for error in errors))
        self.assertTrue(any("canonical_drafts_checked" in error for error in errors))

    def test_reasoning_evidence_is_required(self) -> None:
        for field in ("answer_defining_proposition", "tested_misconception", "reasoning_path"):
            packet = copy.deepcopy(valid_packet())
            packet["evidence"][field] = ""
            self.assertTrue(any(field in error for error in validate_packet(packet)))


if __name__ == "__main__":
    unittest.main()
