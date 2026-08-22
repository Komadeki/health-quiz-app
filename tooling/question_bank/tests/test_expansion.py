from __future__ import annotations

import csv
import json
import tempfile
import unittest
from pathlib import Path

import sys

TOOL_DIR = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(TOOL_DIR))

from expansion import CANDIDATE_COLUMNS, REVIEW_COLUMNS, build_status_report, validate_expansion_batch  # noqa: E402


class ExpansionProtocolTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.bank = Path(self.temp.name) / "question_banks" / "fixture"
        self.batch = self.bank / "authoring" / "batches" / "batch_001"
        self.batch.mkdir(parents=True)
        self._write_canonical_fixture()
        self._write_valid_batch()

    def _write_canonical_fixture(self) -> None:
        authoring = self.bank / "authoring"
        generated = self.bank / "generated"
        generated.mkdir(parents=True)
        (authoring / "bank.json").write_text(
            json.dumps({"app_key": "fixture", "bank_revision": "fixture-v1"}), encoding="utf-8"
        )
        self._write_csv(authoring / "question_id_registry.csv", ["question_id", "status"], [])
        self._write_csv(authoring / "questions.csv", ["question_id"], [])
        (authoring / "released_questions.json").write_text(
            json.dumps({"released_questions": []}), encoding="utf-8"
        )
        (authoring / "source_verifications.json").write_text(
            json.dumps({"verifications": []}), encoding="utf-8"
        )
        (generated / "fixture_bank.json").write_text(
            json.dumps({"appKey": "fixture", "decks": []}), encoding="utf-8"
        )

    def _write_valid_batch(self) -> None:
        batch = {
            "schema_version": "1.0",
            "app_key": "fixture",
            "batch_id": "B1",
            "directory_slug": "batch_001",
            "baseline_sha": "a" * 40,
            "batch_status": "AUTHORING",
            "expansion_trigger": "coverage expansion",
            "evidence": ["human decision"],
            "target_size_decisions": [{
                "decision_id": "T1",
                "previous_approved_target": 10,
                "current_released_count": 10,
                "proposed_target_min": 10,
                "proposed_target_max": 20,
                "approved_new_target": 20,
                "rationale": "approved expansion",
                "decision_date": "2026-08-22",
                "evidence": "human approval",
            }],
            "planned_scope": {"known_rejected_ids": []},
            "coverage_limit_decisions": [],
            "migration_blockers": [],
        }
        (self.batch / "batch.json").write_text(json.dumps(batch), encoding="utf-8")
        candidate = {column: "" for column in CANDIDATE_COLUMNS}
        candidate.update({
            "candidate_id": "B1-C001",
            "state": "HUMAN_ACCEPT",
            "unit_id": "fixture_rules",
            "domain": "Rules",
            "knowledge_target_id": "R1",
            "family": "scenario",
            "question": "Question?",
            "choice1": "A1",
            "choice2": "A2",
            "choice3": "A3",
            "proposed_correct": "A",
            "explanation": "Because.",
            "source_id": "SRC-1",
            "source_version": "1",
            "source_locator": "p.1",
        })
        self._write_csv(self.batch / "candidates.csv", list(CANDIDATE_COLUMNS), [candidate])
        review = {column: "" for column in REVIEW_COLUMNS}
        review.update({
            "candidate_id": "B1-C001",
            "review_round": "1",
            "decision": "ACCEPT",
            "reviewer_role": "HUMAN",
        })
        self._write_csv(self.batch / "reviews.csv", list(REVIEW_COLUMNS), [review])

    def _read_csv(self, name: str) -> tuple[list[str], list[dict[str, str]]]:
        with (self.batch / name).open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            return list(reader.fieldnames or []), list(reader)

    def _write_csv(self, path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)

    def _mutate_candidate(self, **changes: str) -> None:
        fields, rows = self._read_csv("candidates.csv")
        rows[0].update(changes)
        self._write_csv(self.batch / "candidates.csv", fields, rows)

    def _mutate_review(self, **changes: str) -> None:
        fields, rows = self._read_csv("reviews.csv")
        rows[0].update(changes)
        self._write_csv(self.batch / "reviews.csv", fields, rows)

    def _mutate_batch(self, mutate) -> None:
        path = self.batch / "batch.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        mutate(payload)
        path.write_text(json.dumps(payload), encoding="utf-8")

    def _install_canonical_evidence(
        self,
        question_id: str,
        *,
        registry: bool = False,
        question: bool = False,
        verified: bool = False,
        released: bool = False,
        generated: bool = False,
    ) -> None:
        authoring = self.bank / "authoring"
        if registry:
            self._write_csv(
                authoring / "question_id_registry.csv",
                ["question_id", "status"],
                [{"question_id": question_id, "status": "used"}],
            )
        if question:
            self._write_csv(
                authoring / "questions.csv", ["question_id"], [{"question_id": question_id}]
            )
        if verified:
            (authoring / "source_verifications.json").write_text(
                json.dumps({"verifications": [{
                    "question_id": question_id,
                    "verification_state": "author_source_verified",
                }]}),
                encoding="utf-8",
            )
        if released:
            (authoring / "released_questions.json").write_text(
                json.dumps({"released_questions": [{"question_id": question_id}]}),
                encoding="utf-8",
            )
        if generated:
            (self.bank / "generated" / "fixture_bank.json").write_text(
                json.dumps({"appKey": "fixture", "decks": [{"units": [{"cards": [
                    {"stableId": question_id}
                ]}]}]}),
                encoding="utf-8",
            )

    def test_valid_expansion_batch_passes(self) -> None:
        self.assertEqual([], validate_expansion_batch(self.batch))

    def test_duplicate_candidate_id_fails(self) -> None:
        fields, rows = self._read_csv("candidates.csv")
        rows.append(dict(rows[0]))
        self._write_csv(self.batch / "candidates.csv", fields, rows)
        self.assertTrue(any("duplicate candidate_id" in error for error in validate_expansion_batch(self.batch)))

    def test_invalid_state_fails(self) -> None:
        self._mutate_candidate(state="NOT_A_STATE")
        self.assertTrue(any("invalid candidate state" in error for error in validate_expansion_batch(self.batch)))

    def test_human_accept_without_accept_review_fails(self) -> None:
        self._mutate_review(decision="HOLD", reason_code="WAIT", resume_condition="new evidence")
        self.assertTrue(any("conflicts with candidate state" in error for error in validate_expansion_batch(self.batch)))

    def test_ai_reviewer_cannot_satisfy_human_gate(self) -> None:
        self._mutate_review(reviewer_role="AI")
        errors = validate_expansion_batch(self.batch)
        self.assertTrue(any("reviewer_role must be HUMAN" in error for error in errors))
        self.assertTrue(any("has no Human review" in error for error in errors))

    def test_reject_without_reason_fails(self) -> None:
        self._mutate_candidate(state="REJECT")
        self._mutate_review(decision="REJECT")
        self.assertTrue(any("REJECT review requires reason" in error for error in validate_expansion_batch(self.batch)))

    def test_hold_without_reason_or_resume_condition_fails(self) -> None:
        self._mutate_candidate(state="HOLD")
        self._mutate_review(decision="HOLD")
        errors = validate_expansion_batch(self.batch)
        self.assertTrue(any("HOLD review requires reason" in error for error in errors))
        self.assertTrue(any("HOLD review requires resume_condition" in error for error in errors))

    def test_id_allocated_without_permanent_id_fails(self) -> None:
        self._mutate_candidate(state="ID_ALLOCATED")
        self.assertTrue(any("requires permanent_question_id" in error for error in validate_expansion_batch(self.batch)))

    def test_id_allocated_requires_registry_membership(self) -> None:
        self._mutate_candidate(state="ID_ALLOCATED", permanent_question_id="FIXTURE-Q-000001")
        self.assertTrue(any("absent from canonical registry" in error for error in validate_expansion_batch(self.batch)))

    def test_integrated_requires_canonical_question(self) -> None:
        question_id = "FIXTURE-Q-000001"
        self._install_canonical_evidence(question_id, registry=True)
        self._mutate_candidate(state="INTEGRATED", permanent_question_id=question_id)
        self.assertTrue(any("absent from canonical questions" in error for error in validate_expansion_batch(self.batch)))

    def test_verified_requires_canonical_verification(self) -> None:
        question_id = "FIXTURE-Q-000001"
        self._install_canonical_evidence(question_id, registry=True, question=True)
        self._mutate_candidate(state="VERIFIED", permanent_question_id=question_id)
        self.assertTrue(any("lacks canonical source verification" in error for error in validate_expansion_batch(self.batch)))

    def test_released_requires_snapshot_and_generated_runtime(self) -> None:
        question_id = "FIXTURE-Q-000001"
        self._install_canonical_evidence(question_id, registry=True, question=True, verified=True)
        self._mutate_candidate(state="RELEASED", permanent_question_id=question_id)
        errors = validate_expansion_batch(self.batch)
        self.assertTrue(any("absent from released snapshot" in error for error in errors))
        self.assertTrue(any("absent from generated runtime" in error for error in errors))

    def test_expansion_uses_canonical_permanent_id_pattern(self) -> None:
        noncanonical = "FIXTURE-EXTRA-Q-000001"
        self._install_canonical_evidence(noncanonical, registry=True)
        self._mutate_candidate(state="ID_ALLOCATED", permanent_question_id=noncanonical)
        self.assertTrue(any("invalid permanent_question_id" in error for error in validate_expansion_batch(self.batch)))

    def test_pre_id_candidate_with_permanent_id_fails(self) -> None:
        self._mutate_candidate(permanent_question_id="FIXTURE-Q-000001")
        self.assertTrue(any("must not have permanent_question_id" in error for error in validate_expansion_batch(self.batch)))

    def test_duplicate_permanent_mapping_fails(self) -> None:
        fields, rows = self._read_csv("candidates.csv")
        first = rows[0]
        first["state"] = "ID_ALLOCATED"
        first["permanent_question_id"] = "FIXTURE-Q-000001"
        second = dict(first)
        second["candidate_id"] = "B1-C002"
        rows.append(second)
        self._write_csv(self.batch / "candidates.csv", fields, rows)
        review_fields, reviews = self._read_csv("reviews.csv")
        second_review = dict(reviews[0])
        second_review["candidate_id"] = "B1-C002"
        reviews.append(second_review)
        self._write_csv(self.batch / "reviews.csv", review_fields, reviews)
        self.assertTrue(any("duplicate permanent ID mapping" in error for error in validate_expansion_batch(self.batch)))

    def test_duplicate_review_round_fails(self) -> None:
        fields, rows = self._read_csv("reviews.csv")
        rows.append(dict(rows[0]))
        self._write_csv(self.batch / "reviews.csv", fields, rows)
        self.assertTrue(any("duplicate review_round" in error for error in validate_expansion_batch(self.batch)))

    def test_review_round_must_be_monotonic(self) -> None:
        fields, rows = self._read_csv("reviews.csv")
        round3 = dict(rows[0])
        round3["review_round"] = "3"
        round2 = dict(rows[0])
        round2["review_round"] = "2"
        rows.extend([round3, round2])
        self._write_csv(self.batch / "reviews.csv", fields, rows)
        self.assertTrue(any("strictly increasing" in error for error in validate_expansion_batch(self.batch)))

    def test_invalid_target_decision_fails(self) -> None:
        self._mutate_batch(lambda payload: payload["target_size_decisions"][0].update({
            "proposed_target_min": 30, "proposed_target_max": 20
        }))
        self.assertTrue(any("min greater than max" in error for error in validate_expansion_batch(self.batch)))

    def test_approved_target_must_be_within_proposed_range(self) -> None:
        self._mutate_batch(lambda payload: payload["target_size_decisions"][0].update({
            "approved_new_target": 25
        }))
        self.assertTrue(any("within proposed range" in error for error in validate_expansion_batch(self.batch)))

    def test_target_decision_chain_must_be_continuous(self) -> None:
        def mutate(payload) -> None:
            payload["target_size_decisions"].append({
                "decision_id": "T2",
                "previous_approved_target": 19,
                "current_released_count": 10,
                "proposed_target_min": 20,
                "proposed_target_max": 30,
                "approved_new_target": 25,
                "rationale": "second decision",
                "decision_date": "2026-08-23",
                "evidence": "human approval",
            })
        self._mutate_batch(mutate)
        self.assertTrue(any("chain continuity" in error for error in validate_expansion_batch(self.batch)))

    def test_status_human_accept_count_comes_from_latest_human_review(self) -> None:
        self._mutate_candidate(state="READY_FOR_ID")
        report = build_status_report(self.batch)
        self.assertEqual(1, report["human_accept_count"])
        self._mutate_review(reviewer_role="AI")
        report = build_status_report(self.batch)
        self.assertEqual(0, report["human_accept_count"])

    def test_schema_version_is_validated(self) -> None:
        self._mutate_batch(lambda payload: payload.update({"schema_version": "2.0"}))
        self.assertTrue(any("unsupported schema_version" in error for error in validate_expansion_batch(self.batch)))

    def test_directory_slug_is_validated(self) -> None:
        self._mutate_batch(lambda payload: payload.update({"directory_slug": "wrong_slug"}))
        self.assertTrue(any("directory_slug must match" in error for error in validate_expansion_batch(self.batch)))

    def test_app_key_is_validated_against_canonical_bank(self) -> None:
        self._mutate_batch(lambda payload: payload.update({"app_key": "other"}))
        self.assertTrue(any("app_key must match" in error for error in validate_expansion_batch(self.batch)))

    def test_duplicate_logical_batch_id_fails(self) -> None:
        sibling = self.batch.parent / "batch_002"
        sibling.mkdir()
        payload = json.loads((self.batch / "batch.json").read_text(encoding="utf-8"))
        payload["directory_slug"] = "batch_002"
        (sibling / "batch.json").write_text(json.dumps(payload), encoding="utf-8")
        self.assertTrue(any("duplicate logical batch_id" in error for error in validate_expansion_batch(self.batch)))

    def test_ready_for_id_requires_contiguous_three_or_four_choices(self) -> None:
        self._mutate_candidate(state="READY_FOR_ID", choice3="", choice4="A4")
        self.assertTrue(any("requires 3-4 contiguous choices" in error for error in validate_expansion_batch(self.batch)))

    def test_known_rejected_candidate_id_cannot_be_reused(self) -> None:
        self._mutate_batch(lambda payload: payload["planned_scope"].update({
            "known_rejected_ids": ["B1-C001"]
        }))
        self.assertTrue(any("known rejected candidate_id reused" in error for error in validate_expansion_batch(self.batch)))

    def test_status_report_is_derived(self) -> None:
        report = build_status_report(self.batch)
        self.assertEqual(1, report["human_accept_count"])
        self.assertEqual({"HUMAN_ACCEPT": 1}, report["count_by_candidate_state"])

    def test_migrated_drone_accept_set_passes(self) -> None:
        drone = REPOSITORY_ROOT / "question_banks" / "drone_second_class" / "authoring" / "batches" / "batch_001"
        self.assertEqual([], validate_expansion_batch(drone))
        with (drone / "candidates.csv").open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(18, len(rows))
        self.assertEqual({"HUMAN_ACCEPT"}, {row["state"] for row in rows})
        self.assertTrue(all(not row["permanent_question_id"] for row in rows))
        self.assertEqual(
            [f"B1-R-C{i:03d}" for i in range(1, 17)] + ["B1-R-C023", "B1-R-C024"],
            [row["candidate_id"] for row in rows],
        )
        c024 = next(row for row in rows if row["candidate_id"] == "B1-R-C024")
        self.assertIn("別途必要となる", c024["choice1"])


if __name__ == "__main__":
    unittest.main()
