# KOMADEKI UI/UX Physical Evidence Gate

Date: 2026-08-25
Verified repository baseline: `bb5150e82f6b45f70e435ca84a6bd4318f55032d`
Control issue: #48
Workstream: `qualification_factory_ui_ux`
Objective: `VERIFY_PHYSICAL_UX_EVIDENCE`
Result: `HUMAN_BLOCKED`

## Scope reconciliation

The UI/UX machine state previously observed `085a95b448d04d609aa421343021fd2ba819c7ec`.
Current GitHub `main` is `bb5150e82f6b45f70e435ca84a6bd4318f55032d` after Question Bank PR #131.
PR #131 changed only the post-188 Drone authoring gap-audit artifact and the separate
`tooling/komadeki_autopilot/drone_state.json`. It did not change
`packages/qualification_app`, the Drone production composition, released/runtime
question content, purchase/session behavior, or the UI/UX control plane.

Open Question Bank PR #132 changes the future Production target contract and the
separate Drone machine state; it does not provide physical-device UX evidence.
This UI/UX transition must still be recreated/reconciled if any concurrent
Question Bank PR advances `main` before merge.

## Repository evidence already satisfied

Repository evidence is sufficient for the non-physical portions of the gate:

- Product UX Closure passed on the shared Home -> learning -> feedback/result ->
  Home journey, including deterministic primary action, intentional leave/resume,
  practice feedback, mock feedback boundary, result/review, progress, weakness,
  recommendation, history, unlock/restore presentation, loading/failure/status,
  claims/source trust, and Drone-specific composition.
- Shared widget gates cover 320 logical px, 2.0x text scale, long Japanese
  question/choice content, scroll reachability, timed-mock header behavior,
  semantic live regions, non-color-only correctness, and standard Material touch
  controls.
- Drone remains a thin composition through `QualificationProductionBootstrap`
  plus the optional Home supplement; no app-specific controller/persistence/
  selection/purchase fork exists.
- `Quiz Apps iOS Smoke` provides a no-signing iOS build gate, but it is a build
  check and is not evidence of human interaction on a physical device.

These automated checks can establish render/layout/semantic contracts but cannot
establish actual finger interaction, device-level readability, perceived control
reachability, or physical scrolling behavior on a shipping phone.

## Remaining physical evidence

A single pass on the primary shipping platform is required for this UI/UX gate.
For the current Drone reference product, use a physical iPhone with a build that
contains the verified baseline commit or a later reconciled `main` commit.
Debug/device installation or TestFlight is acceptable; App Store purchase
completion is not required by this UI/UX gate.

Perform the following bounded interaction check:

1. Launch the app and confirm Home renders without clipped content, obstructed
   controls, or an unreadable primary action at the device's normal text size.
2. Start a practice session, select an answer, commit it, and confirm the
   correctness state, selected answer, correct answer, explanation, source, and
   `次へ` remain readable and reachable by normal scrolling.
3. Use the close/Home affordance during practice, return Home, and resume with
   `続きから`; confirm the interaction feels intentional and the committed state
   is preserved.
4. Start a timed mock when available in the test entitlement/build, confirm the
   progress/timer header remains readable, leave once, and verify the warning that
   time continues is understandable and the resumed timer is still usable.
5. Complete or use a prepared completed mock state and confirm result plus the
   expandable read-only review can be navigated without trapped scrolling,
   clipped text, or ambiguous answer/correct-answer distinction.
6. Confirm the unlock/restore surface is physically reachable and understandable.
   A real purchase or restore transaction is outside this gate unless release
   validation already provides an authenticated store environment.
7. If iOS Larger Text is already enabled on the test device, repeat the Home and
   one question interaction there; otherwise automated 2.0x widget coverage
   remains the accessibility evidence for this transition.

## Evidence contract

Resume evidence must be persisted to GitHub, preferably as a comment on control
issue #48, and include:

- device model and iOS version;
- build source (TestFlight build or commit SHA);
- PASS/FAIL for each numbered interaction check above;
- any concrete defect with the affected screen/action and, when useful, a
  screenshot or short screen recording reference;
- confirmation that the tested commit contains the current UI/UX baseline, or a
  note that the UI/UX gate was rerun after a newer `main` changed relevant code.

A plain statement such as "looks fine" is insufficient because it cannot be
reconciled to a build or acceptance step.

## Decision

No production defect is established by repository evidence, so this transition
must not change production behavior. The remaining acceptance criterion is a
non-remotely-evidenced physical-device observation explicitly allowed as a human
blocker by the UI/UX Autopilot contract.

Set the UI/UX workstream to `PHYSICAL_UX / HUMAN_BLOCKED` until the evidence
contract above is satisfied. After evidence is posted, the next autonomous
transition is still `VERIFY_PHYSICAL_UX_EVIDENCE`; it must reconcile the tested
commit against then-current `main` before advancing to `DONE`.

This transition does not mutate Question Bank authoring/acceptance/content,
Permanent IDs, released/runtime bank data, app behavior, or
`tooling/komadeki_autopilot/drone_state.json`.
