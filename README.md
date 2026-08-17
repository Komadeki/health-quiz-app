# KOMADEKI quiz apps monorepo

This repository contains independent Flutter quiz applications and the small
set of contracts and tools they intentionally share. The repository name
`health-quiz-app` is historical and may be changed in a separate operation.

## Layout

```text
apps/
  health/                    Published health Flutter app
  _single_unlock_fixture/    Non-production qualification shell fixture
packages/
  quiz_engine/               Shared models and pure quiz logic
question_banks/
  qualification_fixture/     Authored and generated fixture bank
tooling/
  app_manifest/              Manifest generation and contract validation
  question_bank/             Question-bank generation and validation
  ci/                        Local and CI check entry points
docs/                        Monorepo, app-addition, and CI contracts
```

Each app is a standalone Flutter project. There is intentionally no root
Flutter package or root workspace package.

## Main checks

From the repository root:

```bash
tooling/ci/check_all.sh
```

Focused commands and CI scope behavior are documented in [docs/CI.md](docs/CI.md).
See [docs/ADDING_QUALIFICATION_APP.md](docs/ADDING_QUALIFICATION_APP.md) before
adding a qualification product. The complete layout contract is in
[docs/MONOREPO.md](docs/MONOREPO.md).
