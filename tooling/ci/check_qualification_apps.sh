#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
app_count=0

for manifest in "$REPOSITORY_ROOT"/apps/*/app.yaml; do
  if ! awk '/^factory:/{found=1} END{exit !found}' "$manifest"; then
    continue
  fi
  app_directory="$(dirname "$manifest")"
  app_count=$((app_count + 1))
  if [[ -x "$app_directory/tool/factory_ci.sh" ]]; then
    "$app_directory/tool/factory_ci.sh"
  fi
  (
    cd "$app_directory"
    flutter pub get
    flutter analyze
    flutter test
  )
done

if [[ "$app_count" -eq 0 ]]; then
  echo "No Factory qualification apps were discovered." >&2
  exit 1
fi

echo "Validated $app_count Factory qualification app(s)."
