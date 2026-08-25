from __future__ import annotations

import copy
import json
import sys
import unittest
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOL_DIR))

from validate_state import validate  # noqa: E402


class AutopilotStateTest(unittest.TestCase):
    def setUp(self) -> None:
        self.otsu4_state = json.loads((TOOL_DIR / "otsu4_state.json").read_text(encoding="utf-8"))

    def test_otsu4_state_is_valid(self) -> None:
        validate(self.otsu4_state)

    def test_active_state_requires_one_next_objective(self) -> None:
        invalid = copy.deepcopy(self.otsu4_state)
        invalid["next_atomic_objective"] = ""
        with self.assertRaisesRegex(ValueError, "next_atomic_objective"):
            validate(invalid)

    def test_human_blocked_state_requires_resumption_evidence(self) -> None:
        invalid = copy.deepcopy(self.otsu4_state)
        invalid["status"] = "HUMAN_BLOCKED"
        invalid["human_blocker"] = {"action": "Complete account authentication"}
        with self.assertRaisesRegex(ValueError, "human_blocker"):
            validate(invalid)


if __name__ == "__main__":
    unittest.main()
