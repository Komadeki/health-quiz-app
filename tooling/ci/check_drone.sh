#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$REPOSITORY_ROOT"
python3 apps/drone_second_class/tool/sync_validation_assets.py --check

cd "$REPOSITORY_ROOT/apps/drone_second_class"
flutter pub get
flutter analyze
flutter test
