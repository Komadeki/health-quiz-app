#!/usr/bin/env python3
"""Fail-closed validator for KOMADEKI autonomous question acceptance packets."""

from __future__ import annotations

import json
import sys
from pathlib import Path
from typing import Any

ALLOWED_DECISIONS = {"ACCEPT", "REWORK", "REJECT", "HOLD"}
EXPECTED_ROLES = {
    "author": "AI_AUTHOR",
    "reviewer": "AI_REVIEWER",
    "director": "AI_DIRECTOR",
}


def _text(value: Any) -> str:
    return str(value or "").strip()


def validate_packet(packet: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if packet.get("schema_version") != "1.0":
        errors.append("schema_version must be 1.0")

    candidate_id = _text(packet.get("candidate_id"))
    if not candidate_id:
        errors.append("candidate_id is required")
    if packet.get("candidate_state") != "AI_PRE_ACCEPT":
        errors.append("candidate_state must be AI_PRE_ACCEPT")

    actors = packet.get("actors")
    if not isinstance(actors, dict):
        errors.append("actors must be an object")
        actors = {}
    actor_ids: list[str] = []
    for name, role in EXPECTED_ROLES.items():
        actor = actors.get(name)
        if not isinstance(actor, dict):
            errors.append(f"actors.{name} must be an object")
            continue
        if actor.get("role") != role:
            errors.append(f"actors.{name}.role must be {role}")
        actor_id = _text(actor.get("id"))
        if not actor_id:
            errors.append(f"actors.{name}.id is required")
        else:
            actor_ids.append(actor_id)
        if _text(actor.get("role")) == "HUMAN":
            errors.append("HUMAN role cannot be fabricated by autonomous acceptance")
    if len(actor_ids) == 3 and len(set(actor_ids)) != 3:
        errors.append("author, reviewer, and director ids must be pairwise distinct")

    evidence = packet.get("evidence")
    if not isinstance(evidence, dict):
        errors.append("evidence must be an object")
        evidence = {}
    source = evidence.get("source")
    if not isinstance(source, dict):
        errors.append("evidence.source must be an object")
        source = {}
    for field in ("source_id", "source_version", "source_locator"):
        if not _text(source.get(field)):
            errors.append(f"evidence.source.{field} is required")
    for field in ("answer_defining_proposition", "tested_misconception", "reasoning_path"):
        if not _text(evidence.get(field)):
            errors.append(f"evidence.{field} is required")

    collision = evidence.get("collision")
    if not isinstance(collision, dict):
        errors.append("evidence.collision must be an object")
        collision = {}
    for field in ("released_bank_checked", "canonical_drafts_checked", "batch_checked"):
        if collision.get(field) is not True:
            errors.append(f"evidence.collision.{field} must be true")
    if not _text(collision.get("note")):
        errors.append("evidence.collision.note is required")

    reviewer = packet.get("independent_review")
    if not isinstance(reviewer, dict):
        errors.append("independent_review must be an object")
        reviewer = {}
    reviewer_decision = _text(reviewer.get("decision"))
    if reviewer_decision not in ALLOWED_DECISIONS:
        errors.append("independent_review.decision is invalid")
    if not _text(reviewer.get("rationale")):
        errors.append("independent_review.rationale is required")

    director = packet.get("director_adjudication")
    if not isinstance(director, dict):
        errors.append("director_adjudication must be an object")
        director = {}
    director_decision = _text(director.get("decision"))
    if director_decision not in ALLOWED_DECISIONS:
        errors.append("director_adjudication.decision is invalid")
    if not _text(director.get("rationale")):
        errors.append("director_adjudication.rationale is required")

    requested_state = _text(packet.get("requested_state"))
    if requested_state == "AI_GOVERNED_ACCEPT":
        if reviewer_decision != "ACCEPT":
            errors.append("AI_GOVERNED_ACCEPT requires independent reviewer ACCEPT")
        if director_decision != "ACCEPT":
            errors.append("AI_GOVERNED_ACCEPT requires director ACCEPT")
    elif requested_state not in {"REWORK", "REJECT", "HOLD"}:
        errors.append("requested_state must be AI_GOVERNED_ACCEPT, REWORK, REJECT, or HOLD")

    return errors


def accepted(packet: dict[str, Any]) -> bool:
    return not validate_packet(packet) and packet.get("requested_state") == "AI_GOVERNED_ACCEPT"


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: question_acceptance.py <packet.json>", file=sys.stderr)
        return 2
    path = Path(argv[1])
    try:
        packet = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        print(f"invalid packet: {exc}", file=sys.stderr)
        return 1
    if not isinstance(packet, dict):
        print("invalid packet: root must be an object", file=sys.stderr)
        return 1
    errors = validate_packet(packet)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("KOMADEKI autonomous question acceptance packet: VALID")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
