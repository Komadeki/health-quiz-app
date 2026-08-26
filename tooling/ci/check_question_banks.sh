#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPOSITORY_ROOT"

python3 -m unittest discover \
  -s tooling/question_bank/tests \
  -p 'test_*.py'

if [[ -n "${BASE_SHA:-}" && -n "${HEAD_SHA:-}" ]]; then
  mapfile -t changed_paths < <(git diff --name-only "$BASE_SHA" "$HEAD_SHA")
else
  mapfile -t changed_paths < <(git diff --name-only HEAD^ HEAD)
fi

declare -A selected_banks=()
otsu4_state_changed=false
for path in "${changed_paths[@]}"; do
  if [[ "$path" == "tooling/komadeki_autopilot/otsu4_state.json" ]]; then
    selected_banks[otsu4]=1
    otsu4_state_changed=true
    continue
  fi

  if [[ "$path" =~ ^question_banks/([^/]+)/ ]]; then
    app_key="${BASH_REMATCH[1]}"
    if [[ -f "question_banks/$app_key/authoring/bank.json" ]]; then
      selected_banks["$app_key"]=1
    fi
  fi
done

if [[ ${#selected_banks[@]} -eq 0 ]]; then
  echo "No changed qualification bank was resolved; validating all discovered banks fail-safe."
  for bank in question_banks/*; do
    if [[ -f "$bank/authoring/bank.json" ]]; then
      selected_banks["$(basename "$bank")"]=1
    fi
  done
fi

if [[ "$otsu4_state_changed" == true || -n "${selected_banks[otsu4]+x}" ]]; then
  if [[ -f tooling/komadeki_autopilot/otsu4_state.json ]]; then
    python3 tooling/komadeki_autopilot/validate_state.py \
      tooling/komadeki_autopilot/otsu4_state.json
  fi
fi

for app_key in $(printf '%s\n' "${!selected_banks[@]}" | sort); do
  bank_root="question_banks/$app_key"
  echo "Validating Question Bank: $app_key"
  python3 tooling/question_bank/validate.py \
    --bank "$bank_root" \
    --check-generated

  batch_root="$bank_root/authoring/batches"
  if [[ -d "$batch_root" ]]; then
    APP_KEY="$app_key" BATCH_ROOT="$batch_root" python3 - <<'PY'
from pathlib import Path
import os
import sys

sys.path.insert(0, "tooling/question_bank")
from expansion import validate_expansion_batch

app_key = os.environ["APP_KEY"]
root = Path(os.environ["BATCH_ROOT"])
failures: list[str] = []
validated = 0
for batch in sorted(root.iterdir()):
    if not batch.is_dir() or not (batch / "batch.json").is_file():
        continue
    validated += 1
    errors = validate_expansion_batch(batch)
    failures.extend(f"{app_key}/{batch.name}: {error}" for error in errors)
if failures:
    raise SystemExit(
        "Question Bank expansion validation failed:\n" + "\n".join(failures)
    )
print(f"{app_key}: expansion validation passed for {validated} batch(es).")
PY
  fi
done

if [[ -n "${BASE_SHA:-}" && -n "${HEAD_SHA:-}" ]]; then
  git diff --check "$BASE_SHA" "$HEAD_SHA"
else
  git diff --check HEAD^ HEAD
fi
