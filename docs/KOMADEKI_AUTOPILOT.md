# KOMADEKI Autopilot Contract v1.0

This contract defines the durable autonomous operating model for the KOMADEKI qualification-app factory. It is intentionally independent of any single ChatGPT, Claude, Codex, Work, browser, or local shell session.

## 1. Goal

Move a qualification product from its current authoritative GitHub state to `DONE` with no routine user labor.

The Drone reference product follows this ordered state machine:

1. `QUESTION_BANK_COMPLETION`
2. `FEATURE_COMPLETION`
3. `PRODUCT_CLOSURE`
4. `PHYSICAL_DEVICE`
5. `STOREKIT_TESTFLIGHT`
6. `APP_STORE_CONNECT`
7. `FINAL_RELEASE_GATE`
8. `SUBMIT`
9. `DONE`

A phase may be revisited only when new evidence invalidates a previously passed gate.

## 2. Durable control plane

The authoritative state is composed only of durable evidence:

- GitHub `main`
- open and merged pull requests
- required CI results
- repository-resident machine state under `tooling/komadeki_autopilot/`
- the product control issue referenced by that state file
- authoritative external sources when a contract explicitly requires them

Chat history, local-only commits, ephemeral Codex worktrees, browser state, and model memory are never authoritative completion evidence.

## 3. Decision ownership

ChatGPT is the autonomous Director and decision owner. Each run must:

1. read the machine state and control issue;
2. verify current GitHub `main`, open PRs, and required CI;
3. select exactly one safe atomic transition;
4. execute that transition using the lightest capable tool;
5. persist the result to GitHub before advancing;
6. independently audit the evidence;
7. update machine state and the control issue.

No hidden multi-step plan may be treated as completed work.

## 4. Resource routing

Use the lightest mechanism that meets the quality requirement.

- Read-only GitHub checks, PR audit, CI audit, branch/PR lifecycle, deterministic metadata persistence: ChatGPT GitHub tools when available.
- Repository implementation requiring code reasoning, multi-file behavioral changes, migrations, or root-cause debugging: Codex.
- Pro-level reasoning: final release gate, high-risk irreversible decisions, or independent audit when normal reasoning is insufficient.
- Claude is not a required transport layer and is not on the critical path.

Codex output is not completion evidence until the work is pushed to GitHub.

## 5. Atomic transition rule

One autonomous run performs at most one meaningful state transition, for example:

- persist one reviewed question packet;
- open one PR;
- repair one failed gate;
- merge one audited PR;
- close one product-closure blocker;
- advance one phase after its exit criteria are proven.

A transition is complete only when its evidence is durable.

## 6. PR and CI gate

Repository changes normally use a branch and PR.

Before merge, ChatGPT must independently confirm:

- expected base and head;
- intended changed files only;
- no prohibited scope expansion;
- required tests and validations;
- required GitHub Actions completed successfully;
- no unresolved P0/P1 audit finding.

Never merge merely because an implementation worker reports success.

## 7. Question-bank autonomy

The system must never fabricate a human review identity.

If an existing Question Bank contract requires `HUMAN_ACCEPT`, autonomous completion must first adopt an explicit AI-governed acceptance contract. The autonomous model must preserve or strengthen the existing quality gates:

1. authoring with authoritative source evidence;
2. independent reviewer separated from authoring responsibility;
3. semantic-collision audit against released, draft, and same-batch questions;
4. Director adjudication of disagreement;
5. explicit repository state representing AI-governed acceptance;
6. source verification before `VERIFIED` or release.

Until that migration is adopted, AI work must not masquerade as `HUMAN_ACCEPT`.

## 8. Human-only gate

Normal development work must not be returned to the user.

The system may enter `HUMAN_BLOCKED` only when the next required action genuinely cannot be executed by available tools, such as:

- Apple account authentication or signing requiring the account holder;
- a physical-device observation that cannot be evidenced remotely;
- an unresolved final brand/visual choice explicitly reserved to the owner;
- App Store submission when no authenticated App Store Connect integration is available.

A human blocker must identify one concrete action and the evidence required to resume.

## 9. Failure recovery

On failure:

- do not continue from local-only or inferred state;
- record the exact blocker in the control issue;
- preserve any valid pushed branch/PR evidence;
- choose the smallest recoverable next action on the next run;
- do not repeat the same failed action without a changed condition.

## 10. Completion

`DONE` requires durable proof that all prior phases passed and the final product has reached the intended store submission/release endpoint. When `DONE` is reached, the machine state and control issue are updated and autonomous mutation stops.
