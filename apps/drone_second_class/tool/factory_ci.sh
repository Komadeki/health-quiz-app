#!/usr/bin/env bash
set -euo pipefail

readonly APP_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT="$(cd "$APP_DIRECTORY/../.." && pwd)"

cd "$REPOSITORY_ROOT"
python3 apps/drone_second_class/tool/sync_validation_assets.py --check
