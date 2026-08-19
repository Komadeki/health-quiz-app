#!/usr/bin/env python3
"""Generate deterministic V0-Panel validation artifacts."""

from __future__ import annotations

import argparse
from pathlib import Path

from v0_panel_validation import validate_contract, write_generated_files


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bank", required=True, type=Path)
    parser.add_argument(
        "--check",
        action="store_true",
        help="Fail when committed validation artifacts differ from source inputs.",
    )
    arguments = parser.parse_args()
    if arguments.check:
        errors = validate_contract(arguments.bank, check_generated=True)
        for error in errors:
            print(error)
        if errors:
            return 1
        print("V0-Panel validation artifacts are up to date.")
        return 0
    try:
        written = write_generated_files(arguments.bank)
    except ValueError as exception:
        print(exception)
        return 1
    for path in written:
        print(f"WROTE {path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
