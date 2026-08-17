#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$REPOSITORY_ROOT/apps/health"
flutter pub get

if [[ -n "${BASE_SHA:-}" || -n "${HEAD_SHA:-}" ]]; then
  if [[ -z "${BASE_SHA:-}" || -z "${HEAD_SHA:-}" ]]; then
    echo "BASE_SHA and HEAD_SHA must be provided together." >&2
    exit 2
  fi
  "$REPOSITORY_ROOT/tooling/ci/check_changed_health_dart.sh" \
    "$BASE_SHA" "$HEAD_SHA"
fi

flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test test/compatibility
flutter test
