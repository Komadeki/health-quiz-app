# CI contract

## Local entry points

Run every check from the repository root with:

```bash
tooling/ci/check_all.sh
```

Focused entry points are `check_shared.sh`, `check_manifest.sh`,
`check_health.sh`, and `check_qualification_apps.sh` in `tooling/ci/`.

## Pull-request scope

The primary workflow first classifies every changed path.

| Change | Checks |
| --- | --- |
| `packages/**`, `tooling/**`, `question_banks/**`, `.github/**`, shared root config | shared + health + qualification apps |
| `apps/health/**` only | health + repository manifest validation |
| any other direct-child `apps/*/**` | discovered qualification apps + repository manifest validation |
| documentation only | scope report + final gate |
| unknown path | shared + health + qualification apps |

Mixed app changes run every affected app job. An empty or unclassified
change list is unknown and therefore runs all checks. The always-running
`ci-gate` accepts only successful required jobs or intentionally skipped jobs.

`shared-checks` covers strict `quiz_engine`, `qualification_app`, and
app-manifest analysis/tests,
manifest/native/asset/generated drift, question-bank tests and generated drift,
CI scope tests, and dependency boundaries. `check_qualification_apps.sh`
discovers every direct-child manifest with a `factory` profile and runs strict
analysis/tests. An optional per-app `tool/factory_ci.sh` preserves product-owned
integrity checks; Drone uses it for the historical V0 asset byte check.

## iOS smoke

`.github/workflows/quiz-apps-ios-smoke.yml` runs on manual dispatch, a daily
schedule, and `quiz-apps-v*` tags. A discovery job builds the macOS matrix from
all direct-child app manifests and runs `flutter build ios --no-codesign`. It
performs no signing, upload, archive delivery, or App Store action.
