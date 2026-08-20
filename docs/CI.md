# CI contract

## Local entry points

Run every check from the repository root with:

```bash
tooling/ci/check_all.sh
```

Focused entry points are `check_shared.sh`, `check_manifest.sh`,
`check_health.sh`, `check_fixture.sh`, and `check_drone.sh` in `tooling/ci/`.

## Pull-request scope

The primary workflow first classifies every changed path.

| Change | Checks |
| --- | --- |
| `packages/**`, `tooling/**`, `question_banks/**`, `.github/**`, shared root config | shared + health + fixture + drone |
| `apps/health/**` only | health + repository manifest validation |
| `apps/_single_unlock_fixture/**` only | fixture + repository manifest validation |
| `apps/drone_second_class/**` only | drone V0 Panel + repository manifest validation |
| documentation only | scope report + final gate |
| unknown path | shared + health + fixture + drone |

Mixed app changes run every affected app job. An empty or unclassified
change list is unknown and therefore runs all checks. The always-running
`ci-gate` accepts only successful required jobs or intentionally skipped jobs.

`shared-checks` covers strict `quiz_engine` and app-manifest analysis/tests,
manifest/native/asset/generated drift, question-bank tests and generated drift,
CI scope tests, and dependency boundaries. App jobs retain health's existing
non-fatal lint policy and the fixture/drone apps' strict analysis policy. The
drone job also checks that all three validation-only assets are byte-identical
to the bank-side V0P-1 artifacts.

## iOS smoke

`.github/workflows/quiz-apps-ios-smoke.yml` runs on manual dispatch, a daily
schedule, and `quiz-apps-v*` tags. A macOS matrix runs
`flutter build ios --no-codesign` for `apps/health`,
`apps/_single_unlock_fixture`, and `apps/drone_second_class`. It performs no
signing, upload, archive delivery, or App Store action.
