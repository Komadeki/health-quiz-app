#!/usr/bin/env python3
"""Integrate one fully reviewed Eisei1 density batch transactionally."""

from __future__ import annotations

import argparse
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


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--batch", required=True, type=Path)
    parser.add_argument("--verified-at", required=True)
    args = parser.parse_args()

    bank = REPO / "question_banks" / "eisei1"
    authoring = bank / "authoring"
    batch = args.batch.resolve()
    candidates = read_csv(batch / "candidates.csv")
    selected = tuple(row["candidate_id"] for row in candidates)
    if not selected or len(selected) > 10 or len(selected) != len(set(selected)):
        raise SystemExit("batch must contain one to ten unique candidates")
    if any(row["state"] != "AI_PRE_ACCEPT" or row["permanent_question_id"] for row in candidates):
        raise SystemExit("all candidates must be unallocated AI_PRE_ACCEPT rows")
    if errors := validate_expansion_batch(batch):
        raise SystemExit("pre-transition validation failed: " + " | ".join(errors))

    review = json.loads((batch / "independent_review_r1.json").read_text(encoding="utf-8"))
    decisions = {row["candidate_id"]: row for row in review.get("decisions", [])}
    if review.get("identity_separation") != "PASS" or set(decisions) != set(selected):
        raise SystemExit("independent review evidence is incomplete")
    if any(decisions[candidate_id].get("decision") != "ACCEPT" for candidate_id in selected):
        raise SystemExit("all selected candidates must be accepted")

    metadata = json.loads((batch / "batch.json").read_text(encoding="utf-8"))
    author_id = metadata["author"]["id"]
    reviewer_id = review["reviewer"]["id"]
    packet_dir = batch / "acceptance_packets"
    packet_dir.mkdir(exist_ok=False)
    for candidate in candidates:
        candidate_id = candidate["candidate_id"]
        packet = {
            "schema_version": "1.0",
            "candidate_id": candidate_id,
            "candidate_state": "AI_PRE_ACCEPT",
            "candidate_fingerprint": candidate_fingerprint(candidate),
            "actors": {
                "author": {"id": author_id, "role": "AI_AUTHOR"},
                "reviewer": {"id": reviewer_id, "role": "AI_REVIEWER"},
                "director": {"id": "eisei1-density-director-r1", "role": "AI_DIRECTOR"},
            },
            "evidence": {
                "source": {key: candidate[key] for key in ("source_id", "source_version", "source_locator")},
                "answer_defining_proposition": candidate["answer_defining_proposition"],
                "tested_misconception": candidate["tested_misconception"],
                "reasoning_path": candidate["reasoning_path"],
                "collision": {"released_bank_checked": True, "canonical_drafts_checked": True, "batch_checked": True, "note": candidate["collision_note"]},
            },
            "independent_review": {"decision": "ACCEPT", "rationale": decisions[candidate_id]["rationale"]},
            "director_adjudication": {"decision": "ACCEPT", "rationale": "Independent review is adopted after source, choice, and global-collision checks."},
            "requested_state": "AI_GOVERNED_ACCEPT",
        }
        (packet_dir / f"{candidate_id}.json").write_text(json.dumps(packet, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    promote_ai_governed_candidates(batch, selected)

    transaction = QuestionExpansionTransaction(bank, batch, selected, question_factory=canonical_row)
    mapping = transaction.plan().mapping
    if transaction.apply() != mapping:
        raise SystemExit("integration mapping drift")

    source_records = {row["source_id"]: row for row in json.loads((authoring / "sources.json").read_text(encoding="utf-8"))["sources"]}
    verifications_path = authoring / "source_verifications.json"
    verifications = json.loads(verifications_path.read_text(encoding="utf-8"))
    coverage_path = authoring / "coverage.json"
    coverage = json.loads(coverage_path.read_text(encoding="utf-8"))
    for candidate in candidates:
        source = source_records.get(candidate["source_id"])
        if source is None or source["source_version"] != candidate["source_version"]:
            raise SystemExit(f"source-version drift: {candidate['candidate_id']}")
        question_id = mapping[candidate["candidate_id"]]
        verifications["verifications"].append({"question_id": question_id, "source_id": candidate["source_id"], "source_version": candidate["source_version"], "verification_state": "author_source_verified", "verified_at": args.verified_at})
        coverage["question_bindings"].append({"knowledge_target_id": candidate["knowledge_target_id"], "question_id": question_id, "variation_tags": []})
    verifications_path.write_text(json.dumps(verifications, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    coverage_path.write_text(json.dumps(coverage, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if errors := validate_expansion_batch(batch):
        raise SystemExit("post-transition validation failed: " + " | ".join(errors))


if __name__ == "__main__":
    main()
