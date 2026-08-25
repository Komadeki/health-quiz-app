# KOMADEKI UI/UX Physical Evidence Gate

Date: 2026-08-25
Verified repository baseline: `188a8425e837d5fc5cb6db4bc63c7c11f063b2d4`
Verified production UI baseline: `10f0c65f825c3c25fa21f47e0fb72cb64a60e981`
Control issue: #48
Workstream: `qualification_factory_ui_ux`
Objective: `VERIFY_PHYSICAL_UX_EVIDENCE`
Result: `HUMAN_BLOCKED`

## Scope reconciliation

The physical-evidence contract now includes both the PR #287 Home/progress improvements and PR #323, `Expand Drone free tier and strengthen purchase UX`, merged as production UI baseline `10f0c65f825c3c25fa21f47e0fb72cb64a60e981`.

Repository `main` subsequently advanced through `188a8425e837d5fc5cb6db4bc63c7c11f063b2d4` via B17 authoring/review and Drone autopilot-state evidence. Those intervening changes do not touch the shared Qualification production UI, Drone production composition, or released runtime bank, so `10f0c65f...` remains the verified production UI baseline contained in the current repository baseline.

The resulting Drone production UI/runtime keeps the shared Qualification architecture and the existing StoreKit price-display specification while adding or preserving these learner-facing behaviors:

- radar axes use `操縦体制`, `リスク`, `規則`, `システム`, with the formal unit names exposed in a responsive legend;
- `模試ベスト` shows `未受験` before a completed mock and is actionable when the mock route is available;
- low-sample weakness wording remains conservative as `要確認の単元` until the minimum-answer threshold is met;
- `続きから` identifies the unit/mode and persisted question position;
- the free tier is 30 questions, while random practice remains a 20-question session and is regression-tested to start with 20 unique accessible questions;
- locked mock entry opens contextual unlock guidance instead of being a dead control;
- the mock unlock sheet explains the benefit set and uses the result-oriented CTA `全188問を解放する`;
- the bottom full-unlock card shows free-tier learning progress, `全188問すべて利用可能`, `各単元の全問題`, the mock-exam benefit, purchase CTA, and purchase restore;
- the displayed `$4.99` format is intentionally unchanged.

PR #323 passed Quiz Apps CI run #575 (`32845647084`): scope, shared checks, qualification-app checks, and health checks all passed. The bank contract is `drone-second-class-v3-release-2026-08-25`, 188 active questions, 30 free, and 158 premium. The original 20 free questions remain free; 10 already-released questions were added to the free tier without changing question text, correct answers, Permanent IDs, or Question versions.

If a later `main` changes relevant production UI before physical evidence is collected, this gate must be reconciled again.

## Repository evidence already satisfied

Repository evidence is sufficient for the non-physical portions of this gate:

- the shared Home -> learning -> feedback/result -> Home journey remains covered;
- the 30-question entitlement contract and 20-question random-practice headroom are tested;
- the contextual mock unlock sheet, full-unlock card, result-oriented CTA, restore control, and tappable pre-mock metric are covered by widget tests;
- deterministic primary action, intentional leave/resume, practice feedback, mock feedback boundary, result/review, progress, weakness/recommendation/history, loading/failure/status, source trust, and Drone-specific composition remain covered;
- automated responsive gates cover compact width, large text, long Japanese content, scroll reachability, semantics, and standard Material touch behavior;
- repository iOS build checks are build evidence only and are not physical-device interaction evidence.

Automated evidence cannot establish actual finger interaction, shipping-device readability, perceived control reachability, chart legibility, or physical scrolling behavior.

## Remaining physical evidence

A single bounded pass on a physical iPhone is required. Use a build containing production UI baseline `10f0c65f825c3c25fa21f47e0fb72cb64a60e981` or a later `main` reconciled against it. Debug/device installation or TestFlight is acceptable. A real purchase or restore transaction is not required by this UI/UX gate.

Perform these checks:

1. Launch Home at normal text size. Confirm the Hero states `30問を無料で体験`, there is no clipped content or obstructed primary action, and the completion ring, four-axis radar, formal-unit legend, and `学習済み / 正答率 / 要復習 / 模試ベスト` tiles are readable. Before any completed mock, `模試ベスト` should read `未受験`.
2. Start `ランダム演習` while not fully unlocked. Confirm a 20-question session starts normally and question/choice/commit/feedback controls remain reachable through normal scrolling.
3. With only a small number of answers in the weakest unit, confirm Home uses `要確認の単元` rather than prematurely asserting `苦手な単元`, and that the explanatory copy is understandable.
4. Leave an in-progress practice session to Home. Confirm `続きから` names the relevant unit or mode and shows the persisted question position, then resume and confirm committed state is preserved.
5. When the mock exam is locked, tap both the normal mock control and, when visible, `模試ベスト / 未受験`. Confirm the unlock sheet opens, clearly explains full-question and mock benefits, shows the unchanged configured price format, exposes `全188問を解放する`, and can be dismissed cleanly.
6. Scroll to the normal full-unlock card. Confirm it is physically reachable and understandable, displays `無料問題 x / 30問 学習済み`, the benefit list, `全188問を解放する`, and `購入を復元` without clipping or accidental overlap. Do not complete a real purchase for this gate.
7. When a timed mock is available in the test entitlement/build, confirm the progress/timer header is readable, leave once, verify the warning that time continues is understandable, then resume and confirm the timer remains usable. If a completed-mock state is available, confirm result/review navigation and the updated `模試ベスト` value remain clear.
8. If iOS Larger Text is already enabled on the test device, repeat the Home progress card and one question interaction there. Otherwise the automated large-text widget gate remains the accessibility evidence for this transition.

## Evidence contract

Persist resume evidence to GitHub, preferably as a comment on control issue #48, containing:

- device model and iOS version;
- TestFlight build or tested commit SHA;
- PASS/FAIL for every numbered check above;
- concrete defect evidence for any failure, with the affected screen/action and screenshot or short recording when useful;
- confirmation that the tested build contains the current production UI baseline, or a note that the gate was reconciled after a newer relevant `main` change.

A general statement such as `looks fine` is insufficient because it cannot be tied to a build or acceptance step.

## Decision

No production UI defect is established by repository evidence. PR #287 and PR #323 are accepted as repository-verified UI/UX improvements, but the workstream remains `PHYSICAL_UX / HUMAN_BLOCKED` because the remaining acceptance criterion is physical-device observation.

After durable physical evidence is posted, reconcile the tested commit against then-current `main`; if every check passes and no newer relevant UI invalidates the evidence, advance the UI/UX workstream to `DONE` through the normal PR/CI gate.
