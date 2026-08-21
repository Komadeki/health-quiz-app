import unittest

from detect_scope import classify


class DetectScopeTest(unittest.TestCase):
    def test_shared_change_runs_everything(self) -> None:
        scope = classify(["packages/quiz_engine/lib/quiz_engine.dart"])
        self.assertTrue(scope.shared)
        self.assertTrue(scope.health)
        self.assertTrue(scope.qualification_apps)

    def test_health_only_is_focused(self) -> None:
        scope = classify(["apps/health/lib/main.dart"])
        self.assertFalse(scope.shared)
        self.assertTrue(scope.health)
        self.assertFalse(scope.qualification_apps)

    def test_any_qualification_app_is_focused(self) -> None:
        scope = classify(["apps/_single_unlock_fixture/lib/main.dart"])
        self.assertFalse(scope.shared)
        self.assertFalse(scope.health)
        self.assertTrue(scope.qualification_apps)

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

    def test_documentation_only_keeps_final_gate(self) -> None:
        scope = classify(["README.md", "docs/CI.md"])
        self.assertTrue(scope.docs_only)
        self.assertFalse(scope.shared)
        self.assertFalse(scope.health)
        self.assertFalse(scope.qualification_apps)

    def test_unknown_and_empty_inputs_fail_safe_to_all(self) -> None:
        for paths in (["unexpected/config.json"], []):
            with self.subTest(paths=paths):
                scope = classify(paths)
                self.assertTrue(scope.shared)
                self.assertTrue(scope.health)
                self.assertTrue(scope.qualification_apps)

    def test_github_workflow_change_is_shared_not_docs_only(self) -> None:
        scope = classify([".github/workflows/README.md"])
        self.assertTrue(scope.shared)
        self.assertFalse(scope.docs_only)


if __name__ == "__main__":
    unittest.main()
