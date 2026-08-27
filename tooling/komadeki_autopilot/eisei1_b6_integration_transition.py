#!/usr/bin/env python3
"""Allocate and integrate the accepted Eisei1 B6 candidate."""

from __future__ import annotations

import csv
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "tooling" / "question_bank"))

from expansion import validate_expansion_batch  # noqa: E402
from transaction import QuestionExpansionTransaction  # noqa: E402
from eisei1_ready_for_id_integration_transition import canonical_row  # noqa: E402

BANK = REPOSITORY_ROOT / "question_banks" / "eisei1"
BATCH = BANK / "authoring" / "batches" / "batch_006"
CANDIDATE_ID = "E1-B6-HH-C001"
QUESTION_ID = "EISEI1-Q-000008"


def rows(path: Path) -> dict[str, dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return {row["candidate_id"]: row for row in csv.DictReader(handle)}


def main() -> None:
    candidate = rows(BATCH / "candidates.csv")[CANDIDATE_ID]
    if candidate["state"] != "READY_FOR_ID" or candidate["permanent_question_id"]:
        raise SystemExit("B6 must be READY_FOR_ID without a permanent ID")
    if not (BATCH / "acceptance_packets" / f"{CANDIDATE_ID}.json").is_file():
        raise SystemExit("B6 acceptance packet is required")
    transaction = QuestionExpansionTransaction(BANK, BATCH, (CANDIDATE_ID,), question_factory=canonical_row)
    expected = {CANDIDATE_ID: QUESTION_ID}
    if transaction.plan().mapping != expected or transaction.apply() != expected:
        raise SystemExit("unexpected B6 permanent-ID allocation")
    integrated = rows(BATCH / "candidates.csv")[CANDIDATE_ID]
    if integrated["state"] != "INTEGRATED" or integrated["permanent_question_id"] != QUESTION_ID:
        raise SystemExit("B6 integration postcondition failed")
    errors = validate_expansion_batch(BATCH)
    if errors:
        raise SystemExit("B6 expansion validation failed: " + " | ".join(errors))


if __name__ == "__main__":
    main()
