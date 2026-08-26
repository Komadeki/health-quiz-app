import unittest

from detect_scope import classify


class DetectScopeTest(unittest.TestCase):
    def test_shared_change_runs_everything(self) -> None:
        scope = classify(["packages/quiz_engine/lib/quiz_engine.dart"])
        self.assertTrue(scope.shared)
        self.assertTrue(scope.health)
        self.assertTrue(scope.qualification_apps)
        self.assertFalse(scope.question_bank)

    def test_health_only_is_focused(self) -> None:
        scope = classify(["apps/health/lib/main.dart"])
        self.assertFalse(scope.shared)
        self.assertTrue(scope.health)
        self.assertFalse(scope.qualification_apps)
        self.assertFalse(scope.question_bank)

    def test_any_qualification_app_is_focused(self) -> None:
        scope = classify(["apps/_single_unlock_fixture/lib/main.dart"])
        self.assertFalse(scope.shared)
        self.assertFalse(scope.health)
        self.assertTrue(scope.qualification_apps)
        self.assertFalse(scope.question_bank)

        second = classify(["apps/future_qualification/lib/main.dart"])
        self.assertTrue(second.qualification_apps)

    def test_mixed_apps_run_both_app_jobs(self) -> None:
        scope = classify(
            [
                "apps/health/app.yaml",
                "apps/_single_unlock_fixture/app.yaml",
            ]
        )
        self.assertFalse(scope.shared)
        self.assertTrue(scope.health)
        self.assertTrue(scope.qualification_apps)
        self.assertFalse(scope.question_bank)

    def test_otsu4_candidate_and_state_changes_use_question_bank_fast_path(self) -> None:
        scope = classify(
            [
                "question_banks/otsu4/authoring/batches/batch_004/candidates.csv",
                "question_banks/otsu4/authoring/batches/batch_004/independent_review_r1.json",
                "tooling/komadeki_autopilot/otsu4_state.json",
                "docs/OTSU4_QUESTION_FACTORY_WAVE_MODE_V1.md",
            ]
        )
        self.assertFalse(scope.shared)
        self.assertFalse(scope.health)
        self.assertFalse(scope.qualification_apps)
        self.assertTrue(scope.question_bank)
        self.assertEqual(scope.reason, "question_bank_fast_path")

    def test_eisei_candidate_coverage_and_sources_use_question_bank_fast_path(self) -> None:
        scope = classify(
            [
                "question_banks/eisei1/authoring/batches/batch_002/batch.json",
                "question_banks/eisei1/authoring/batches/batch_002/candidates.csv",
                "question_banks/eisei1/authoring/coverage.json",
                "question_banks/eisei1/authoring/sources.json",
                "question_banks/eisei1/authoring/EISEI1_QUESTION_QUALITY_GATE_V1.md",
            ]
        )
        self.assertFalse(scope.shared)
        self.assertFalse(scope.health)
        self.assertFalse(scope.qualification_apps)
        self.assertTrue(scope.question_bank)
        self.assertEqual(scope.reason, "question_bank_fast_path")

    def test_eisei_source_verification_uses_question_bank_fast_path(self) -> None:
        scope = classify(["question_banks/eisei1/authoring/source_verifications.json"])
        self.assertFalse(scope.shared)
        self.assertTrue(scope.question_bank)

    def test_canonical_integration_remains_fail_safe_full_ci(self) -> None:
        for path in (
            "question_banks/otsu4/authoring/questions.csv",
            "question_banks/eisei1/authoring/questions.csv",
            "question_banks/eisei1/authoring/question_id_registry.csv",
            "question_banks/eisei1/authoring/released_questions.json",
            "question_banks/eisei1/authoring/bank.json",
            "question_banks/eisei1/generated/eisei1_bank.json",
        ):
            with self.subTest(path=path):
                scope = classify([path])
                self.assertTrue(scope.shared)
                self.assertTrue(scope.health)
                self.assertTrue(scope.qualification_apps)
                self.assertFalse(scope.question_bank)

    def test_otsu4_canonical_plus_state_remains_fail_safe_full_ci(self) -> None:
        scope = classify(
            [
                "question_banks/otsu4/authoring/questions.csv",
                "tooling/komadeki_autopilot/otsu4_state.json",
            ]
        )
        self.assertTrue(scope.shared)
        self.assertTrue(scope.health)
        self.assertTrue(scope.qualification_apps)
        self.assertFalse(scope.question_bank)

    def test_generic_tooling_mixed_with_question_bank_falls_back_to_full_ci(self) -> None:
        scope = classify(
            [
                "question_banks/eisei1/authoring/batches/batch_002/candidates.csv",
                "tooling/question_bank/expansion.py",
            ]
        )
        self.assertTrue(scope.shared)
        self.assertFalse(scope.question_bank)

    def test_shared_question_bank_contract_change_remains_full_ci(self) -> None:
        scope = classify(["question_banks/schema/question.schema.json"])
        self.assertTrue(scope.shared)
        self.assertFalse(scope.question_bank)

    def test_documentation_only_keeps_final_gate(self) -> None:
        scope = classify(["README.md", "docs/CI.md"])
        self.assertTrue(scope.docs_only)
        self.assertFalse(scope.shared)
        self.assertFalse(scope.health)
        self.assertFalse(scope.qualification_apps)
        self.assertFalse(scope.question_bank)

    def test_unknown_and_empty_inputs_fail_safe_to_all(self) -> None:
        for paths in (["unexpected/config.json"], []):
            with self.subTest(paths=paths):
                scope = classify(paths)
                self.assertTrue(scope.shared)
                self.assertTrue(scope.health)
                self.assertTrue(scope.qualification_apps)
                self.assertFalse(scope.question_bank)

    def test_github_workflow_change_is_shared_not_docs_only(self) -> None:
        scope = classify([".github/workflows/README.md"])
        self.assertTrue(scope.shared)
        self.assertFalse(scope.docs_only)
        self.assertFalse(scope.question_bank)


if __name__ == "__main__":
    unittest.main()
