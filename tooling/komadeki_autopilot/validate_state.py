#!/usr/bin/env python3
"""Validate the durable KOMADEKI autopilot machine state using stdlib only."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

PHASES = (
    "QUESTION_BANK_COMPLETION",
    "FEATURE_COMPLETION",
    "PRODUCT_CLOSURE",
    "PHYSICAL_DEVICE",
    "STOREKIT_TESTFLIGHT",
    "APP_STORE_CONNECT",
    "FINAL_RELEASE_GATE",
    "SUBMIT",
    "DONE",
)
STATUSES = {"ACTIVE", "HUMAN_BLOCKED", "DONE"}
ACCEPTANCE_MODES = {"MIGRATION_REQUIRED", "AI_GOVERNED", "HUMAN_REQUIRED"}
REQUIRED_KEYS = {
    "schema_version",
    "project",
    "product",
    "control_issue",
    "status",
    "current_phase",
    "phase_order",
    "observed_main",
    "next_atomic_objective",
    "autonomous_acceptance",
    "review_identity_policy",
    "local_only_state_authoritative",
    "repository_completion_rule",
    "human_blocker",
    "state_epoch",
}


def fail(message: str) -> None:
    raise ValueError(message)


def validate(state: dict[str, object]) -> None:
    keys = set(state)
    if keys != REQUIRED_KEYS:
        missing = sorted(REQUIRED_KEYS - keys)
        extra = sorted(keys - REQUIRED_KEYS)
        fail(f"state keys mismatch; missing={missing}, extra={extra}")

    if state["schema_version"] != "1.0":
        fail("unsupported schema_version")
    if not isinstance(state["project"], str) or not state["project"]:
        fail("project must be a non-empty string")
    if not isinstance(state["product"], str) or not state["product"]:
        fail("product must be a non-empty string")
    if not isinstance(state["control_issue"], int) or state["control_issue"] < 1:
        fail("control_issue must be a positive integer")
    if state["status"] not in STATUSES:
        fail("invalid status")
    if state["current_phase"] not in PHASES:
        fail("invalid current_phase")
    if tuple(state["phase_order"]) != PHASES:
        fail("phase_order must match the canonical state machine")
    if not isinstance(state["observed_main"], str) or re.fullmatch(r"[0-9a-f]{40}", state["observed_main"]) is None:
        fail("observed_main must be a 40-character lowercase SHA")
    if not isinstance(state["next_atomic_objective"], str):
        fail("next_atomic_objective must be a string")
    if state["autonomous_acceptance"] not in ACCEPTANCE_MODES:
        fail("invalid autonomous_acceptance mode")
    if state["review_identity_policy"] != "NEVER_FABRICATE_HUMAN":
        fail("review identity policy must forbid fabricated human review")
    if state["local_only_state_authoritative"] is not False:
        fail("local-only state must never be authoritative")
    if state["repository_completion_rule"] != "DURABLE_GITHUB_EVIDENCE_REQUIRED":
        fail("repository completion must require durable GitHub evidence")
    if not isinstance(state["state_epoch"], int) or state["state_epoch"] < 1:
        fail("state_epoch must be a positive integer")

    status = state["status"]
    phase = state["current_phase"]
    blocker = state["human_blocker"]
    objective = state["next_atomic_objective"]

    if status == "ACTIVE":
        if phase == "DONE":
            fail("ACTIVE state cannot be in DONE phase")
        if blocker is not None:
            fail("ACTIVE state cannot carry a human blocker")
        if not objective:
            fail("ACTIVE state requires a next_atomic_objective")
    elif status == "HUMAN_BLOCKED":
        if not isinstance(blocker, dict):
            fail("HUMAN_BLOCKED requires a blocker object")
        if set(blocker) != {"action", "resume_evidence"}:
            fail("human_blocker must contain action and resume_evidence only")
        if not all(isinstance(blocker[key], str) and blocker[key] for key in blocker):
            fail("human blocker fields must be non-empty strings")
    elif status == "DONE":
        if phase != "DONE":
            fail("DONE status requires DONE phase")
        if objective:
            fail("DONE state must not have a next objective")
        if blocker is not None:
            fail("DONE state must not have a human blocker")


def validate_repository_owner_guard(state: dict[str, object], state_path: Path) -> None:
    """Apply repository-only owner-direction guard to the authoritative Drone state.

    Unit tests and validation of temporary state files retain the generic state-machine
    contract above. This extra guard applies only when the actual repository
    `drone_state.json` is the file being validated.
    """

    expected_state_path = Path(__file__).resolve().parent / "drone_state.json"
    if state_path.resolve() != expected_state_path.resolve():
        return
    if state.get("product") != "drone_second_class":
        return

    repository_root = Path(__file__).resolve().parents[2]
    guard_path = Path(__file__).resolve().parent / "drone_owner_direction_guard.json"
    if not guard_path.is_file():
        return

    guard = json.loads(guard_path.read_text(encoding="utf-8"))
    if not isinstance(guard, dict):
        fail("Drone owner-direction guard must be an object")
    if guard.get("status") != "ACTIVE":
        return
    if guard.get("schema_version") != "1.0" or guard.get("product") != "drone_second_class":
        fail("invalid Drone owner-direction guard identity")

    minimum_epoch = guard.get("minimum_state_epoch")
    if not isinstance(minimum_epoch, int) or minimum_epoch < 1:
        fail("Drone owner-direction guard has invalid minimum_state_epoch")
    if int(state["state_epoch"]) < minimum_epoch:
        fail("Drone state epoch predates the active owner-direction guard")

    policy_rel = guard.get("authoritative_decision_path")
    decision_id = guard.get("authoritative_decision_id")
    if not isinstance(policy_rel, str) or not policy_rel or not isinstance(decision_id, str) or not decision_id:
        fail("Drone owner-direction guard is missing authoritative policy identity")
    policy_path = repository_root / policy_rel
    policy = json.loads(policy_path.read_text(encoding="utf-8"))
    if policy.get("decision_id") != decision_id or policy.get("status") != "ACTIVE":
        fail("Drone authoritative owner decision is not active")

    for relative_path in guard.get("forbidden_active_contract_paths", []):
        if not isinstance(relative_path, str) or not relative_path:
            fail("Drone owner-direction guard has invalid forbidden contract path")
        path = repository_root / relative_path
        if not path.is_file():
            continue
        contract = json.loads(path.read_text(encoding="utf-8"))
        if contract.get("status") == "ACTIVE":
            fail(f"forbidden superseded Drone contract is active: {relative_path}")

    if state.get("current_phase") == "QUESTION_BANK_COMPLETION":
        allowed = guard.get("question_bank_completion_allowed_objectives")
        if not isinstance(allowed, list) or not allowed or not all(isinstance(x, str) and x for x in allowed):
            fail("Drone owner-direction guard has invalid allowed objectives")
        if state.get("next_atomic_objective") not in allowed:
            fail(
                "Drone QUESTION_BANK_COMPLETION objective conflicts with active owner-direction guard: "
                f"{state.get('next_atomic_objective')}"
            )


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_state.py <state.json>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            fail("top-level state must be an object")
        validate(data)
        validate_repository_owner_guard(data, path)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"KOMADEKI autopilot state invalid: {exc}", file=sys.stderr)
        return 1
    print(
        "KOMADEKI autopilot state valid: "
        f"phase={data['current_phase']} status={data['status']} epoch={data['state_epoch']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
