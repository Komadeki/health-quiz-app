from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tooling" / "question_bank"))
from otsu4_next_batch import build_plan


class Otsu4NextBatchTest(unittest.TestCase):
    def test_selects_largest_verified_coverage_deficit_in_a_bounded_batch(self) -> None:
        plan = build_plan(ROOT / "question_banks" / "otsu4")
        self.assertEqual("O4-PHY-KT-CALCULATION-BOUNDARY", plan["next_batch"]["knowledge_target_id"])
        self.assertEqual(10, plan["next_batch"]["candidate_ceiling"])
        self.assertTrue(plan["next_batch"]["must_be_source_verified_before_integration"])
        self.assertEqual(305, plan["canonical_draft_count"])


if __name__ == "__main__":
    unittest.main()
