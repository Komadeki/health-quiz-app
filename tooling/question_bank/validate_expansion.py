#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

from expansion import validate_expansion_batch


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate a pre-ID question bank expansion batch.")
    parser.add_argument("--batch", required=True, type=Path)
    args = parser.parse_args()
    errors = validate_expansion_batch(args.batch)
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print(f"PASS: {args.batch}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
