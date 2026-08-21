#!/usr/bin/env python3
"""Print deterministic Question Factory readiness evidence."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from readiness import build_readiness_report, format_readiness_report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bank", required=True, type=Path)
    parser.add_argument("--check-generated", action="store_true")
    parser.add_argument("--json", action="store_true", dest="as_json")
    arguments = parser.parse_args()
    try:
        report, validation = build_readiness_report(
            arguments.bank, check_generated=arguments.check_generated
        )
    except (FileNotFoundError, ValueError) as error:
        print(f"ERROR [invalid_bank_layout] {error}")
        return 1
    if arguments.as_json:
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(format_readiness_report(report))
    return 0 if validation.is_valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
