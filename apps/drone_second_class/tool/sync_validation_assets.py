#!/usr/bin/env python3
"""Copy immutable bank-side V0P-1 artifacts into the validation-only app."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys
import tempfile


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
SOURCE_ROOT = REPOSITORY_ROOT / "question_banks/drone_second_class/validation"
OUTPUT_ROOT = REPOSITORY_ROOT / "apps/drone_second_class/assets/validation"
COPIES = {
    SOURCE_ROOT / "protocol.json": OUTPUT_ROOT / "protocol.json",
    SOURCE_ROOT / "generated/validation_bundle.json":
        OUTPUT_ROOT / "validation_bundle.json",
    SOURCE_ROOT / "generated/validation_manifest.json":
        OUTPUT_ROOT / "validation_manifest.json",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    failures: list[str] = []
    for source, output in COPIES.items():
        source_bytes = source.read_bytes()
        if arguments.check:
            if not output.is_file() or output.read_bytes() != source_bytes:
                failures.append(f"validation asset drift: {output}")
            continue
        output.parent.mkdir(parents=True, exist_ok=True)
        descriptor, temporary_name = tempfile.mkstemp(
            dir=output.parent,
            prefix=f".{output.name}.",
        )
        try:
            with os.fdopen(descriptor, "wb") as temporary:
                temporary.write(source_bytes)
                temporary.flush()
                os.fsync(temporary.fileno())
            os.replace(temporary_name, output)
        finally:
            if os.path.exists(temporary_name):
                os.unlink(temporary_name)
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
