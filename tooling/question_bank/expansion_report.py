#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path

from expansion import build_status_report, validate_expansion_batch


def main() -> int:
    parser = argparse.ArgumentParser(description="Report status for a pre-ID expansion batch.")
    parser.add_argument("--batch", required=True, type=Path)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    validation_errors = validate_expansion_batch(args.batch)
    report = build_status_report(args.batch)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(f"batch_id={report['batch_id']}")
        print(f"batch_status={report['batch_status']}")
        print(f"current_target_decision_status={report['current_target_decision_status']}")
        print(f"current_target_decision={json.dumps(report['current_target_decision'], ensure_ascii=False, sort_keys=True)}")
        print(f"count_by_candidate_state={json.dumps(report['count_by_candidate_state'], ensure_ascii=False, sort_keys=True)}")
        print(f"human_accept_count={report['human_accept_count']}")
        print(f"reject_count={report['reject_count']}")
        print(f"hold_count={report['hold_count']}")
        print(f"ready_for_id_count={report['ready_for_id_count']}")
        print(f"id_allocated_count={report['id_allocated_count']}")
        print(f"integrated_count={report['integrated_count']}")
        print(f"verified_count={report['verified_count']}")
        print(f"released_count={report['released_count']}")
        print(f"blockers={json.dumps(report['blockers'], ensure_ascii=False)}")
        print(f"next_actionable_states={json.dumps(report['next_actionable_states'])}")
    return 1 if validation_errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
