#!/usr/bin/env python3
"""Classify changed repository paths for fail-safe CI routing."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import PurePosixPath
import sys


@dataclass(frozen=True)
class Scope:
    shared: bool
    health: bool
    fixture: bool
    drone: bool
    docs_only: bool
    reason: str

    def output_lines(self) -> list[str]:
        return [
            f"shared={str(self.shared).lower()}",
            f"health={str(self.health).lower()}",
            f"fixture={str(self.fixture).lower()}",
            f"drone={str(self.drone).lower()}",
            f"docs_only={str(self.docs_only).lower()}",
            f"reason={self.reason}",
        ]


def classify(paths: list[str], *, force_all: bool = False) -> Scope:
    normalized = sorted({_normalize(path) for path in paths if path.strip()})
    if force_all:
        return _all("non_pr_trigger")
    if not normalized:
        return _all("empty_change_list")
    if all(_is_documentation(path) for path in normalized):
        return Scope(False, False, False, False, True, "documentation_only")

    shared = False
    health = False
    fixture = False
    drone = False
    unknown = False
    for path in normalized:
        if _is_documentation(path):
            continue
        if _is_shared(path):
            shared = True
        elif path.startswith("apps/health/"):
            health = True
        elif path.startswith("apps/_single_unlock_fixture/"):
            fixture = True
        elif path.startswith("apps/drone_second_class/"):
            drone = True
        else:
            unknown = True

    if shared:
        return _all("shared_change")
    if unknown:
        return _all("unknown_path")
    return Scope(False, health, fixture, drone, False, "app_change")


def _normalize(path: str) -> str:
    value = path.strip().replace("\\", "/")
    return str(PurePosixPath(value)).removeprefix("./")


def _is_documentation(path: str) -> bool:
    if path == "README.md" or path.startswith("docs/"):
        return True
    if not path.endswith(".md"):
        return False
    return path.startswith(("apps/", "packages/", "question_banks/", "tooling/"))


def _is_shared(path: str) -> bool:
    return path == ".gitignore" or path.startswith(
        ("packages/", "tooling/", "question_banks/", ".github/")
    )


def _all(reason: str) -> Scope:
    return Scope(True, True, True, True, False, reason)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--force-all", action="store_true")
    parser.add_argument("--github-output")
    arguments = parser.parse_args()
    scope = classify(sys.stdin.read().splitlines(), force_all=arguments.force_all)
    lines = scope.output_lines()
    print("\n".join(lines))
    if arguments.github_output:
        with open(arguments.github_output, "a", encoding="utf-8") as output:
            output.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
