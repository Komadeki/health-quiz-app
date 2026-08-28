#!/usr/bin/env python3
"""Fail closed on exact normalized duplicate draft-question stems."""

from __future__ import annotations

import argparse
import csv
import re
from collections import defaultdict
from pathlib import Path


def normalize(value: str) -> str:
    return re.sub(r"\s+", "", value).casefold()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bank", required=True, type=Path)
    args = parser.parse_args()
    with (args.bank / "authoring" / "questions.csv").open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    grouped: dict[str, list[str]] = defaultdict(list)
    for row in rows:
        if row["status"] in {"draft", "active"}:
            grouped[normalize(row["question"])].append(row["question_id"])
    duplicates = sorted(ids for ids in grouped.values() if len(ids) > 1)
    for ids in duplicates:
        print("EXACT_DUPLICATE_STEM " + ",".join(ids))
    return 1 if duplicates else 0


if __name__ == "__main__":
    raise SystemExit(main())
