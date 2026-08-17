#!/usr/bin/env bash
set -euo pipefail

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/check_shared.sh"
"$SCRIPT_DIR/check_health.sh"
"$SCRIPT_DIR/check_fixture.sh"
