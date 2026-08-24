from __future__ import annotations

import csv
import json
import shutil
import tempfile
import unittest
from pathlib import Path

import sys

TOOL_DIR = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(TOOL_DIR))

from ai_governance import AIGovernanceError, promote_ai_governed_candidates  # noqa: E402
from expansion import CANDIDATE_COLUMNS, REVIEW_COLUMNS, validate_expansion_batch  # noqa: E402
from transaction import QuestionExpansionTransaction  # noqa: E402


class AIGovernanceLifecycleTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.bank = Path(self.temp.name) / "question_banks" / "qualification_fixture"
        shutil.copytree(REPOSITORY_ROOT / "question_banks" / "qualification_fixture", self.bank)
        self.batch = self.bank / "authoring" / "batches" / "batch_001"
        self.batch.mkdir(parents=True)
        self.candidate_id = "B1-C001"
        self._write_batch()
        self._write_candidate()
        self._write_reviews([])
        self._write_packet()

    def _write_csv(self, path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)

    def _write_batch(self) -> None:
        payload = {
            "schema_version": "1.0",
            "app_key": "qualification_fixture",
            "batch_id": "B1",
            "directory_slug": "batch_001",
            "baseline_sha": "a" * 40,
            "batch_status": "AUTHORING",
            "expansion_trigger": "autonomous coverage expansion",
            "evidence": ["AI-governed acceptance contract"],
            "target_size_decisions": [{
                "decision_id": "T1",
                "previous_approved_target": 10,
                "current_released_count": 10,
                "proposed_target_min": 10,
                "proposed_target_max": 20,
                "approved_new_target": 20,
                "rationale": "approved expansion",
                "decision_date": "2026-08-24",
                "evidence": "coverage evidence",
            }],
            "planned_scope": {"known_rejected_ids": []},
            "coverage_limit_decisions": [],
            "migration_blockers": [],
        }
        (self.batch / "batch.json").write_text(json.dumps(payload), encoding="utf-8")

    def _candidate(self) -> dict[str, str]:
        row = {column: "" for column in CANDIDATE_COLUMNS}
        row.update({
            "candidate_id": self.candidate_id,
            "state": "AI_PRE_ACCEPT",
            "unit_id": "fixture_safety",
            "domain": "Risk",
            "knowledge_target_id": "RM1",
            "family": "scenario",
            "question": "飛行前に最初に確認すべき事項はどれか？",
            "choice1": "飛行場所の危険要因を確認する",
            "choice2": "確認せず離陸する",
            "choice3": "飛行後にだけ確認する",
            "proposed_correct": "A",
            "explanation": "飛行前に危険要因を確認する必要がある。",
            "source_id": "FIXTURE-SRC-001",
            "source_version": "2026.1",
            "source_locator": "p.1",
            "answer_defining_proposition": "飛行前に危険要因を確認する",
            "tested_misconception": "飛行後の確認で足りる",
            "reasoning_path": "hazard identification before flight",
            "collision_note": "fixture released bank, drafts, and batch checked; no collision",
        })
        return row

    def _write_candidate(self) -> None:
        self._write_csv(self.batch / "candidates.csv", list(CANDIDATE_COLUMNS), [self._candidate()])

    def _write_reviews(self, rows: list[dict[str, str]]) -> None:
        self._write_csv(self.batch / "reviews.csv", list(REVIEW_COLUMNS), rows)

    def _packet(self) -> dict[str, object]:
        candidate = self._candidate()
        return {
            "schema_version": "1.0",
            "candidate_id": self.candidate_id,
            "candidate_state": "AI_PRE_ACCEPT",
            "actors": {
                "author": {"id": "author-1", "role": "AI_AUTHOR"},
                "reviewer": {"id": "reviewer-1", "role": "AI_REVIEWER"},
                "director": {"id": "director-1", "role": "AI_DIRECTOR"},
            },
            "evidence": {
                "source": {
                    "source_id": candidate["source_id"],
                    "source_version": candidate["source_version"],
                    "source_locator": candidate["source_locator"],
                },
                "answer_defining_proposition": candidate["answer_defining_proposition"],
                "tested_misconception": candidate["tested_misconception"],
                "reasoning_path": candidate["reasoning_path"],
                "collision": {
                    "released_bank_checked": True,
                    "canonical_drafts_checked": True,
                    "batch_checked": True,
                    "note": candidate["collision_note"],
                },
            },
            "independent_review": {"decision": "ACCEPT", "rationale": "source and collision evidence pass"},
            "director_adjudication": {"decision": "ACCEPT", "rationale": "independent acceptance adopted"},
            "requested_state": "AI_GOVERNED_ACCEPT",
        }

    def _write_packet(self, mutate=None) -> None:
        packet = self._packet()
        if mutate is not None:
            mutate(packet)
        path = self.batch / "acceptance_packets" / f"{self.candidate_id}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(packet, ensure_ascii=False), encoding="utf-8")

    def _candidate_state(self) -> str:
        with (self.batch / "candidates.csv").open(newline="", encoding="utf-8") as handle:
            return next(csv.DictReader(handle))["state"]

    def test_valid_ai_governed_acceptance_promotes_to_ready_for_id(self) -> None:
        promote_ai_governed_candidates(self.batch, [self.candidate_id])
        self.assertEqual("READY_FOR_ID", self._candidate_state())
        self.assertEqual([], validate_expansion_batch(self.batch))

    def test_ready_for_id_without_human_or_ai_acceptance_fails(self) -> None:
        (self.batch / "acceptance_packets" / f"{self.candidate_id}.json").unlink()
        promote_path = self.batch / "candidates.csv"
        with promote_path.open(newline="", encoding="utf-8") as handle:
            fields = list((reader := csv.DictReader(handle)).fieldnames or [])
            rows = list(reader)
        rows[0]["state"] = "READY_FOR_ID"
        self._write_csv(promote_path, fields, rows)
        self.assertTrue(any("Human ACCEPT or valid AI-governed acceptance" in error for error in validate_expansion_batch(self.batch)))

    def test_actor_reuse_fails_closed_without_mutation(self) -> None:
        def mutate(packet):
            packet["actors"]["reviewer"]["id"] = "author-1"
        self._write_packet(mutate)
        with self.assertRaises(AIGovernanceError):
            promote_ai_governed_candidates(self.batch, [self.candidate_id])
        self.assertEqual("AI_PRE_ACCEPT", self._candidate_state())

    def test_source_binding_mismatch_fails_closed(self) -> None:
        def mutate(packet):
            packet["evidence"]["source"]["source_version"] = "stale"
        self._write_packet(mutate)
        with self.assertRaises(AIGovernanceError):
            promote_ai_governed_candidates(self.batch, [self.candidate_id])

    def test_transaction_allocates_after_ai_governed_promotion(self) -> None:
        promote_ai_governed_candidates(self.batch, [self.candidate_id])
        transaction = QuestionExpansionTransaction(self.bank, self.batch, [self.candidate_id])
        mapping = transaction.dry_run()
        self.assertEqual({self.candidate_id: "FIXTURE-Q-000004"}, mapping)
        self.assertEqual("READY_FOR_ID", self._candidate_state())


if __name__ == "__main__":
    unittest.main()
