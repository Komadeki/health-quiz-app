#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 2 ]]; then
  echo "Usage: $0 BASE_SHA HEAD_SHA" >&2
  exit 2
fi

readonly BASE_SHA="$1"
readonly HEAD_SHA="$2"
readonly DEFAULT_REPOSITORY_ROOT="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
)"
readonly REPOSITORY_ROOT="${REPOSITORY_ROOT_OVERRIDE:-$DEFAULT_REPOSITORY_ROOT}"
readonly HEALTH_PATH_PREFIX="apps/health/"
readonly DIFF_FILE="$(mktemp "${TMPDIR:-/tmp}/changed-health-dart.XXXXXX")"

cleanup() {
  rm -f "$DIFF_FILE"
}
trap cleanup EXIT

for revision in "$BASE_SHA" "$HEAD_SHA"; do
  if ! git -C "$REPOSITORY_ROOT" cat-file -e "${revision}^{commit}"; then
    echo "Revision is not available as a commit: $revision" >&2
    exit 1
  fi
done

git -C "$REPOSITORY_ROOT" diff \
  --name-status -z -M "$BASE_SHA" "$HEAD_SHA" > "$DIFF_FILE"

is_health_dart() {
  local path="$1"
  [[ "$path" == "${HEALTH_PATH_PREFIX}"*.dart ]]
}

strict_files=()
skipped_pure_renames=0

while IFS= read -r -d '' status; do
  case "$status" in
    R*)
      IFS= read -r -d '' source_path
      IFS= read -r -d '' destination_path
      if ! is_health_dart "$destination_path"; then
        continue
      fi
      if [[ "$status" == "R100" ]]; then
        skipped_pure_renames=$((skipped_pure_renames + 1))
      else
        strict_files+=("$destination_path")
      fi
      ;;
    A|M)
      IFS= read -r -d '' path
      if is_health_dart "$path"; then
        strict_files+=("$path")
      fi
      ;;
    *)
      # Deleted and non-Dart paths do not have a file to analyze.
      IFS= read -r -d '' _path
      ;;
  esac
done < "$DIFF_FILE"

echo "Skipped $skipped_pure_renames pure R100 health Dart rename(s)."

if [[ "${#strict_files[@]}" -eq 0 ]]; then
  echo "No added or content-changed health Dart files to analyze."
  exit 0
fi

cd "$REPOSITORY_ROOT/apps/health"
for path in "${strict_files[@]}"; do
  echo "Strictly analyzing changed health Dart file: $path"
  dart analyze --fatal-infos "${path#${HEALTH_PATH_PREFIX}}"
done
