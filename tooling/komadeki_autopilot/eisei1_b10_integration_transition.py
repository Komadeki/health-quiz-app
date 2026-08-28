#!/usr/bin/env python3
"""Promote, allocate, and source-bind the reviewed Eisei1 B10 candidates."""

from __future__ import annotations

import csv
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "tooling" / "question_bank"))

from ai_governance import candidate_fingerprint, promote_ai_governed_candidates
from eisei1_ready_for_id_integration_transition import canonical_row
from expansion import validate_expansion_batch
from transaction import QuestionExpansionTransaction

BANK = REPO / "question_banks" / "eisei1"
AUTHORING = BANK / "authoring"
BATCH = AUTHORING / "batches" / "batch_010"
AUTHOR = "eisei1-b10-author-r1"
REVIEWER = "eisei1-b10-independent-reviewer-r1"
DIRECTOR = "eisei1-b10-director-r1"
SELECTED = (
    "E1-B10-LH-C001", "E1-B10-LH-C002", "E1-B10-LH-C003",
    "E1-B10-LH-C004", "E1-B10-HH-C001", "E1-B10-HH-C002",
)
EXPECTED = {
    "E1-B10-HH-C001": "EISEI1-Q-000017",
    "E1-B10-HH-C002": "EISEI1-Q-000018",
    "E1-B10-LH-C001": "EISEI1-Q-000019",
    "E1-B10-LH-C002": "EISEI1-Q-000020",
    "E1-B10-LH-C003": "EISEI1-Q-000021",
    "E1-B10-LH-C004": "EISEI1-Q-000022",
}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, fields: list[str], rows: list[dict[str, str]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def promote() -> None:
    candidates = read_csv(BATCH / "candidates.csv")
    if [row["candidate_id"] for row in candidates] != list(SELECTED):
        raise SystemExit("B10 candidate set drift")
    review = json.loads((BATCH / "independent_review_r1.json").read_text(encoding="utf-8"))
    decisions = {row["candidate_id"]: row for row in review.get("decisions", [])}
    if review.get("identity_separation") != "PASS" or set(decisions) != set(SELECTED):
        raise SystemExit("B10 review evidence drift")
    packet_dir = BATCH / "acceptance_packets"
    packet_dir.mkdir(exist_ok=True)
    if list(packet_dir.glob("*.json")):
        raise SystemExit("partial B10 acceptance packet state detected")
    for candidate in candidates:
        candidate_id = candidate["candidate_id"]
        if candidate["state"] != "AI_PRE_ACCEPT" or candidate["permanent_question_id"]:
            raise SystemExit(f"unexpected B10 pre-accept state: {candidate_id}")
        decision = decisions[candidate_id]
        if decision.get("decision") != "ACCEPT":
            raise SystemExit(f"B10 review did not accept {candidate_id}")
        packet = {
            "schema_version": "1.0",
            "candidate_id": candidate_id,
            "candidate_state": "AI_PRE_ACCEPT",
            "candidate_fingerprint": candidate_fingerprint(candidate),
            "actors": {
                "author": {"id": AUTHOR, "role": "AI_AUTHOR"},
                "reviewer": {"id": REVIEWER, "role": "AI_REVIEWER"},
                "director": {"id": DIRECTOR, "role": "AI_DIRECTOR"},
            },
            "evidence": {
                "source": {key: candidate[key] for key in ("source_id", "source_version", "source_locator")},
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
            "independent_review": {"decision": "ACCEPT", "rationale": decision["rationale"]},
            "director_adjudication": {
                "decision": "ACCEPT",
                "rationale": "The independent review is adopted after a fresh source, all-choice, and global collision check. This transition is AI-governed content acceptance only and creates no release artifact.",
            },
            "requested_state": "AI_GOVERNED_ACCEPT",
        }
        (packet_dir / f"{candidate_id}.json").write_text(
            json.dumps(packet, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    promote_ai_governed_candidates(BATCH, SELECTED)


def integrate_and_bind() -> None:
    transaction = QuestionExpansionTransaction(BANK, BATCH, SELECTED, question_factory=canonical_row)
    if transaction.plan().mapping != EXPECTED:
        raise SystemExit("B10 allocation plan drift")
    if transaction.apply() != EXPECTED:
        raise SystemExit("B10 allocation mismatch")

    sources = {row["source_id"]: row for row in json.loads((AUTHORING / "sources.json").read_text(encoding="utf-8"))["sources"]}
    candidates = {row["candidate_id"]: row for row in read_csv(BATCH / "candidates.csv")}
    verifications_path = AUTHORING / "source_verifications.json"
    verifications_data = json.loads(verifications_path.read_text(encoding="utf-8"))
    verifications = verifications_data["verifications"]
    if {row["question_id"] for row in verifications} & set(EXPECTED.values()):
        raise SystemExit("B10 source verification already present")
    coverage_path = AUTHORING / "coverage.json"
    coverage = json.loads(coverage_path.read_text(encoding="utf-8"))
    if {row["question_id"] for row in coverage["question_bindings"]} & set(EXPECTED.values()):
        raise SystemExit("B10 coverage binding already present")
    for candidate_id in SELECTED:
        candidate = candidates[candidate_id]
        question_id = EXPECTED[candidate_id]
        source = sources.get(candidate["source_id"])
        if source is None or source["source_version"] != candidate["source_version"]:
            raise SystemExit(f"B10 source version drift: {candidate_id}")
        verifications.append({
            "question_id": question_id,
            "source_id": candidate["source_id"],
            "source_version": candidate["source_version"],
            "verification_state": "author_source_verified",
            "verified_at": "2026-08-28",
        })
        coverage["question_bindings"].append({
            "knowledge_target_id": candidate["knowledge_target_id"],
            "question_id": question_id,
            "variation_tags": [],
        })
    verifications_path.write_text(json.dumps(verifications_data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    coverage_path.write_text(json.dumps(coverage, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    if validate_expansion_batch(BATCH):
        raise SystemExit("B10 validation must pass before transition")
    promote()
    integrate_and_bind()
    if errors := validate_expansion_batch(BATCH):
        raise SystemExit("B10 validation failed after transition: " + " | ".join(errors))


if __name__ == "__main__":
    main()
