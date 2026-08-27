from __future__ import annotations

import csv
import json
import sys
import unittest
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parents[1]
REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(TOOL_DIR))

from expansion import validate_expansion_batch  # noqa: E402


class Eisei1B7DirectorReworkTest(unittest.TestCase):
    def setUp(self) -> None:
        self.b4 = REPOSITORY_ROOT / "question_banks/eisei1/authoring/batches/batch_004"
        self.batch = REPOSITORY_ROOT / "question_banks/eisei1/authoring/batches/batch_007"
        self.b4_rows = self._rows(self.b4)
        self.rows = self._rows(self.batch)

    @staticmethod
    def _rows(batch: Path) -> dict[str, dict[str, str]]:
        with (batch / "candidates.csv").open(encoding="utf-8", newline="") as handle:
            return {row["candidate_id"]: row for row in csv.DictReader(handle)}

    def test_batch_is_pre_id_reauthoring_for_only_b4_rework_items(self) -> None:
        metadata = json.loads((self.batch / "batch.json").read_text(encoding="utf-8"))
        self.assertEqual("B7", metadata["batch_id"])
        self.assertFalse(metadata["planned_scope"]["candidate_count_is_quota"])
        self.assertEqual(
            ["E1-B4-LH-C001", "E1-B4-LH-C003"],
            metadata["planned_scope"]["known_rejected_ids"],
        )
        self.assertEqual({"E1-B7-LH-C001", "E1-B7-LH-C002"}, set(self.rows))
        self.assertTrue(all(row["state"] == "AI_PRE_ACCEPT" for row in self.rows.values()))
        self.assertTrue(all(not row["permanent_question_id"] for row in self.rows.values()))

    def test_original_b4_history_is_unchanged_and_replacements_are_distinct(self) -> None:
        self.assertEqual("特定化学物質健康診断個人票の保存期間として正しいものはどれか。", self.b4_rows["E1-B4-LH-C001"]["question"])
        self.assertEqual("石綿等を取り扱う業務に常時従事する労働者に対する石綿健康診断の定期実施間隔として正しいものはどれか。", self.b4_rows["E1-B4-LH-C003"]["question"])
        self.assertIn("除く", self.rows["E1-B7-LH-C001"]["question"])
        self.assertEqual("5年間", self.rows["E1-B7-LH-C001"]["choice3"])
        self.assertIn("従事しないこととなった日から40年間", self.rows["E1-B7-LH-C002"]["choice4"])
        self.assertNotIn("6月以内ごと", self.rows["E1-B7-LH-C002"]["question"])
        self.assertNotIn("frequency", self.rows["E1-B7-LH-C002"]["family"])

    def test_current_primary_law_locators_bind_each_replacement(self) -> None:
        chemical = self.rows["E1-B7-LH-C001"]
        asbestos = self.rows["E1-B7-LH-C002"]
        self.assertEqual("E1-LAW-SPEC-CHEM", chemical["source_id"])
        self.assertEqual("特定化学物質障害予防規則第40条第1項・第2項", chemical["source_locator"])
        self.assertEqual("C", chemical["proposed_correct"])
        self.assertEqual("E1-LAW-ASBESTOS", asbestos["source_id"])
        self.assertEqual("石綿障害予防規則第41条", asbestos["source_locator"])
        self.assertEqual("D", asbestos["proposed_correct"])
        self.assertEqual([], validate_expansion_batch(self.batch))


if __name__ == "__main__":
    unittest.main()
