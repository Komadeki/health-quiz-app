#!/usr/bin/env bash
set -euo pipefail

python3 tooling/komadeki_autopilot/validate_state.py \
  tooling/komadeki_autopilot/otsu4_state.json

python3 -m unittest discover \
  -s tooling/question_bank/tests \
  -p 'test_*.py'

python3 tooling/question_bank/validate.py \
  --bank question_banks/otsu4 \
  --check-generated

python3 tooling/question_bank/playbook_audit.py \
  --bank question_banks/otsu4 \
  --profile question_banks/otsu4/authoring/validated_batch_playbook_profile_v1.json

python3 - <<'PY'
from pathlib import Path
import sys

sys.path.insert(0, "tooling/question_bank")
from expansion import validate_expansion_batch

root = Path("question_banks/otsu4/authoring/batches")
failures: list[str] = []
for batch in sorted(root.glob("batch_*")):
    errors = validate_expansion_batch(batch)
    failures.extend(f"{batch.name}: {error}" for error in errors)
if failures:
    raise SystemExit("Otsu4 expansion validation failed:\n" + "\n".join(failures))
print("Otsu4 expansion validation passed for all batches.")
PY

for batch in question_banks/otsu4/authoring/batches/batch_*; do
  python3 tooling/question_bank/validate_playbook_batch.py \
    --batch "$batch" \
    --profile question_banks/otsu4/authoring/validated_batch_playbook_profile_v1.json
done

git diff --check
