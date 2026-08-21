#!/usr/bin/env python3
"""Verify the Flutter assets emitted by a Drone production build."""

from __future__ import annotations

import argparse
from pathlib import Path
import sys


REQUIRED_QUESTION_BANK = Path(
    "assets/question_bank/drone_second_class_bank.json",
)
VALIDATION_ROOT = Path("assets/validation")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--flutter-assets",
        required=True,
        type=Path,
        help="The flutter_assets directory emitted by a production build.",
    )
    arguments = parser.parse_args()
    flutter_assets = arguments.flutter_assets
    if not flutter_assets.is_dir():
        print(f"Missing Flutter asset bundle: {flutter_assets}", file=sys.stderr)
        return 1

    missing = flutter_assets / REQUIRED_QUESTION_BANK
    if not missing.is_file():
        print(f"Missing production question-bank asset: {missing}", file=sys.stderr)
        return 1

    validation_assets = sorted(
        path for path in flutter_assets.rglob("*")
        if path.is_file() and VALIDATION_ROOT in path.relative_to(flutter_assets).parents
    )
    if validation_assets:
        print("Validation-only assets leaked into the production bundle:", file=sys.stderr)
        print(
            "\n".join(str(path) for path in validation_assets),
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
