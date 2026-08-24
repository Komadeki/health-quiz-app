# KOMADEKI Qualification Factory UI/UX Baseline Audit

Date: 2026-08-24
Baseline `main`: `585f7b5771c0840b547441d370382c931da6b8c9`
Workstream: `qualification_factory_ui_ux`
Control issue: #48

## Audit scope

This is a repository-evidence audit only. It does not change production behavior.

Inspected:

- `packages/qualification_app/lib/src/production_app.dart`
- `packages/qualification_app/lib/src/production_controller.dart`
- `packages/qualification_app/lib/src/production_bank.dart`
- `packages/qualification_app/test/production_widget_test.dart`
- `packages/quiz_engine/lib/src/models/card.dart`
- `apps/drone_second_class/app.yaml`
- `apps/drone_second_class/lib/production/production_app.dart`
- `apps/drone_second_class/test/production_widget_test.dart`
- `question_banks/drone_second_class/generated/drone_second_class_bank.json`
- Factory architecture contracts under `docs/`

Priority meanings:

- **P0**: product-flow or semantic defect that should block Product UX Closure.
- **P1**: material product-quality gap that should be closed before Product UX Closure unless explicitly rejected with durable rationale.
- **P2**: useful improvement that does not block Product UX Closure after P0/P1 are closed.

## Baseline strengths

The Factory already has a substantial reusable production shell: Home, resume persistence, unit/random/unanswered/incorrect/retry modes, timed mock exam, progress, weakness, recommendation, history, full unlock/restore, local persistence, safe external links, fatal-load handling, and widget/controller tests. The shared-vs-qualification-specific architecture boundary is explicit and appropriate.

The Question Bank already carries permanent IDs and source metadata (`sourceId`, `sourceTitle`, `sourceSection`, `sourceVersion`) through `QuizCard`, so source-aware UX does not require inventing a separate provenance store.

## Findings

### P0

#### UX-P0-001 — Mock exam reveals answer feedback during the exam

- Ownership: `FACTORY_SHARED`
- Evidence: `QualificationQuizPage` renders `正解` / `不正解` and the explanation after every committed answer without a `LearningModeV1.mockExam` exception. Drone enables mock exam with a 50-question / 30-minute profile.
- User impact: later answers can be influenced by in-exam feedback; the feature behaves like practice under a timer rather than a credible mock exam.
- Acceptance criteria:
  - mock-exam answer commit does not reveal correctness, correct choice, explanation, or source before completion;
  - the deadline/completion result remains deterministic;
  - learning feedback becomes available only after mock completion through result/review UX.

#### UX-P0-002 — No intentional leave/pause path from an active quiz

- Ownership: `FACTORY_SHARED`
- Evidence: the quiz screen has no Home, close, pause, or back action. `QualificationProductionController.returnHome()` is only exposed from the result screen, while active sessions are already persisted and Home already supports `続きから`.
- User impact: a learner must finish the session or terminate/background the app to leave normal practice. Persisted resume capability exists but cannot be reached through a normal in-app flow.
- Acceptance criteria:
  - practice sessions expose an explicit leave-to-Home action that preserves the active session;
  - Home exposes resume for that preserved session;
  - timed mock behavior explicitly preserves wall-clock deadline semantics and does not silently pause the exam clock.

#### UX-P0-003 — Empty practice modes can become silent no-op actions

- Ownership: `FACTORY_SHARED`
- Evidence: `間違い演習` and `未回答演習` buttons are enabled based on feature flags, while `startIncorrect()` / `startUnanswered()` may produce an empty selection and `_startSession()` returns `false`; the UI does not consume that result or show a state message.
- User impact: especially for a new learner with no incorrect answers, tapping a visible action can appear broken.
- Acceptance criteria:
  - eligibility is represented before tap where practical, or an explicit empty-state response is shown after tap;
  - no enabled learning action fails silently;
  - empty-state behavior has widget coverage.

### P1

#### UX-P1-001 — Home does not establish one primary next action

- Ownership: `FACTORY_SHARED`
- Evidence: after optional resume/progress, Home renders all units, all standard practice modes, weakness, recommendation, history, then purchase. Recommendation is below the feature list rather than acting as the main action.
- User impact: the learner must interpret the product structure instead of being guided toward the next useful study action.
- Acceptance criteria:
  - Home has a deterministic primary-action hierarchy such as resume -> due/review -> weakness/recommendation -> start learning;
  - secondary modes remain discoverable without competing equally with the primary action;
  - the hierarchy is testable from controller state.

#### UX-P1-002 — Incorrect-answer feedback does not explicitly identify the correct choice

- Ownership: `FACTORY_SHARED`
- Evidence: after commit, the screen shows only `正解` / `不正解` plus explanation; choice tiles are disabled but the correct option is not explicitly identified for an incorrect response.
- User impact: learners must infer the correct answer from prose, increasing unnecessary cognitive load.
- Acceptance criteria:
  - practice feedback distinguishes selected answer and correct answer;
  - correctness is not communicated by color alone;
  - long Japanese choice text remains readable at large text scale.

#### UX-P1-003 — Per-question source provenance is available but not shown

- Ownership: `FACTORY_SHARED`
- Evidence: runtime Drone questions contain source title/version/section, `QuizCard` preserves those fields, but the production quiz renders only explanation.
- User impact: the strongest trust/verification asset of the Question Bank is invisible to the learner.
- Acceptance criteria:
  - a reusable source panel renders title, version, and section when present;
  - practice can show it after answer commit;
  - mock exam exposes it only in post-exam review;
  - missing source fields fail gracefully without placeholder noise.

#### UX-P1-004 — Loading/fatal states and action failures are not yet product-grade

