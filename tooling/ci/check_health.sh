#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$REPOSITORY_ROOT/apps/health"
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test test/compatibility
flutter test
