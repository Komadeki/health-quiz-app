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

from expansion import CANDIDATE_COLUMNS, REVIEW_COLUMNS, build_status_report, validate_expansion_batch  # noqa: E402


class ExpansionProtocolTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.bank = Path(self.temp.name) / "question_banks" / "qualification_fixture"
        shutil.copytree(REPOSITORY_ROOT / "question_banks" / "qualification_fixture", self.bank)
        self.batch = self.bank / "authoring" / "batches" / "batch_001"
        self.batch.mkdir(parents=True)
        self._write_valid_batch()

    def _write_valid_batch(self) -> None:
        batch = {
            "schema_version": "1.0",
            "app_key": "qualification_fixture",
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
            "unit_id": "fixture_safety",
            "domain": "Rules",
            "knowledge_target_id": "R1",
            "family": "scenario",
            "question": "Question?",
            "choice1": "A1",
            "choice2": "A2",
            "choice3": "A3",
            "proposed_correct": "A",
            "explanation": "Because.",
            "source_id": "FIXTURE-SRC-001",
            "source_version": "2026.1",
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

    def _canonical_question(self, question_id: str) -> dict[str, str]:
        with (self.bank / "authoring" / "questions.csv").open(
            newline="", encoding="utf-8"
        ) as handle:
            return next(
                row for row in csv.DictReader(handle) if row["question_id"] == question_id
            )

    def _bind_candidate_to_question(self, question_id: str, state: str) -> None:
        question = self._canonical_question(question_id)
        sources = json.loads(
            (self.bank / "authoring" / "sources.json").read_text(encoding="utf-8")
        )["sources"]
        source = next(item for item in sources if item["source_id"] == question["source_id"])
        self._mutate_candidate(
            state=state,
            permanent_question_id=question_id,
            unit_id=question["unit_id"],
            question=question["question"],
            choice1=question["choice1"],
            choice2=question["choice2"],
            choice3=question["choice3"],
            choice4=question["choice4"],
            proposed_correct=question["correct_choice"],
            explanation=question["explanation"],
            source_id=question["source_id"],
            source_version=str(source["source_version"]),
            source_locator=question["source_locator"],
        )

    def _install_prerelease_question(
        self, question_id: str = "FIXTURE-Q-000004", *, verified: bool = False
    ) -> str:
        authoring = self.bank / "authoring"
        with (authoring / "questions.csv").open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            question_fields = list(reader.fieldnames or [])
            questions = list(reader)
        draft = dict(questions[0])
        draft.update({
            "question_id": question_id,
            "question_version": "1",
            "status": "draft",
            "question": "架空施設で追加作業前に最初に行うことはどれか？",
            "notes_internal": "Expansion fixture draft",
        })
        questions.append(draft)
        self._write_csv(authoring / "questions.csv", question_fields, questions)

        with (authoring / "question_id_registry.csv").open(
            newline="", encoding="utf-8"
        ) as handle:
            reader = csv.DictReader(handle)
            registry_fields = list(reader.fieldnames or [])
            registry = list(reader)
        registry.append({
            "question_id": question_id,
            "status": "used",
            "first_used_bank_revision": "",
            "retired_at": "",
            "replacement_id": "",
            "notes": "Expansion fixture pre-release ID",
        })
        self._write_csv(authoring / "question_id_registry.csv", registry_fields, registry)

        if verified:
            verification_path = authoring / "source_verifications.json"
            payload = json.loads(verification_path.read_text(encoding="utf-8"))
            payload["verifications"].append({
                "question_id": question_id,
                "source_id": draft["source_id"],
                "source_version": "2026.1",
                "verification_state": "author_source_verified",
                "verified_at": "2026-08-22",
            })
            verification_path.write_text(json.dumps(payload), encoding="utf-8")
        return question_id

    def _set_registry_field(self, question_id: str, field: str, value: str) -> None:
        path = self.bank / "authoring" / "question_id_registry.csv"
        with path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            fields = list(reader.fieldnames or [])
            rows = list(reader)
        next(row for row in rows if row["question_id"] == question_id)[field] = value
        self._write_csv(path, fields, rows)

    def _remove_canonical_question(self, question_id: str) -> None:
        path = self.bank / "authoring" / "questions.csv"
        with path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            fields = list(reader.fieldnames or [])
            rows = [row for row in reader if row["question_id"] != question_id]
        self._write_csv(path, fields, rows)

    def _set_canonical_question_field(
        self, question_id: str, field: str, value: str
    ) -> None:
        path = self.bank / "authoring" / "questions.csv"
        with path.open(newline="", encoding="utf-8") as handle:
            reader = csv.DictReader(handle)
            fields = list(reader.fieldnames or [])
            rows = list(reader)
        next(row for row in rows if row["question_id"] == question_id)[field] = value
        self._write_csv(path, fields, rows)

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
        self._mutate_candidate(state="ID_ALLOCATED", permanent_question_id="FIXTURE-Q-000004")
        self.assertTrue(any("absent from canonical registry" in error for error in validate_expansion_batch(self.batch)))

    def test_id_allocated_rejects_retired_registry_tombstone(self) -> None:
        question_id = "FIXTURE-Q-000003"
        self._mutate_candidate(state="ID_ALLOCATED", permanent_question_id=question_id)
        self.assertTrue(any("not a valid pre-release used registry entry" in error for error in validate_expansion_batch(self.batch)))

    def test_id_allocated_rejects_nonempty_first_used_revision(self) -> None:
        question_id = "FIXTURE-Q-000001"
        self._mutate_candidate(state="ID_ALLOCATED", permanent_question_id=question_id)
        self.assertTrue(any("requires blank first_used_bank_revision" in error for error in validate_expansion_batch(self.batch)))

    def test_id_allocated_passes_with_unused_in_release_registry_row(self) -> None:
        question_id = self._install_prerelease_question()
        self._remove_canonical_question(question_id)
        self._mutate_candidate(state="ID_ALLOCATED", permanent_question_id=question_id)
        self.assertEqual([], validate_expansion_batch(self.batch))

    def test_integrated_requires_canonical_question(self) -> None:
        question_id = self._install_prerelease_question()
        self._remove_canonical_question(question_id)
        self._mutate_candidate(state="INTEGRATED", permanent_question_id=question_id)
        self.assertTrue(any("absent from canonical questions" in error for error in validate_expansion_batch(self.batch)))

    def test_verified_requires_canonical_verification(self) -> None:
        question_id = self._install_prerelease_question()
        self._bind_candidate_to_question(question_id, "VERIFIED")
        self.assertTrue(any("lacks canonical source verification" in error for error in validate_expansion_batch(self.batch)))

    def test_verified_rejects_stale_source_verification(self) -> None:
        question_id = self._install_prerelease_question(verified=True)
        verification_path = self.bank / "authoring" / "source_verifications.json"
        payload = json.loads(verification_path.read_text(encoding="utf-8"))
        next(
            row for row in payload["verifications"] if row["question_id"] == question_id
        )["source_version"] = "0"
        verification_path.write_text(json.dumps(payload), encoding="utf-8")
        self._bind_candidate_to_question(question_id, "VERIFIED")
        self.assertTrue(any("lacks canonical source verification" in error for error in validate_expansion_batch(self.batch)))

    def test_verified_requires_canonical_validator_pass(self) -> None:
        question_id = self._install_prerelease_question(verified=True)
        self._bind_candidate_to_question(question_id, "VERIFIED")
        self._set_canonical_question_field("FIXTURE-Q-000001", "choice2", "手順書を確認する")
        self.assertTrue(any("VERIFIED canonical bank validation failed" in error for error in validate_expansion_batch(self.batch)))

    def test_released_requires_snapshot_and_generated_runtime(self) -> None:
        question_id = self._install_prerelease_question(verified=True)
        self._set_registry_field(question_id, "first_used_bank_revision", "fixture-bank-v2")
        self._set_canonical_question_field(question_id, "status", "active")
        self._bind_candidate_to_question(question_id, "RELEASED")
        errors = validate_expansion_batch(self.batch)
        self.assertTrue(any("absent from released snapshot" in error for error in errors))
        self.assertTrue(any("absent from generated runtime" in error for error in errors))

    def test_released_passes_with_complete_canonical_evidence(self) -> None:
        question_id = "FIXTURE-Q-000001"
        self._bind_candidate_to_question(question_id, "RELEASED")
        self.assertEqual([], validate_expansion_batch(self.batch))

    def test_released_existing_id_cannot_be_claimed_by_unrelated_candidate(self) -> None:
        self._mutate_candidate(
            state="RELEASED", permanent_question_id="FIXTURE-Q-000001"
        )
        self.assertTrue(any("canonical content mismatch: question" in error for error in validate_expansion_batch(self.batch)))

    def test_released_rejects_each_candidate_content_mismatch(self) -> None:
        mismatches = (
            ("question", "別の問題本文"),
            ("choice1", "別の選択肢"),
            ("proposed_correct", "B"),
            ("explanation", "別の解説"),
            ("source_id", "OTHER-SOURCE"),
            ("source_locator", "別の箇所"),
        )
        for field, value in mismatches:
            with self.subTest(field=field):
                self._bind_candidate_to_question("FIXTURE-Q-000001", "RELEASED")
                self._mutate_candidate(**{field: value})
                self.assertTrue(any(
                    f"canonical content mismatch: {field}" in error
                    for error in validate_expansion_batch(self.batch)
                ))

    def test_integrated_requires_draft_canonical_status(self) -> None:
        self._bind_candidate_to_question("FIXTURE-Q-000001", "INTEGRATED")
        self.assertTrue(any("requires canonical status draft" in error for error in validate_expansion_batch(self.batch)))

    def test_integrated_rejects_candidate_question_mismatch(self) -> None:
        question_id = self._install_prerelease_question()
        self._bind_candidate_to_question(question_id, "INTEGRATED")
        self._mutate_candidate(question="別の問題本文")
        self.assertTrue(any("canonical content mismatch: question" in error for error in validate_expansion_batch(self.batch)))

    def test_integrated_rejects_candidate_choice_mismatch(self) -> None:
        question_id = self._install_prerelease_question()
        self._bind_candidate_to_question(question_id, "INTEGRATED")
        self._mutate_candidate(choice2="別の選択肢")
        self.assertTrue(any("canonical content mismatch: choice2" in error for error in validate_expansion_batch(self.batch)))

    def test_integrated_rejects_candidate_correct_answer_mismatch(self) -> None:
        question_id = self._install_prerelease_question()
        self._bind_candidate_to_question(question_id, "INTEGRATED")
        self._mutate_candidate(proposed_correct="B")
        self.assertTrue(any("canonical content mismatch: proposed_correct" in error for error in validate_expansion_batch(self.batch)))

    def test_integrated_rejects_candidate_explanation_mismatch(self) -> None:
        question_id = self._install_prerelease_question()
        self._bind_candidate_to_question(question_id, "INTEGRATED")
        self._mutate_candidate(explanation="別の解説")
        self.assertTrue(any("canonical content mismatch: explanation" in error for error in validate_expansion_batch(self.batch)))

    def test_integrated_rejects_candidate_source_id_mismatch(self) -> None:
        question_id = self._install_prerelease_question()
        self._bind_candidate_to_question(question_id, "INTEGRATED")
        self._mutate_candidate(source_id="OTHER-SOURCE")
        self.assertTrue(any("canonical content mismatch: source_id" in error for error in validate_expansion_batch(self.batch)))

    def test_integrated_rejects_candidate_source_locator_mismatch(self) -> None:
        question_id = self._install_prerelease_question()
        self._bind_candidate_to_question(question_id, "INTEGRATED")
        self._mutate_candidate(source_locator="別の箇所")
        self.assertTrue(any("canonical content mismatch: source_locator" in error for error in validate_expansion_batch(self.batch)))

    def test_integrated_rejects_candidate_source_version_mismatch(self) -> None:
        question_id = self._install_prerelease_question()
        self._bind_candidate_to_question(question_id, "INTEGRATED")
        self._mutate_candidate(source_version="old")
        self.assertTrue(any("canonical content mismatch: source_version" in error for error in validate_expansion_batch(self.batch)))

    def test_released_requires_active_canonical_status(self) -> None:
        question_id = "FIXTURE-Q-000001"
        self._bind_candidate_to_question(question_id, "RELEASED")
        self._set_canonical_question_field(question_id, "status", "draft")
        self.assertTrue(any("requires canonical status active" in error for error in validate_expansion_batch(self.batch)))

    def test_released_requires_first_used_revision(self) -> None:
        question_id = "FIXTURE-Q-000001"
        self._bind_candidate_to_question(question_id, "RELEASED")
        self._set_registry_field(question_id, "first_used_bank_revision", "")
        self.assertTrue(any("requires non-empty first_used_bank_revision" in error for error in validate_expansion_batch(self.batch)))

    def test_released_rejects_snapshot_answer_identity_mismatch(self) -> None:
        question_id = "FIXTURE-Q-000001"
        self._bind_candidate_to_question(question_id, "RELEASED")
        path = self.bank / "authoring" / "released_questions.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        next(
            row for row in payload["released_questions"] if row["question_id"] == question_id
        )["correct_choice"] = "B"
        path.write_text(json.dumps(payload), encoding="utf-8")
        self.assertTrue(any("released snapshot identity mismatch" in error for error in validate_expansion_batch(self.batch)))

    def test_released_rejects_generated_drift(self) -> None:
        question_id = "FIXTURE-Q-000001"
        self._bind_candidate_to_question(question_id, "RELEASED")
        path = self.bank / "generated" / "qualification_fixture_bank.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        card = next(
            card
            for unit in payload["decks"][0]["units"]
            for card in unit["cards"]
            if card["stableId"] == question_id
        )
        card["question"] = "generated drift"
        path.write_text(json.dumps(payload), encoding="utf-8")
        self.assertTrue(any("RELEASED canonical bank validation failed" in error for error in validate_expansion_batch(self.batch)))

    def test_expansion_uses_canonical_permanent_id_pattern(self) -> None:
        noncanonical = "FIXTURE-EXTRA-Q-000001"
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

    def test_target_decision_requires_real_calendar_date(self) -> None:
        self._mutate_batch(lambda payload: payload["target_size_decisions"][0].update({
            "decision_date": "2026-02-30"
        }))
        self.assertTrue(any("invalid decision_date" in error for error in validate_expansion_batch(self.batch)))

    def test_target_decision_dates_must_not_move_backward(self) -> None:
        def mutate(payload) -> None:
            payload["target_size_decisions"].append({
                "decision_id": "T2",
                "previous_approved_target": 20,
                "current_released_count": 10,
                "proposed_target_min": 20,
                "proposed_target_max": 30,
                "approved_new_target": 25,
                "rationale": "second decision",
                "decision_date": "2026-08-21",
                "evidence": "human approval",
            })
        self._mutate_batch(mutate)
        self.assertTrue(any("decision_date moves backward" in error for error in validate_expansion_batch(self.batch)))

    def test_invalid_target_history_is_not_reported_as_authoritative(self) -> None:
        self._mutate_batch(lambda payload: payload["target_size_decisions"][0].update({
            "decision_date": "2026-02-30"
        }))
        report = build_status_report(self.batch)
        self.assertIsNone(report["current_target_decision"])
        self.assertEqual("validation_invalid", report["current_target_decision_status"])

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

    def test_invalid_logical_batch_ids_fail(self) -> None:
        for batch_id in ("", "B0", "B-1", "batch1", "arbitrary"):
            with self.subTest(batch_id=batch_id):
                self._mutate_batch(lambda payload, value=batch_id: payload.update({"batch_id": value}))
                self.assertTrue(any("invalid logical batch_id" in error for error in validate_expansion_batch(self.batch)))

    def test_ready_for_id_requires_contiguous_three_or_four_choices(self) -> None:
        self._mutate_candidate(state="READY_FOR_ID", choice3="", choice4="A4")
        self.assertTrue(any("requires 3-4 contiguous choices" in error for error in validate_expansion_batch(self.batch)))

    def test_ready_for_id_rejects_exactly_two_choices(self) -> None:
        self._mutate_candidate(state="READY_FOR_ID", choice3="", choice4="")
        self.assertTrue(any("requires 3-4 contiguous choices" in error for error in validate_expansion_batch(self.batch)))

    def test_ready_for_id_rejects_normalized_duplicate_choices(self) -> None:
        self._mutate_candidate(state="READY_FOR_ID", choice2="  A1  ")
        self.assertTrue(any("requires unique normalized choices" in error for error in validate_expansion_batch(self.batch)))

    def test_known_rejected_candidate_id_cannot_be_reused(self) -> None:
        self._mutate_batch(lambda payload: payload["planned_scope"].update({
            "known_rejected_ids": ["B1-C001"]
        }))
        self.assertTrue(any("known rejected candidate_id reused" in error for error in validate_expansion_batch(self.batch)))

    def test_status_report_is_derived(self) -> None:
        report = build_status_report(self.batch)
        self.assertEqual(1, report["human_accept_count"])
        self.assertEqual({"HUMAN_ACCEPT": 1}, report["count_by_candidate_state"])
        self.assertEqual("valid", report["current_target_decision_status"])

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
