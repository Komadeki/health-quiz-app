# KOMADEKI UI/UX Physical Evidence Gate

Date: 2026-08-25
Verified repository baseline: `dabdc2a4869ee41103540ee4fd3de4fbae4b0d8f`
Verified production UI baseline: `ebce7f3b3de1d76ab778f52746bb7c8a2e0dc729`
Control issue: #48
Workstream: `qualification_factory_ui_ux`
Objective: `VERIFY_PHYSICAL_UX_EVIDENCE`
Result: `HUMAN_BLOCKED`

## Scope reconciliation

The previous physical-evidence contract observed UI/UX baseline
`00f19d57e11d89a742056b846759c8a8b60cdf67`.

GitHub `main` now includes PR #257, `Add unit radar and actionable progress metrics`, merged
as production UI baseline `ebce7f3b3de1d76ab778f52746bb7c8a2e0dc729`. Subsequent main
advancement through `dabdc2a4869ee41103540ee4fd3de4fbae4b0d8f` changes only Otsu4
Question Bank authoring/source/state artifacts and does not touch the shared Qualification UI
or Drone production composition. Therefore `dabdc2a...` is the current reconciled repository
baseline and `ebce7f3b...` remains the verified UI baseline contained within it.

The reconciled progress dashboard now provides:

- completion ring on the left;
- unit-performance visualization on the right, with Drone's four units rendered as a radar
  chart from actual per-unit accuracy;
- four learner-facing metrics: `学習済み`, `正答率`, `要復習`, and `模試ベスト`;
- `要復習` derived from the existing most-recent-incorrect practice-selection semantics,
  respecting current access;
- `模試ベスト` derived only from completed mock-exam history and shown as unavailable before
  the first completed mock;
- responsive fallback behavior for qualifications that cannot form a radar chart.

PR #257 passed required Quiz Apps CI run #422 (`32826160634`): scope, shared checks,
qualification-app checks, health checks, and ci-gate all passed. The shared checks include the
existing compact/large-text gates and new progress-dashboard behavior assertions; the Drone
product-seam test confirms its four-unit bank uses the radar rendering path.

If a later `main` changes relevant production UI before physical evidence is collected, the
physical gate must be reconciled again rather than treating this baseline as current.

## Repository evidence already satisfied

Repository evidence is sufficient for the non-physical portions of the gate:

- Product UX Closure remains satisfied for the shared Home -> learning -> feedback/result ->
  Home journey, including deterministic primary action, intentional leave/resume, practice
  feedback, mock feedback boundary, result/review, progress, weakness, recommendation,
  history, unlock/restore presentation, loading/failure/status, claims/source trust, and
  Drone-specific composition.
- The post-closure progress-dashboard change is covered by shared and Drone widget tests and
  does not fork controller, persistence, selection, purchase, session, or Question Bank
  behavior.
- Shared widget gates cover 320 logical px, 2.0x text scale, long Japanese question/choice
  content, scroll reachability, timed-mock header behavior, semantic live regions,
  non-color-only correctness, and standard Material touch controls.
- Drone remains a thin composition through `QualificationProductionBootstrap` plus the
  optional Home supplement; no app-specific controller/persistence/selection/purchase fork
  exists.
- Repository iOS build checks are build evidence only; they are not evidence of human
  interaction on a physical device.

These automated checks can establish render/layout/semantic contracts but cannot establish
actual finger interaction, device-level readability, perceived control reachability, chart
legibility, or physical scrolling behavior on a shipping phone.

## Remaining physical evidence

A single pass on the primary shipping platform is required for this UI/UX gate. For the
current Drone reference product, use a physical iPhone with a build containing this verified
UI baseline or a later reconciled `main` commit. Debug/device installation or TestFlight is
acceptable; App Store purchase completion is not required by this UI/UX gate.

Perform the following bounded interaction check:

1. Launch the app and confirm Home renders without clipped content, obstructed controls, or
   an unreadable primary action at the device's normal text size. In `学習進捗`, specifically
   confirm the completion ring is readable on the left, the four-unit radar is readable on
   the right, and the four tiles `学習済み` / `正答率` / `要復習` / `模試ベスト` are legible
   without ambiguous truncation or overlap.
2. Interact with learning so the Home metrics change, return Home, and confirm progress,
   per-unit performance, `要復習`, and `模試ベスト` present plausible values and remain
   visually stable during normal scrolling. `模試ベスト` may remain unavailable until a
   completed mock exists.
3. Start a practice session, select an answer, commit it, and confirm the correctness state,
   selected answer, correct answer, explanation, source, and `次へ` remain readable and
   reachable by normal scrolling.
4. Use the close/Home affordance during practice, return Home, and resume with `続きから`;
   confirm the interaction feels intentional and the committed state is preserved.
5. Start a timed mock when available in the test entitlement/build, confirm the progress/
   timer header remains readable, leave once, and verify the warning that time continues is
   understandable and the resumed timer is still usable.
6. Complete or use a prepared completed mock state and confirm result plus the expandable
   read-only review can be navigated without trapped scrolling, clipped text, or ambiguous
   answer/correct-answer distinction. Return Home and confirm `模試ベスト` reflects a
   completed mock result.
7. Confirm the unlock/restore surface is physically reachable and understandable. A real
   purchase or restore transaction is outside this gate unless release validation already
   provides an authenticated store environment.
8. If iOS Larger Text is already enabled on the test device, repeat the Home progress card
   and one question interaction there; otherwise automated 2.0x widget coverage remains the
   accessibility evidence for this transition.

## Evidence contract

Resume evidence must be persisted to GitHub, preferably as a comment on control issue #48,
and include:

- device model and iOS version;
- build source (TestFlight build or commit SHA);
- PASS/FAIL for each numbered interaction check above;
- any concrete defect with the affected screen/action and, when useful, a screenshot or
  short screen recording reference;
- confirmation that the tested commit contains the current UI/UX baseline, or a note that
  the UI/UX gate was rerun after a newer `main` changed relevant code.

A plain statement such as "looks fine" is insufficient because it cannot be reconciled to a
build or acceptance step.

## Decision

No production defect is established by repository evidence. PR #257 is accepted as a
repository-verified UI improvement, but the UI/UX workstream must remain
`PHYSICAL_UX / HUMAN_BLOCKED` because the remaining acceptance criterion is physical-device
observation.

After evidence is posted, the next autonomous transition remains
`VERIFY_PHYSICAL_UX_EVIDENCE`; it must reconcile the tested commit against then-current
`main` before advancing to `DONE`.

This reconciliation changes only durable UI/UX evidence/control state. It does not mutate
Question Bank authoring/acceptance/content, Permanent IDs, released/runtime bank data,
purchase/session behavior, or `tooling/komadeki_autopilot/drone_state.json`.