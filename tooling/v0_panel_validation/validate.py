#!/usr/bin/env python3
"""Validate the Drone V0-Panel bundle contract and generated artifacts."""

from __future__ import annotations

import argparse
from pathlib import Path

from v0_panel_validation import validate_contract


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bank", required=True, type=Path)
    parser.add_argument("--check-generated", action="store_true")
    arguments = parser.parse_args()
    errors = validate_contract(
        arguments.bank,
        check_generated=arguments.check_generated,
    )
    for error in errors:
        print(error)
    print(f"V0-Panel validation complete: {len(errors)} error(s).")
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
