#!/usr/bin/env python3
"""Validate qualification authoring data and committed generated artifacts."""

from __future__ import annotations

import argparse
from pathlib import Path

from question_bank import validate_bank


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bank", required=True, type=Path)
    parser.add_argument(
        "--check-generated",
        action="store_true",
        help="Also fail on generated JSON or manifest drift.",
    )
    arguments = parser.parse_args()

    try:
        result = validate_bank(
            arguments.bank,
            check_generated=arguments.check_generated,
        )
    except (FileNotFoundError, ValueError) as error:
        print(f"ERROR [invalid_bank_layout] {error}")
        return 1

    for issue in result.issues:
        print(issue)
    print(
        f"Validation complete: {len(result.errors)} error(s), "
        f"{len(result.warnings)} warning(s)."
    )
    return 0 if result.is_valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
