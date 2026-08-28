#!/usr/bin/env python3
"""Apply an authoring playbook's stricter rules to a new expansion batch."""

from __future__ import annotations

import argparse
import csv
import json
import re
from pathlib import Path

from expansion import validate_expansion_batch


def _batch_number(batch_dir: Path) -> int | None:
    match = re.fullmatch(r"batch_(\d+)", batch_dir.name)
    return int(match.group(1)) if match else None


def validate_playbook_batch(batch_dir: Path, profile_path: Path) -> list[str]:
    errors = list(validate_expansion_batch(batch_dir))
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    start = _batch_number(Path(profile["applies_from_batch"]))
    current = _batch_number(batch_dir)
    if start is None or current is None or current < start:
        return errors
    contract = profile["candidate_contract"]
    with (batch_dir / "candidates.csv").open(newline="", encoding="utf-8-sig") as file:
        rows = list(csv.DictReader(file))
    if len(rows) > contract["maximum_candidates_per_batch"]:
        errors.append("candidate count exceeds the playbook maximum")
    for index, row in enumerate(rows, start=2):
        for field in contract["required_fields"]:
            if not (row.get(field) or "").strip():
                errors.append(f"candidates.csv:{index}: missing playbook field {field}")
        choice_count = sum(bool((row.get(f"choice{choice}") or "").strip()) for choice in range(1, 6))
        if choice_count < contract["minimum_choice_count"]:
            errors.append(
                f"candidates.csv:{index}: requires {contract['minimum_choice_count']} choices, found {choice_count}"
            )
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True, type=Path)
    parser.add_argument("--profile", required=True, type=Path)
    args = parser.parse_args()
    errors = validate_playbook_batch(args.batch, args.profile)
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print(f"PASS: {args.batch}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
