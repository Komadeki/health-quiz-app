from __future__ import annotations

import csv
import hashlib
import json
import os
import sys
import tempfile
from pathlib import Path
from typing import Iterable

_AUTOPILOT_DIR = Path(__file__).resolve().parents[1] / "komadeki_autopilot"
if str(_AUTOPILOT_DIR) not in sys.path:
    sys.path.insert(0, str(_AUTOPILOT_DIR))

from question_acceptance import accepted, validate_packet  # noqa: E402


class AIGovernanceError(RuntimeError):
    pass


CONTENT_BINDING_FIELDS = (
    "candidate_id",
    "unit_id",
    "domain",
    "knowledge_target_id",
    "family",
    "question",
    "choice1",
    "choice2",
    "choice3",
    "choice4",
    "choice5",
    "proposed_correct",
    "explanation",
    "source_id",
    "source_version",
    "source_locator",
    "answer_defining_proposition",
    "tested_misconception",
    "reasoning_path",
    "collision_note",
)


def packet_path(batch_dir: Path | str, candidate_id: str) -> Path:
    return Path(batch_dir) / "acceptance_packets" / f"{candidate_id}.json"


def candidate_fingerprint(candidate: dict[str, str]) -> str:
    # Historical packets were fingerprinted before choice5 existed.  Omit the
    # additive field when reading one of those legacy CSV rows, but bind it for
    # every newly authored row that declares the column.
    payload = {
        field: candidate.get(field, "")
        for field in CONTENT_BINDING_FIELDS
        if field != "choice5" or field in candidate
    }
    canonical = json.dumps(
        payload,
        ensure_ascii=False,
        sort_keys=True,
        separators=(",", ":"),
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def ai_acceptance_errors(batch_dir: Path | str, candidate: dict[str, str]) -> list[str]:
    path = packet_path(batch_dir, candidate.get("candidate_id", ""))
    if not path.is_file():
        return [f"missing AI-governed acceptance packet: {path.name}"]
    try:
        packet = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"invalid AI-governed acceptance packet: {exc}"]
    if not isinstance(packet, dict):
        return ["AI-governed acceptance packet root must be an object"]

    errors = [f"packet: {error}" for error in validate_packet(packet)]
    if str(packet.get("candidate_id", "")).strip() != candidate.get("candidate_id", ""):
        errors.append("packet candidate_id does not match candidate row")
    if str(packet.get("candidate_fingerprint", "")).strip() != candidate_fingerprint(candidate):
        errors.append("packet candidate_fingerprint does not match candidate content")

    evidence = packet.get("evidence") if isinstance(packet.get("evidence"), dict) else {}
    source = evidence.get("source") if isinstance(evidence.get("source"), dict) else {}
    for field in ("source_id", "source_version", "source_locator"):
        if str(source.get(field, "")).strip() != candidate.get(field, ""):
            errors.append(f"packet source evidence mismatch: {field}")
    for field in ("answer_defining_proposition", "tested_misconception", "reasoning_path"):
        if str(evidence.get(field, "")).strip() != candidate.get(field, ""):
            errors.append(f"packet evidence mismatch: {field}")
    collision = evidence.get("collision") if isinstance(evidence.get("collision"), dict) else {}
    if str(collision.get("note", "")).strip() != candidate.get("collision_note", ""):
        errors.append("packet evidence mismatch: collision_note")
    if not accepted(packet):
        errors.append("packet is not AI_GOVERNED_ACCEPT")
    return errors


def has_valid_ai_acceptance(batch_dir: Path | str, candidate: dict[str, str]) -> bool:
    return not ai_acceptance_errors(batch_dir, candidate)


def promote_ai_governed_candidates(
    batch_dir: Path | str, candidate_ids: Iterable[str]
) -> tuple[str, ...]:
    batch_dir = Path(batch_dir)
    candidate_ids = tuple(candidate_ids)
    if not candidate_ids or len(candidate_ids) != len(set(candidate_ids)):
        raise AIGovernanceError("candidate_ids must be a non-empty unique set")

    path = batch_dir / "candidates.csv"
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        fields = list(reader.fieldnames or [])
        rows = list(reader)

    wanted = set(candidate_ids)
    selected = [row for row in rows if row.get("candidate_id") in wanted]
    if len(selected) != len(wanted):
        raise AIGovernanceError("candidate set is incomplete")

    failures: list[str] = []
    for row in selected:
        candidate_id = row.get("candidate_id", "")
        if row.get("state") != "AI_PRE_ACCEPT":
            failures.append(f"{candidate_id}: state must be AI_PRE_ACCEPT")
        if row.get("permanent_question_id"):
            failures.append(f"{candidate_id}: permanent_question_id must be blank")
        failures.extend(
            f"{candidate_id}: {error}" for error in ai_acceptance_errors(batch_dir, row)
        )
    if failures:
        raise AIGovernanceError("; ".join(failures))

    updated: list[dict[str, str]] = []
    for row in rows:
        row = dict(row)
        if row.get("candidate_id") in wanted:
            row["state"] = "READY_FOR_ID"
        updated.append(row)

    fd, temp_name = tempfile.mkstemp(prefix=".candidates-", suffix=".csv", dir=batch_dir)
    try:
        with os.fdopen(fd, "w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
            writer.writeheader()
            writer.writerows(updated)
        os.replace(temp_name, path)
    except Exception:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
        raise
    return candidate_ids
