# Repository instructions for Codex and other coding agents

## Repository boundaries
- This repository is the KOMADEKI quiz-app **monorepo** (its name is historical).
- Read the root `README.md`, then only task-relevant docs: `docs/MONOREPO.md` for app boundaries, `docs/CI.md` for checks, and `apps/health/README.md` for the published Health app.
- There is no root Flutter package. Apps live in `apps/*`; shared logic lives in `packages/*`; tooling and question banks have their own contracts.
- Do not change another app, shared package, app identity, question IDs, purchases, or persistence as a side effect of a Health-only task. Broaden scope only with demonstrated need and explicit approval.

## Resource and implementation discipline
- Use coding agents for repository changes; planning, PR status, CI inspection, and decisions that require no change should not start an implementation.
- Prefer a lightweight model for simple, well-specified edits; use a standard model for ordinary implementation; escalate only for demonstrated complexity, uncertain root cause, or high-risk architectural changes. Do not escalate automatically because a project is important.
- Keep reads, diffs, changes, dependencies, and tests proportional to the task. Avoid speculative redesign, parallel agents, and unnecessary tooling.

## Before modifying files
- Check `git status`, the branch and its base, and overlapping active PRs; preserve uncommitted or parallel-agent changes.
- State the affected paths, expected behavior, smallest change, and focused verification plan.
- Follow the source-of-truth documents above instead of duplicating or replacing their instructions.

## Safety and approvals
- Never commit tokens, credentials, real student or teacher data, or other private information.
- Do not force-push, rewrite shared history, or use destructive resets.
- Do not merge PRs, publish releases, deploy production, submit to app stores, alter live billing/IAP configuration, or migrate/delete production data without explicit task-specific authorization. A PR is not a release approval.
- Keep code changes on a task branch and open a reviewable PR where appropriate; do not overwrite another agent's work.

## Verification and reporting
- Use `docs/CI.md` to select scoped checks. For `apps/health/` work, run relevant Flutter analysis and tests from that app directory; use root `tooling/ci/check_all.sh` for shared or cross-app changes as warranted.
- Run only the checks needed to support the change and its risk, expanding after failures or for shared-contract changes.
- Never claim an unrun check, a device test, or a purchase flow was verified.
- Finish with a concise summary of changes, tests actually run, remaining risks, and next action.
