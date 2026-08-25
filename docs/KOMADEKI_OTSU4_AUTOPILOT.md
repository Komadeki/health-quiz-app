# KOMADEKI Qualification #2 (Otsu4) Autopilot Contract v1.0

This contract governs the autonomous delivery of Qualification #2, the Japanese Hazardous Materials Engineer Class B, Category 4 examination (危険物取扱者 乙種4類, "Otsu4"). It extends, rather than replaces, the Factory-wide contract in `KOMADEKI_AUTOPILOT.md`.

## 1. Scope and boundaries

The Otsu4 product reuses Qualification App Factory v1.0. Its durable control plane must not change shared Factory architecture, Drone contracts, or Drone machine state unless an independently selected atomic objective proves a shared compatibility need.

The dedicated machine state is `tooling/komadeki_autopilot/otsu4_state.json`. Its dedicated control issue is GitHub issue #185. A single run may advance only the state referenced by that objective.

The initial product constraints are already fixed by issue #185:

- do not reproduce, redistribute, or market copyrighted published past questions;
- author an original Question Bank from rights-cleared authoritative sources;
- preserve the Factory's `explicit_v1` identity and `qualification_runtime_v2` runtime conventions;
- retain the initial `singleFullUnlock` monetization stance unless a later product-spec decision durably changes it;
- differentiate through Otsu4's three subject thresholds, coverage-aware learning, and high-error decision boundaries, not a fork of shared capabilities.

## 2. Authority and reconciliation order

For every Otsu4 run, resolve conflicting evidence in this exact order:

1. current GitHub `main`;
2. repository-resident authoritative contracts;
3. `tooling/komadeki_autopilot/otsu4_state.json`;
4. GitHub issue #185;
5. merged pull requests and their successful required CI evidence.

Chat history, model memory, local branches, local commits, ephemeral worktrees, and browser state are never completion evidence. A newer item lower in this list may record progress, but cannot override a higher authority without an explicit compatible update to that authority.

## 3. `進めて` run protocol

When the owner says only `進めて`, ChatGPT must perform one and only one meaningful atomic transition:

1. read the five authority sources above, including the issue, open PRs, current `main`, and required CI;
2. report `current state` and select the smallest safe `next_atomic_objective`;
3. use direct GitHub operations for read-only audits, issue/state synchronization, PR/CI inspection, safe metadata changes, and merging;
4. route repository reasoning, production code, multi-file behavior changes, migrations, or debugging to Codex only when needed;
5. persist the transition to GitHub, independently audit its PR and CI evidence, then synchronize machine state and issue #185;
6. report exactly: `current state`, `atomic action`, `PASS` or `REWORK`, `blocker`, and `next objective`.

No unpersisted work is a pass. Do not perform a second meaningful transition in the same run. Do not advance state merely because a worker claims success.

## 4. Initial transition and question-bank governance

The first active objective is `FREEZE_OTSU4_AUTHORITATIVE_SOURCE_SET_AND_PRODUCT_SPEC_V0`. Its durable output must define the official-source inventory, rights classification, frozen exam profile, customer problem, product promise, differentiation, and an initial Question Bank size and coverage map. It must not author production questions or change Factory behavior.

Before autonomous question acceptance begins, Otsu4 must have a repository-resident Question Bank contract compatible with `KOMADEKI_AUTONOMOUS_QUESTION_ACCEPTANCE.md`. Until then the state remains `MIGRATION_REQUIRED`; no actor may claim a fabricated human review.

## 5. Gates and human-only escalation

Use the canonical phase order in `state.schema.json`. A phase advances only with durable GitHub evidence and required CI. Before merging a PR, confirm the base/head, changed-file scope, current-main reconciliation, required validations, successful CI, and absence of unresolved P0/P1 findings.

Enter `HUMAN_BLOCKED` only for an action unavailable to the connected tools and genuinely reserved for a human, such as Apple account authentication/signing, physical-device evidence unavailable remotely, or owner-reserved final brand judgment. Record exactly one requested action and the evidence that resumes work in both the state and issue #185. In the user-facing report, use:

```text
HUMAN REQUIRED:
<one action>
<resume evidence>
```

Routine product, source, implementation, GitHub, PR, CI, and state work must not be returned to the owner.
