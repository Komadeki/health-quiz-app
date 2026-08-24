# KOMADEKI UI/UX Product Closure Exit Verification

Date: 2026-08-25
Verified production baseline: `ee53619b1fa0c5761eaec4c82588baef6c910546`
Control issue: #48
Workstream: `qualification_factory_ui_ux`
Objective: `VERIFY_PRODUCT_UX_CLOSURE_EXIT_CRITERIA`
Result: `PASS`

## Scope reconciliation

The durable UI/UX state entered `PRODUCT_UX_CLOSURE` with `observed_main` at
`efcef3317959f5d9929659d0ce6781511b1112cd`. Current GitHub `main` has since
advanced to `ee53619b1fa0c5761eaec4c82588baef6c910546` through the separate Drone
Question Bank / product-closure workstream.

That concurrent work activated the already-governed Drone Production Bank from
100 to 188 questions, updated its generated/runtime asset and the Drone
production-controller count assertions, reconciled product documentation, and
advanced the separate Drone machine state. The completed one-shot activation
workers were subsequently removed. The current diff from the UI/UX production
gate baseline contains no changes to `packages/qualification_app` production
UI, its widget/controller tests, or the Drone Home product-seam composition.

This verification therefore re-evaluates Product UX Closure against the current
188-question production state rather than carrying forward stale assumptions.
It does not alter Question Bank authoring, acceptance, Permanent IDs, released
content, runtime content, or `tooling/komadeki_autopilot/drone_state.json`.

## Product closure gate

### Shared learner journey — PASS

The shared Factory provides a coherent Home -> learn -> feedback/result -> Home
loop with the following durable behavior:

- Home exposes a deterministic primary learning action instead of treating every
  feature as equal priority: resumable session, incorrect review,
  recommendation, unanswered/start learning, then secondary modes.
- Unit and standard-practice discovery remain available below that primary
  action, with unavailable modes disabled and accompanied by stable reason copy.
- Practice answer commit is immutable for the attempt and explicitly shows
  correctness, the learner's recorded answer, the correct answer, explanation,
  and source provenance when present.
- Active mock exam records and locks answers without exposing correctness,
  correct answers, explanation, or provenance before completion.
- Completed mock exam has a read-only review surface with recorded answer,
  correct answer, explanation, and provenance; retry starts a separate attempt.
- Practice can intentionally return Home without completing the session, and
  Home promotes `続きから`. Timed mock leave explicitly warns that wall-clock
  time continues and resume preserves the original deadline semantics.

Relevant durable gates include `home_primary_action_test.dart`,
`practice_empty_state_test.dart`, `practice_feedback_test.dart`,
`mock_exam_feedback_boundary_test.dart`, `mock_exam_review_test.dart`, and
`session_leave_resume_test.dart`.

### Progress, weakness, recommendation, and history coherence — PASS

- Progress counts completed unique questions and shows completion/count/attempt
  context without making unsupported pass-probability or real-exam-ability
  claims.
- Weakness remains intentionally unit-level for Factory v1 and reports a
  transparent recent-correctness/attempt summary.
- Recommendation is deterministic and is also promoted into the Home primary
  action when eligible, so the metric can lead directly to a learning action.
- History preserves completed sessions, keeps pass/fail absent where the exam
  profile has no pass rule, and does not confuse an intentionally paused active
  session with completion.

The remaining richer knowledge-target and history-detail ideas remain P2
backlog, not Product UX Closure blockers.

### Purchase, restore, and failure behavior — PASS

- Free and full-unlock access remain configuration-driven.
- The Home purchase surface exposes the current authoritative total from the
  loaded runtime bank, purchase state, and `購入を復元`.
- Purchase and restore share the common Factory purchase coordinator and durable
  entitlement cache; controller coverage verifies both paths unlock the mock
  exam.
- Store unavailability does not block free learning. Expected store/purchase
  failures are mapped to stable learner-facing status copy and unknown internal
  messages are replaced by a generic safe message.
