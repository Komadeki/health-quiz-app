#!/usr/bin/env python3
"""Validate the durable KOMADEKI UI/UX Autopilot machine state."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

PHASES = (
    "BASELINE_AUDIT",
    "STANDARD_UX_CONTRACT",
    "CORE_UX_IMPROVEMENT",
    "DRONE_SPECIFIC_UX",
    "ACCESSIBILITY_RESPONSIVE",
    "PRODUCT_UX_CLOSURE",
    "PHYSICAL_UX",
    "DONE",
)
STATUSES = {"ACTIVE", "HUMAN_BLOCKED", "DONE"}
REQUIRED_KEYS = {
    "schema_version",
    "project",
    "workstream",
    "control_issue",
    "status",
    "current_phase",
    "phase_order",
    "observed_main",
    "next_atomic_objective",
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
        fail(
            "state keys mismatch; "
            f"missing={sorted(REQUIRED_KEYS - keys)}, extra={sorted(keys - REQUIRED_KEYS)}"
        )
    if state["schema_version"] != "1.0":
        fail("unsupported schema_version")
    if not isinstance(state["project"], str) or not state["project"]:
        fail("project must be a non-empty string")
    if state["workstream"] != "qualification_factory_ui_ux":
        fail("unexpected workstream")
    if not isinstance(state["control_issue"], int) or state["control_issue"] < 1:
        fail("control_issue must be a positive integer")
    if state["status"] not in STATUSES:
        fail("invalid status")
    if state["current_phase"] not in PHASES:
        fail("invalid current_phase")
    if tuple(state["phase_order"]) != PHASES:
        fail("phase_order must match the canonical UI/UX state machine")
    if (
        not isinstance(state["observed_main"], str)
        or re.fullmatch(r"[0-9a-f]{40}", state["observed_main"]) is None
    ):
        fail("observed_main must be a 40-character lowercase SHA")
    if not isinstance(state["next_atomic_objective"], str):
        fail("next_atomic_objective must be a string")
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


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: validate_ui_ux_state.py <state.json>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        if not isinstance(data, dict):
            fail("top-level state must be an object")
        validate(data)
    except (OSError, json.JSONDecodeError, ValueError) as exc:
        print(f"KOMADEKI UI/UX Autopilot state invalid: {exc}", file=sys.stderr)
        return 1
    print(
        "KOMADEKI UI/UX Autopilot state valid: "
        f"phase={data['current_phase']} status={data['status']} epoch={data['state_epoch']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
