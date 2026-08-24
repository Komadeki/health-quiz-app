from __future__ import annotations

import csv
import json
import sys
import unittest
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPOSITORY_ROOT / "tooling" / "question_bank"))

from expansion import validate_expansion_batch  # noqa: E402

ACCEPTED_IDS = (
    "B4-OPS-C001", "B4-OPS-C002", "B4-OPS-C003", "B4-OPS-C004",
    "B4-OPS-C005", "B4-OPS-C006", "B4-OPS-C007", "B4-OPS-C008",
    "B4-OPS-C009", "B4-OPS-C010", "B4-OPS-C011", "B4-OPS-C012",
    "B4-OPS-C013", "B4-OPS-C014", "B4-OPS-C015", "B4-OPS-C017",
    "B4-OPS-C018", "B4-OPS-C019", "B4-OPS-C020",
)
EXPECTED = {candidate_id: f"DRONE-Q-{number:06d}" for candidate_id, number in zip(ACCEPTED_IDS, range(170, 189))}
REJECTED_ID = "B4-OPS-C016"


class B4IntegrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bank_root = REPOSITORY_ROOT / "question_banks" / "drone_second_class"
        self.authoring = self.bank_root / "authoring"
        self.batch = self.authoring / "batches" / "batch_004"
        with (self.batch / "candidates.csv").open(encoding="utf-8", newline="") as handle:
            self.candidates = {row["candidate_id"]: row for row in csv.DictReader(handle)}
        with (self.authoring / "question_id_registry.csv").open(encoding="utf-8", newline="") as handle:
            self.registry = {row["question_id"]: row for row in csv.DictReader(handle)}
        with (self.authoring / "questions.csv").open(encoding="utf-8", newline="") as handle:
            self.questions = {row["question_id"]: row for row in csv.DictReader(handle)}

    def test_exact_19_are_integrated_with_deterministic_ids(self) -> None:
        for candidate_id, question_id in EXPECTED.items():
            candidate = self.candidates[candidate_id]
            self.assertEqual("INTEGRATED", candidate["state"])
            self.assertEqual(question_id, candidate["permanent_question_id"])
            question = self.questions[question_id]
            self.assertEqual("draft", question["status"])
            self.assertEqual("drone_second_class_exam", question["deck_id"])
            self.assertEqual("drone_operations", question["unit_id"])
            self.assertEqual("1", question["question_version"])
            self.assertEqual("2", question["difficulty"])
            self.assertEqual("2", question["importance"])
            self.assertEqual("false", question["is_free"])
            self.assertEqual("", question["last_reviewed_at"])
            self.assertEqual("", question["notes_internal"])
            self.assertEqual(candidate["question"], question["question"])
            self.assertEqual(candidate["proposed_correct"], question["correct_choice"])
            self.assertEqual(candidate["source_locator"], question["source_locator"])
            registry = self.registry[question_id]
            self.assertEqual("used", registry["status"])
            self.assertEqual("", registry["first_used_bank_revision"])
            self.assertEqual("", registry["retired_at"])
            self.assertEqual(f"Expansion pre-release allocation: {candidate_id}", registry["notes"])
        self.assertEqual(188, len(self.questions))

    def test_c016_remains_rejected_from_integration(self) -> None:
        row = self.candidates[REJECTED_ID]
        self.assertEqual("AI_PRE_ACCEPT", row["state"])
        self.assertEqual("", row["permanent_question_id"])
        self.assertFalse((self.batch / "acceptance_packets" / f"{REJECTED_ID}.json").exists())
        self.assertNotIn(REJECTED_ID, {row["notes"] for row in self.registry.values()})

    def test_acceptance_packet_binding_and_release_runtime_invariants(self) -> None:
        packet_ids = {path.stem for path in (self.batch / "acceptance_packets").glob("*.json")}
        self.assertEqual(set(ACCEPTED_IDS), packet_ids)
        self.assertEqual([], validate_expansion_batch(self.batch))
        verifications = json.loads((self.authoring / "source_verifications.json").read_text(encoding="utf-8"))["verifications"]
        verified_ids = {row["question_id"] for row in verifications}
        self.assertTrue(all(question_id not in verified_ids for question_id in EXPECTED.values()))
        released = json.loads((self.authoring / "released_questions.json").read_text(encoding="utf-8"))["released_questions"]
        self.assertEqual(100, len(released))
        bank = json.loads((self.authoring / "bank.json").read_text(encoding="utf-8"))
        runtime = json.loads((self.bank_root / bank["runtime_output"]).read_text(encoding="utf-8"))
        runtime_count = sum(len(unit.get("cards", [])) for deck in runtime.get("decks", []) for unit in deck.get("units", []))
        self.assertEqual(100, runtime_count)


if __name__ == "__main__":
    unittest.main()
