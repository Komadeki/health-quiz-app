#!/usr/bin/env python3
"""Materialize and promote the sole Director-accepted Eisei1 B6 candidate."""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tooling" / "question_bank"))

from ai_governance import (  # noqa: E402
    ai_acceptance_errors,
    candidate_fingerprint,
    promote_ai_governed_candidates,
)
from expansion import validate_expansion_batch  # noqa: E402


BATCH = REPO / "question_banks" / "eisei1" / "authoring" / "batches" / "batch_006"
CANDIDATE_ID = "E1-B6-HH-C001"
AUTHOR_ID = "eisei1-b6-author-r1"
REVIEWER_ID = "eisei1-b6-independent-reviewer-r1"
DIRECTOR_ID = "eisei1-b6-director-r1"
DIRECTOR_RATIONALE = (
    "The reviewer ACCEPT is adopted after an independent collision check. "
    "B6's single proposition is that an unknown harmful-substance concentration "
    "prohibits filtering respiratory protective equipment. This is materially "
    "distinct from B2's oxygen-deficiency-risk proposition requiring supplied-air "
    "equipment with SPF >= 1000: B6 neither asks for nor implies that selection. "
    "The current MHLW guidance at 4(1)ア directly binds B6's prohibition, and the "
    "recorded B3/B5 comparisons exclude the rejected supplied-air duplicates. "
    "This is AI-governed content acceptance only; it creates no Human review, "
    "permanent ID, canonical question, source verification, release, or runtime change."
)


def read_candidate() -> dict[str, str]:
    with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as handle:
        candidates = list(csv.DictReader(handle))
    if [candidate.get("candidate_id") for candidate in candidates] != [CANDIDATE_ID]:
        raise SystemExit("unexpected B6 candidate set")
    candidate = candidates[0]
    if candidate.get("state") != "AI_PRE_ACCEPT":
        raise SystemExit("B6 candidate must be AI_PRE_ACCEPT before promotion")
    if candidate.get("permanent_question_id", "").strip():
        raise SystemExit("B6 candidate must not have a permanent question ID")
    return candidate


def read_review() -> dict[str, object]:
    review = json.loads((BATCH / "independent_review_r1.json").read_text(encoding="utf-8"))
    if review.get("summary") != {"reviewed": 1, "accept": 1, "reject": 0, "rework": 0, "hold": 0}:
        raise SystemExit("unexpected B6 independent review summary")
    if review.get("author_identity_checked") != AUTHOR_ID:
        raise SystemExit("B6 review author identity drift")
    if review.get("identity_separation") != "PASS":
        raise SystemExit("B6 review identity separation failed")
    if review.get("reviewer") != {"id": REVIEWER_ID, "role": "AI_REVIEWER"}:
        raise SystemExit("B6 review reviewer identity drift")
    decisions = review.get("decisions")
    if not isinstance(decisions, list) or len(decisions) != 1:
        raise SystemExit("unexpected B6 review decision set")
    decision = decisions[0]
    if not isinstance(decision, dict) or decision.get("candidate_id") != CANDIDATE_ID:
        raise SystemExit("B6 review candidate identity drift")
    if decision.get("decision") != "ACCEPT" or not str(decision.get("rationale", "")).strip():
        raise SystemExit("B6 independent review must ACCEPT with rationale")
    collision = review.get("collision_review")
    if not isinstance(collision, dict) or collision.get("result") != "PASS":
        raise SystemExit("B6 review collision evidence failed")
    if not all(collision.get(field) is True for field in (
        "released_bank_checked",
        "canonical_drafts_checked",
        "persisted_candidates_checked",
        "full_batch_checked",
    )):
        raise SystemExit("B6 review collision scope is incomplete")
    if len({AUTHOR_ID, REVIEWER_ID, DIRECTOR_ID}) != 3:
        raise SystemExit("B6 AI actor identities must be pairwise distinct")
    return {"decision": decision, "collision": collision}


def main() -> None:
    candidate = read_candidate()
    review = read_review()
    packet_dir = BATCH / "acceptance_packets"
    packet_dir.mkdir(exist_ok=True)
    packet_file = packet_dir / f"{CANDIDATE_ID}.json"
    if packet_file.exists() or list(packet_dir.glob("*.json")):
        raise SystemExit("partial B6 acceptance packet state detected")

    decision = review["decision"]
    collision = review["collision"]
    assert isinstance(decision, dict)
    assert isinstance(collision, dict)
    packet = {
        "schema_version": "1.0",
        "candidate_id": CANDIDATE_ID,
        "candidate_state": "AI_PRE_ACCEPT",
        "candidate_fingerprint": candidate_fingerprint(candidate),
        "actors": {
            "author": {"id": AUTHOR_ID, "role": "AI_AUTHOR"},
            "reviewer": {"id": REVIEWER_ID, "role": "AI_REVIEWER"},
            "director": {"id": DIRECTOR_ID, "role": "AI_DIRECTOR"},
        },
        "evidence": {
            "source": {
                field: candidate[field]
                for field in ("source_id", "source_version", "source_locator")
            },
            "answer_defining_proposition": candidate["answer_defining_proposition"],
            "tested_misconception": candidate["tested_misconception"],
            "reasoning_path": candidate["reasoning_path"],
            "collision": {
                "released_bank_checked": True,
                "canonical_drafts_checked": True,
                "batch_checked": True,
                "note": candidate["collision_note"],
            },
        },
        "independent_review": {
            "decision": "ACCEPT",
            "rationale": decision["rationale"],
        },
        "director_adjudication": {
            "decision": "ACCEPT",
            "rationale": DIRECTOR_RATIONALE,
        },
        "requested_state": "AI_GOVERNED_ACCEPT",
    }
    packet_file.write_text(
        json.dumps(packet, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )

    errors = ai_acceptance_errors(BATCH, candidate)
    if errors:
        raise SystemExit("invalid B6 AI-governed packet: " + " | ".join(errors))
    promote_ai_governed_candidates(BATCH, [CANDIDATE_ID])

    with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as handle:
        promoted = next(csv.DictReader(handle))
    if promoted.get("state") != "READY_FOR_ID" or promoted.get("permanent_question_id"):
        raise SystemExit("B6 promotion failed")
    errors = validate_expansion_batch(BATCH)
    if errors:
        raise SystemExit("B6 expansion validation failed: " + " | ".join(errors))


if __name__ == "__main__":
    main()
