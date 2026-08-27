#!/usr/bin/env python3
"""Advance only independently accepted Eisei1 B4 candidates to READY_FOR_ID."""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPOSITORY_ROOT / "tooling" / "question_bank"))

from ai_governance import (  # noqa: E402
    candidate_fingerprint,
    promote_ai_governed_candidates,
)
from expansion import validate_expansion_batch  # noqa: E402

BANK = REPOSITORY_ROOT / "question_banks" / "eisei1"
AUTHORING = BANK / "authoring"
BATCH = AUTHORING / "batches" / "batch_004"
ACCEPTED = ("E1-B4-LH-C002", "E1-B4-LH-C004")
REWORK = ("E1-B4-LH-C001", "E1-B4-LH-C003")
ACTORS = {
    "author": {"id": "eisei1-b4-author-r1", "role": "AI_AUTHOR"},
    "reviewer": {
        "id": "eisei1-b4-independent-reviewer-r1",
        "role": "AI_REVIEWER",
    },
    "director": {"id": "eisei1-b4-director-r1", "role": "AI_DIRECTOR"},
}
DIRECTOR_RATIONALE = (
    "Independent Director check: each accepted candidate remains bound to its "
    "current primary-rule locator, has exactly one best answer under its stated "
    "worker/procedure condition, and has a materially distinct reasoning path. "
    "The released bank, canonical drafts, and full B4 batch collision evidence "
    "was checked. C001 remains excluded for stem-condition ambiguity and C003 "
    "remains excluded for collision/variation failure; neither may receive an "
    "acceptance packet or promotion in this transition."
)


def read_rows() -> tuple[list[str], dict[str, dict[str, str]]]:
    with (BATCH / "candidates.csv").open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        return list(reader.fieldnames or []), {row["candidate_id"]: row for row in reader}


def main() -> None:
    fields, rows = read_rows()
    if not fields or set(rows) != set(ACCEPTED + REWORK):
        raise SystemExit("unexpected Eisei1 B4 candidate set")
    if len({actor["id"] for actor in ACTORS.values()}) != 3:
        raise SystemExit("AI actor identities must be pairwise distinct")
    if any(row["state"] != "AI_PRE_ACCEPT" or row["permanent_question_id"] for row in rows.values()):
        raise SystemExit("Eisei1 B4 candidate state or permanent-ID drift")

    review = json.loads((BATCH / "independent_review_r1.json").read_text(encoding="utf-8"))
    decisions = {item["candidate_id"]: item for item in review["decisions"]}
    if (
        review.get("summary") != {"reviewed": 4, "accept": 2, "reject": 0, "rework": 2, "hold": 0}
        or review.get("identity_separation") != "PASS"
        or review.get("author_identity_checked") != ACTORS["author"]["id"]
        or review.get("reviewer") != ACTORS["reviewer"]
        or set(decisions) != set(rows)
        or any(decisions[candidate_id]["decision"] != "ACCEPT" for candidate_id in ACCEPTED)
        or any(decisions[candidate_id]["decision"] != "REWORK" for candidate_id in REWORK)
    ):
        raise SystemExit("authoritative B4 independent-review decision drift")

    packets = BATCH / "acceptance_packets"
    packets.mkdir(exist_ok=True)
    if {path.stem for path in packets.glob("*.json")}:
        raise SystemExit("partial Eisei1 B4 packet state detected")

    for candidate_id in ACCEPTED:
        candidate = rows[candidate_id]
        packet = {
            "schema_version": "1.0",
            "candidate_id": candidate_id,
            "candidate_state": "AI_PRE_ACCEPT",
            "candidate_fingerprint": candidate_fingerprint(candidate),
            "actors": ACTORS,
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
                "rationale": decisions[candidate_id]["rationale"],
            },
            "director_adjudication": {
                "decision": "ACCEPT",
                "rationale": DIRECTOR_RATIONALE,
            },
            "requested_state": "AI_GOVERNED_ACCEPT",
        }
        (packets / f"{candidate_id}.json").write_text(
            json.dumps(packet, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

    promote_ai_governed_candidates(BATCH, ACCEPTED)
    _, after = read_rows()
    if any(after[candidate_id]["state"] != "READY_FOR_ID" or after[candidate_id]["permanent_question_id"] for candidate_id in ACCEPTED):
        raise SystemExit("accepted B4 candidates did not reach READY_FOR_ID")
    if any(after[candidate_id]["state"] != "AI_PRE_ACCEPT" or after[candidate_id]["permanent_question_id"] for candidate_id in REWORK):
        raise SystemExit("REWORK B4 candidates must remain AI_PRE_ACCEPT without IDs")
    if {path.stem for path in packets.glob("*.json")} != set(ACCEPTED):
        raise SystemExit("B4 acceptance packet set drift")
    errors = validate_expansion_batch(BATCH)
    if errors:
        raise SystemExit("B4 expansion validation failed: " + " | ".join(errors))


if __name__ == "__main__":
    main()
