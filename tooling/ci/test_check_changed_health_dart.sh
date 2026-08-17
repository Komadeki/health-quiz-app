#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly CHECK_SCRIPT="$REPOSITORY_ROOT/tooling/ci/check_changed_health_dart.sh"
readonly TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/changed-health-dart-test.XXXXXX")"
readonly TEST_REPOSITORY="$TEST_ROOT/repository"
readonly FAKE_BIN="$TEST_ROOT/bin"
readonly DART_LOG_FILE="$TEST_ROOT/dart.log"
readonly CHECK_OUTPUT="$TEST_ROOT/check.out"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

mkdir -p "$TEST_REPOSITORY/lib" "$TEST_REPOSITORY/apps/health/lib"
git -C "$TEST_REPOSITORY" init -q
git -C "$TEST_REPOSITORY" config user.name "CI Contract Test"
git -C "$TEST_REPOSITORY" config user.email "ci-contract@example.invalid"
git -C "$TEST_REPOSITORY" config commit.gpgsign false

for index in {1..40}; do
  printf 'const value%s = %s;\n' "$index" "$index"
done > "$TEST_REPOSITORY/lib/pure.dart"
cp "$TEST_REPOSITORY/lib/pure.dart" "$TEST_REPOSITORY/lib/changed.dart"
printf 'const existing = 1;\n' \
  > "$TEST_REPOSITORY/apps/health/lib/modified.dart"

git -C "$TEST_REPOSITORY" add .
git -C "$TEST_REPOSITORY" commit -qm "Create base files"
readonly BASE_SHA="$(git -C "$TEST_REPOSITORY" rev-parse HEAD)"

git -C "$TEST_REPOSITORY" mv \
  lib/pure.dart apps/health/lib/pure.dart
git -C "$TEST_REPOSITORY" mv \
  lib/changed.dart apps/health/lib/changed.dart
printf 'const changedMarker = true;\n' \
  >> "$TEST_REPOSITORY/apps/health/lib/changed.dart"
printf 'const modifiedMarker = true;\n' \
  >> "$TEST_REPOSITORY/apps/health/lib/modified.dart"
printf 'const added = true;\n' \
  > "$TEST_REPOSITORY/apps/health/lib/added.dart"

git -C "$TEST_REPOSITORY" add .
git -C "$TEST_REPOSITORY" commit -qm "Move and change health files"
readonly HEAD_SHA="$(git -C "$TEST_REPOSITORY" rev-parse HEAD)"
readonly NAME_STATUS="$(
  git -C "$TEST_REPOSITORY" diff --name-status -M "$BASE_SHA" "$HEAD_SHA"
)"

if [[ "$NAME_STATUS" != *$'R100\tlib/pure.dart\tapps/health/lib/pure.dart'* ]]; then
  echo "Test setup did not produce the required R100 rename." >&2
  exit 1
fi
if [[ "$NAME_STATUS" == *$'R100\tlib/changed.dart\tapps/health/lib/changed.dart'* ]] || \
   [[ "$NAME_STATUS" != *$'R0'*$'\tlib/changed.dart\tapps/health/lib/changed.dart'* ]]; then
  echo "Test setup did not produce a content-changed rename." >&2
  exit 1
fi

mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/dart" <<'FAKE_DART'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$STRICT_DART_LOG"
FAKE_DART
chmod +x "$FAKE_BIN/dart"

PATH="$FAKE_BIN:$PATH" \
  STRICT_DART_LOG="$DART_LOG_FILE" \
  REPOSITORY_ROOT_OVERRIDE="$TEST_REPOSITORY" \
  "$CHECK_SCRIPT" "$BASE_SHA" "$HEAD_SHA" > "$CHECK_OUTPUT"

grep -Fxq 'analyze' "$DART_LOG_FILE"
grep -Fxq -- '--fatal-infos' "$DART_LOG_FILE"
grep -Fxq 'lib/added.dart' "$DART_LOG_FILE"
grep -Fxq 'lib/changed.dart' "$DART_LOG_FILE"
grep -Fxq 'lib/modified.dart' "$DART_LOG_FILE"
if grep -Fxq 'lib/pure.dart' "$DART_LOG_FILE"; then
  echo "Pure R100 rename was incorrectly analyzed." >&2
  exit 1
fi
grep -Fxq 'Skipped 1 pure R100 health Dart rename(s).' "$CHECK_OUTPUT"

mkdir -p "$TEST_REPOSITORY/docs"
printf 'Documentation only.\n' > "$TEST_REPOSITORY/docs/CI.md"
git -C "$TEST_REPOSITORY" add docs/CI.md
git -C "$TEST_REPOSITORY" commit -qm "Change documentation only"
readonly DOCS_HEAD_SHA="$(git -C "$TEST_REPOSITORY" rev-parse HEAD)"

: > "$DART_LOG_FILE"
PATH="$FAKE_BIN:$PATH" \
  STRICT_DART_LOG="$DART_LOG_FILE" \
  REPOSITORY_ROOT_OVERRIDE="$TEST_REPOSITORY" \
  "$CHECK_SCRIPT" "$HEAD_SHA" "$DOCS_HEAD_SHA" > "$CHECK_OUTPUT"

if [[ -s "$DART_LOG_FILE" ]]; then
  echo "Docs-only change unexpectedly invoked Dart analyze." >&2
  exit 1
fi
grep -Fxq 'No added or content-changed health Dart files to analyze.' \
  "$CHECK_OUTPUT"

echo "Changed health Dart guard contract test passed."
