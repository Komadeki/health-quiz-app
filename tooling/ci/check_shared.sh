#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

cd "$REPOSITORY_ROOT/packages/quiz_engine"
dart pub get
dart analyze --fatal-infos
dart test

cd "$REPOSITORY_ROOT/tooling/app_manifest"
dart pub get
dart analyze --fatal-infos
dart test
dart run bin/validate.dart \
  --repository-root "$REPOSITORY_ROOT" \
  --check-generated
dart run bin/generate.dart --repository-root "$REPOSITORY_ROOT" --check

cd "$REPOSITORY_ROOT"
python3 -m unittest discover \
  -s tooling/question_bank/tests \
  -p 'test_*.py'
python3 tooling/question_bank/validate.py \
  --bank question_banks/qualification_fixture \
  --check-generated
python3 tooling/question_bank/validate.py \
  --bank question_banks/drone_second_class \
  --check-generated
python3 -m unittest discover \
  -s tooling/v0_panel_validation/tests \
  -p 'test_*.py'
python3 tooling/v0_panel_validation/validate.py \
  --bank question_banks/drone_second_class \
  --check-generated
python3 -m unittest discover \
  -s tooling/ci \
  -p 'test_*.py'
tooling/ci/test_check_changed_health_dart.sh
