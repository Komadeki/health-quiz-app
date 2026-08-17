#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$REPOSITORY_ROOT/tooling/app_manifest"
dart pub get
dart run bin/validate.dart \
  --repository-root "$REPOSITORY_ROOT" \
  --check-generated
dart run bin/generate.dart --repository-root "$REPOSITORY_ROOT" --check