- Loading has readable semantic status. Fatal load state does not expose raw
  exception text and offers support only when a support URL actually exists.
- External-link failure is nonfatal and does not discard local learning state.

### Claims and source trust — PASS

The production Factory still forbids unsupported pass probability, AI
pass/fail judgement, `本番力`, invented pass rules, and official-endorsement
claims. Drone's mock profile remains 50 questions / 30 minutes with no configured
overall or section pass rule, so its result correctly renders a reference score
without `合格` / `不合格` judgement.

Question source provenance is shown only after practice commit or in completed
mock review. Missing title/version/section fields are omitted without placeholder
noise.

### Drone-specific product differentiation — PASS

Drone remains a thin Factory composition. Its production bootstrap delegates to
`QualificationProductionBootstrap` and adds one Home supplement through the
shared optional seam; it does not fork the controller, persistence, selection,
purchase, quiz, or result runtime.

The supplement is tied to defensible qualification context rather than cosmetic
duplication: it presents the configured official-source context and a learning
path that leads from unit/review work to this app's configured mock profile.
The 50-question / 30-minute mock values are derived from the manifest exam
profile, while the Home question total is derived from the current runtime bank.
Current Drone controller coverage verifies 188 total questions, 20 free
questions, four units, and a 50-question mock sequence after full unlock.

### Accessibility and responsive closure remains valid — PASS

The previously adopted accessibility/responsive gates remain in the current
shared implementation and were not changed by the intervening Question Bank
transition. Durable tests cover:

- 320 logical-pixel compact width;
- 2.0x text scaling;
- long Japanese question and choice content;
- scroll reachability of essential actions;
- timed-mock progress/remaining-time header;
- Home, Unlock, Quiz, Result, and mock-review overflow checks;
- semantic live regions for loading and feedback;
- textual correctness feedback rather than color-only state;
- standard Material controls for essential touch targets.

The Drone-specific Home supplement is independently covered at the same compact
width and text scale.

### Architecture boundary — PASS

`packages/qualification_app` remains qualification-neutral and its dependency
boundary test rejects Drone/Health identity in shared production code. Drone has
one production composition file and no `DroneProductionController`. This remains
consistent with `QUALIFICATION_APP_FACTORY.md`, `ADDING_QUALIFICATION_APP.md`,
and `MONOREPO.md`.

## Backlog disposition

All accepted P0 and P1 findings in
`tooling/komadeki_ui_ux_autopilot/backlog.json` are closed on current production
main. No Product Closure audit finding reopens a P0 or P1.

The following P2 findings remain intentionally open and do not block this exit:

- `UX-P2-001` — optional knowledge-target seam for finer weakness UX;
- `UX-P2-002` — inspectable history/detail reuse;
- `UX-P2-003` — learner-facing terminology normalization, including remaining
  mixed terms such as `解説（Explanation）` and `Full Unlock`;
- `UX-P2-004` — further connect progress presentation to action.

Their current impact is product polish or future depth rather than a broken core
learner flow, incorrect exam semantics, inaccessible essential action, unsafe
claim, or architecture violation. They may be scheduled after the blocking
closure path without changing this decision.

## CI and merge gate

This exit record and the accompanying state transition are documentation/control
plane only. They change no production behavior. Merge is permitted only after:

1. the PR is based on the latest GitHub `main` and remains non-stale;
2. changed files are limited to this exit record and the UI/UX machine state;
3. `Quiz Apps CI` passes every scope required by repository detection;
4. `KOMADEKI UI UX Autopilot State` validates the new machine state and diff
   hygiene;
5. there is no concurrent Question Bank change that makes the audited product
   baseline stale.

## Exit decision

`PRODUCT_UX_CLOSURE` exit criteria are satisfied on the current production
baseline. Advance the UI/UX Autopilot to `PHYSICAL_UX`.

Next atomic objective: `VERIFY_PHYSICAL_UX_EVIDENCE`.
