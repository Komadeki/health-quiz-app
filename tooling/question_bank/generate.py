#!/usr/bin/env python3
"""Generate deterministic runtime question-bank artifacts."""

from __future__ import annotations

import argparse
from pathlib import Path

from question_bank import validate_bank, write_generated_files


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bank", required=True, type=Path)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail when committed generated artifacts differ from authoring inputs.",
    )
    arguments = parser.parse_args()

    if arguments.check:
        result = validate_bank(arguments.bank, check_generated=True)
        for issue in result.issues:
            print(issue)
        if result.is_valid:
            print("Question bank generation is up to date.")
            return 0
        return 1

    try:
        written = write_generated_files(arguments.bank)
    except ValueError as error:
        print(error)
        return 1
    for path in written:
        print(f"WROTE {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