- Ownership: `FACTORY_SHARED`
- Evidence: loading is an unlabeled spinner; fatal load renders the raw error string; several controller actions return `false` without a standard user-facing state surface.
- User impact: failure recovery and accessibility are inconsistent, and internal error detail can leak into user copy.
- Acceptance criteria:
  - loading has semantic/user-readable status;
  - fatal errors use stable user copy with a safe recovery path where possible;
  - expected nonfatal failures use a common status/message mechanism rather than silent no-op behavior.

#### UX-P1-005 — Responsive/accessibility gates are too narrow

- Ownership: `FACTORY_SHARED`
- Evidence: shared widget coverage primarily exercises one large 800x1800 viewport. There is no durable large-text / compact-width gate for the Home stack, long Japanese question/choice text, or the mock-exam AppBar row containing progress and remaining time.
- User impact: overflow, clipped controls, or unreadable hierarchy may appear on smaller devices or with larger accessibility text settings without CI detecting it.
- Acceptance criteria:
  - widget tests cover compact phone width and large text scaling;
  - long question/choice fixtures cover scrolling and action reachability;
  - mock timer/progress header remains usable under the same conditions;
  - essential state changes have appropriate semantics.

#### UX-P1-006 — Drone headline duplicates a dynamic question count as static copy

- Ownership: `DRONE_SPECIFIC`
- Evidence: `app.yaml` hard-codes `教則第5版を基にした全100問` while Home separately derives the usable question count from the runtime bank. The Question Bank workstream is actively expanding beyond the original 100-question seed.
- User impact: the product can display stale or contradictory counts after a legitimate bank update.
- Acceptance criteria:
  - Drone headline does not embed a manually maintained total, or the total is generated from the authoritative runtime manifest;
  - visible question counts have one authoritative source.

#### UX-P1-007 — Drone has no explicit qualification-specific product UX seam yet

- Ownership: `DRONE_SPECIFIC`
- Evidence: `DroneProductionBootstrap` delegates directly to `QualificationProductionBootstrap`; qualification differences are currently manifest/content-driven only.
- User impact: the product risks feeling like a generic shell despite having strong domain/source data and a four-area exam structure.
- Acceptance criteria:
  - add at least one defensible Drone-specific presentation tied to official source/exam structure or learning path, not cosmetic duplication;
  - use Factory extension/configuration seams and shared components rather than forking controllers, persistence, selection algorithms, purchase handling, or standard screens.

#### UX-P1-008 — Mock result needs a post-exam review path once in-exam feedback is removed

- Ownership: `FACTORY_SHARED`
- Depends on: `UX-P0-001`
- Evidence: result currently shows score/pass state and can retry incorrect questions, but there is no post-exam item review surface.
- User impact: after correcting mock semantics, a learner otherwise loses the explanation/source learning value of the completed mock.
- Acceptance criteria:
  - completed mock has a review path that exposes recorded answer, correct answer, explanation, and source where available;
  - review cannot mutate the completed attempt;
  - retry remains a separate new attempt.

### P2

#### UX-P2-001 — Weakness remains unit-level and knowledge-target persistence is unused

- Ownership: `FACTORY_SHARED`
- Evidence: Factory architecture allows optional knowledge-target metrics, but answer events are currently persisted with `knowledgeTarget: null` and production `QuizCard` has no knowledge-target field.
- User impact: weakness guidance cannot become more precise than broad units even when authoring/coverage data contains finer concepts.
- Acceptance criteria:
  - define a backward-compatible optional knowledge-target seam before exposing finer weakness UX;
  - preserve unit-level behavior when no target exists.

#### UX-P2-002 — History is summary-only

- Ownership: `FACTORY_SHARED`
- Evidence: Home renders the five latest completed sessions as read-only score rows.
- User impact: useful past-session context exists but cannot be inspected or reused directly.
- Acceptance criteria:
  - evaluate a history-detail/review entry point after core P0/P1 flows are stable;
  - do not duplicate the mock-review implementation.

#### UX-P2-003 — Shared product copy mixes Japanese and English implementation terms

- Ownership: `FACTORY_SHARED`
- Evidence: visible labels include `解説（Explanation）` and `Full Unlock` alongside Japanese UI copy.
- User impact: product polish and terminology consistency are weaker than necessary.
- Acceptance criteria:
  - adopt consistent learner-facing terminology;
  - keep developer/internal naming out of visible production copy unless intentionally branded.

#### UX-P2-004 — Progress is informative but weakly actionable

- Ownership: `FACTORY_SHARED`
- Evidence: progress shows completion percent/count and attempts but has no direct action. Recommendation exists separately lower on Home.
- User impact: the metric explains state without directly converting that state into the next study action.
- Acceptance criteria:
  - address primarily through the Home primary-action hierarchy before adding more metrics;
  - avoid unsupported pass-probability or "real exam ability" claims.

## Ownership summary

- Factory shared: 3 P0, 6 P1, 4 P2.
- Drone specific: 0 P0, 2 P1, 0 P2.

The absence of Drone-specific P0 findings means the current blocking UX defects should be fixed once in the Factory rather than patched in Drone.

## Recommended transition order

1. Adopt a durable Standard UX Contract covering session lifecycle, mock-exam semantics, empty states, Home action hierarchy, feedback/source presentation, and accessibility gates.
2. Close `UX-P0-001`, `UX-P0-002`, and `UX-P0-003` as bounded shared Factory transitions.
3. Close shared P1 feedback/source/Home/state gaps.
4. Add the Drone-specific count fix and one defensible Drone product UX seam.
5. Run responsive/accessibility closure, Product UX Closure, then physical-device UX evidence.

## Audit result

`PASS_WITH_BLOCKING_BACKLOG`

Baseline audit is complete. Production behavior remains unchanged. The workstream should advance to `STANDARD_UX_CONTRACT` before implementation.