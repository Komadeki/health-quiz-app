# KOMADEKI UI/UX Physical Evidence Gate

Date: 2026-08-25
Verified repository baseline: `e93eb3de7fd02c493b8d6972a456cbf23a3e6221`
Verified production UI baseline: `1dac5bba96ee18ae2ae919bf7b5c8d5f31e7cb33`
Control issue: #48
Workstream: `qualification_factory_ui_ux`
Objective: `VERIFY_PHYSICAL_UX_EVIDENCE`
Result: `HUMAN_BLOCKED`

## Scope reconciliation

The previous physical-evidence contract was reconciled through the progress-dashboard baseline that introduced the completion ring, four-unit radar, and the four learner metrics.

GitHub `main` now additionally contains PR #287, `Polish Drone Home UX follow-up`, merged as production UI baseline `1dac5bba96ee18ae2ae919bf7b5c8d5f31e7cb33`. PR #287 preserves the existing shared Qualification runtime and the existing price-display specification while adding the following learner-facing changes:

- radar axes use concise semantic labels for Drone: `操縦体制`, `リスク`, `規則`, `システム`;
- a responsive legend exposes each short radar label together with the formal unit title;
- `模試ベスト` shows `未受験` before the first completed mock rather than an ambiguous dash;
- a low-sample weakness result is labelled `要確認の単元` until the weakest unit has at least five answers; only sufficient evidence is labelled `苦手な単元`;
- `続きから` identifies the resumed unit or mode and the exact persisted question position;
- the locked mock-exam control is actionable and opens unlock guidance instead of remaining a dead disabled control;
- the existing purchase price presentation is preserved unchanged.

PR #287 passed Quiz Apps CI run #487 (`32835361369`): scope, shared checks, qualification-app checks, health checks, and `ci-gate` all passed. The qualification checks include the Drone production seam and post-dashboard scroll interaction; shared checks include the existing compact-width, large-text, semantic, learning-state, purchase, progress, and session behavior gates.

After PR #287, `main` advanced through `e93eb3de7fd02c493b8d6972a456cbf23a3e6221`. The intervening changes are limited to Drone B15 Question Bank authoring artifacts and `tooling/komadeki_autopilot/drone_state.json`; they do not touch the shared Qualification UI or Drone production composition. Therefore `e93eb3de...` is the current reconciled repository baseline and `1dac5bba...` remains the verified production UI baseline contained within it.

If a later `main` changes relevant production UI before physical evidence is collected, this gate must be reconciled again.

## Repository evidence already satisfied

Repository evidence is sufficient for the non-physical portions of this gate:

- the shared Home -> learning -> feedback/result -> Home journey remains covered;
- deterministic primary action, intentional leave/resume, practice feedback, mock feedback boundary, result/review, progress, weakness/recommendation/history, unlock/restore, loading/failure/status, source trust, and Drone-specific composition remain covered;
- the progress dashboard and PR #287 changes are covered by shared and Drone widget tests without introducing an app-specific controller, persistence, selection, session, purchase, scoring, or Question Bank fork;
- automated responsive gates cover compact width, 2.0x text scale, long Japanese content, scroll reachability, semantic live state, and standard Material touch behavior;
- repository iOS build checks are build evidence only and are not physical-device interaction evidence.

Automated evidence cannot establish actual finger interaction, shipping-device readability, perceived control reachability, chart legibility, or physical scrolling behavior.

## Remaining physical evidence

A single bounded pass on a physical iPhone is required. Use a build containing UI baseline `1dac5bba96ee18ae2ae919bf7b5c8d5f31e7cb33` or a later `main` that has been reconciled against this UI baseline. Debug/device installation or TestFlight is acceptable. A real purchase or restore transaction is not required by this UI/UX gate.

Perform these checks:

1. Launch Home at normal text size. Confirm there is no clipped content or obstructed primary action. In `学習進捗`, confirm the completion ring is readable on the left; the radar on the right uses readable `操縦体制` / `リスク` / `規則` / `システム` labels; the formal-unit legend is understandable; and the four tiles `学習済み` / `正答率` / `要復習` / `模試ベスト` are legible without ambiguous overlap or truncation. Before any completed mock, `模試ベスト` should read `未受験`.
2. With only a small number of answers in the weakest unit, confirm Home uses `要確認の単元` rather than prematurely asserting `苦手な単元`, and that the explanatory copy is understandable. Interact with learning and confirm progress, radar values, and review-related values remain visually stable during normal scrolling.
3. Start a practice session, select and commit an answer, and confirm correctness, selected answer, correct answer, explanation, source, and `次へ` remain readable and reachable through normal scrolling.
4. Leave an in-progress practice session to Home. Confirm `続きから` names the relevant unit or mode and shows the persisted question position, then resume and confirm committed state is preserved.
5. When the mock exam is locked, confirm the mock control is visibly actionable, tapping it opens the unlock guidance, the guidance is understandable, and dismissing it returns cleanly to Home. Also confirm the normal unlock/restore surface remains physically reachable. The existing displayed price format is intentionally not part of this UI change.
6. When a timed mock is available in the test entitlement/build, confirm the progress/timer header is readable, leave once, verify the warning that time continues is understandable, then resume and confirm the timer remains usable.
7. Complete a mock or use a prepared completed-mock state. Confirm result and expandable read-only review can be navigated without trapped scrolling, clipped text, or ambiguous recorded-answer/correct-answer distinction; after returning Home, confirm `模試ベスト` shows the completed result.
8. If iOS Larger Text is already enabled on the test device, repeat the Home progress card and one question interaction there. Otherwise the automated 2.0x widget gate remains the accessibility evidence for this transition.

## Evidence contract

Persist resume evidence to GitHub, preferably as a comment on control issue #48, containing:

- device model and iOS version;
- TestFlight build or tested commit SHA;
- PASS/FAIL for every numbered check above;
- concrete defect evidence for any failure, with the affected screen/action and screenshot or short recording when useful;
- confirmation that the tested build contains the current UI baseline, or a note that the gate was reconciled after a newer relevant `main` change.

A general statement such as `looks fine` is insufficient because it cannot be tied to a build or acceptance step.

## Decision

No production UI defect is established by repository evidence. PR #287 is accepted as repository-verified UI/UX improvement, but the workstream remains `PHYSICAL_UX / HUMAN_BLOCKED` because the remaining acceptance criterion is physical-device observation.

After durable physical evidence is posted, the next autonomous transition is still `VERIFY_PHYSICAL_UX_EVIDENCE`: reconcile the tested commit against then-current `main`; if all checks pass and no newer relevant UI invalidates the evidence, advance to `DONE` through the normal PR/CI gate.

This reconciliation does not mutate Question Bank authoring/acceptance/content, Permanent IDs, released/runtime bank data, scoring, purchase/session semantics, the price-display specification, or `tooling/komadeki_autopilot/drone_state.json`.
