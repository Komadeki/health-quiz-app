import sys
import unittest

from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from audit_draft_duplicates import main


class DraftDuplicateAuditTests(unittest.TestCase):
    def test_current_eisei1_bank_has_no_exact_duplicate_stems(self) -> None:
        bank = Path(__file__).resolve().parents[3] / "question_banks" / "eisei1"
        self.assertEqual(0, main_for(bank))


def main_for(bank: Path) -> int:
    import sys
    from unittest.mock import patch

    with patch.object(sys, "argv", ["audit_draft_duplicates", "--bank", str(bank)]):
        return main()
