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
    qualification_apps: bool
    question_bank: bool
    docs_only: bool
    reason: str

    def output_lines(self) -> list[str]:
        return [
            f"shared={str(self.shared).lower()}",
            f"health={str(self.health).lower()}",
            f"qualification_apps={str(self.qualification_apps).lower()}",
            f"question_bank={str(self.question_bank).lower()}",
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

    non_docs = [path for path in normalized if not _is_documentation(path)]
    if non_docs and all(_is_question_bank_fast_path(path) for path in non_docs):
        return Scope(False, False, False, True, False, "question_bank_fast_path")

    shared = False
    health = False
    qualification_apps = False
    unknown = False
    for path in normalized:
        if _is_documentation(path):
            continue
        if _is_shared(path):
            shared = True
        elif path.startswith("apps/health/"):
            health = True
        elif path.startswith("apps/"):
            qualification_apps = True
        else:
            unknown = True

    if shared:
        return _all("shared_change")
    if unknown:
        return _all("unknown_path")
    return Scope(False, health, qualification_apps, False, False, "app_change")


def _normalize(path: str) -> str:
    value = path.strip().replace("\\", "/")
    return str(PurePosixPath(value)).removeprefix("./")


def _is_documentation(path: str) -> bool:
    if path == "README.md" or path.startswith("docs/"):
        return True
    if not path.endswith(".md"):
        return False
    return path.startswith(("apps/", "packages/", "question_banks/", "tooling/"))


def _is_question_bank_fast_path(path: str) -> bool:
    """Return True only for authoring-only bank mutations safe for focused CI.

    Canonical identity, released snapshots, generated artifacts and bank metadata
    intentionally remain on the fail-safe full-CI path. Qualification-specific
    candidate, coverage and source-evidence work can use the focused shared
    Question Factory validator regardless of app key.
    """
    if path == "tooling/komadeki_autopilot/otsu4_state.json":
        return True

    parts = PurePosixPath(path).parts
    if len(parts) < 4 or parts[0] != "question_banks" or parts[2] != "authoring":
        return False

    authoring_path = parts[3:]
    first = authoring_path[0]
    if first in {"batches", "waves"}:
        return True
    if first.startswith("BATCH_"):
        return True
    return first in {"coverage.json", "sources.json", "source_verifications.json"}


def _is_shared(path: str) -> bool:
    return path == ".gitignore" or path.startswith(
        ("packages/", "tooling/", "question_banks/", ".github/")
    )


def _all(reason: str) -> Scope:
    return Scope(True, True, True, False, False, reason)


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
