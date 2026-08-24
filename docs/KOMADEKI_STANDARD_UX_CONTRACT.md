# KOMADEKI Qualification Factory Standard UX Contract v1.0

Adopted baseline: `65d7df42a0ad4c501350917ca055832ffb9475e2`
Workstream: `qualification_factory_ui_ux`
Control issue: #48

## Purpose

This contract converts the UI/UX baseline audit into deterministic product behavior that autonomous implementation can test. Shared behavior belongs in `packages/qualification_app` unless it is UI-independent engine logic. Qualification-specific presentation stays thin and must not fork shared controllers, persistence, selection, purchase handling, or standard screens.

## 1. Session lifecycle

### Practice

- An active practice session must expose an intentional leave-to-Home action.
- Leaving practice preserves the active session and committed responses.
- Home must make `続きから` the highest-priority action while a resumable session exists.
- Returning Home is not session completion and must not create history or score records.

### Timed mock exam

- A timed mock may be left and resumed, but its wall-clock deadline never pauses.
- Any leave action must make that consequence explicit before leaving.
- Resume computes remaining time from the persisted start/deadline semantics, not from time spent foregrounded.
- If the deadline expires while away, the existing deterministic expiration/completion path remains authoritative.

## 2. Practice feedback

After a practice answer is committed:

- the response is immutable for that attempt;
- correctness is stated in text and not by color alone;
- the selected answer and correct answer are explicitly distinguishable;
- explanation is shown when available;
- source provenance is shown when available;
- the learner has one obvious next-question action.

## 3. Mock-exam semantics

During an active mock exam:

- committing an answer must not reveal correctness;
- it must not reveal the correct answer;
- it must not reveal explanation or source provenance;
- the committed answer remains immutable;
- progress and remaining time may be shown;
- the next-question action must remain obvious.

After completion, score/pass output follows the configured exam profile only. The runtime must never invent a pass rule. A completed mock-review surface may show recorded answer, correct answer, explanation, and source, but it must be read-only and must not mutate the completed attempt. Retry is a new attempt.

## 4. Empty and unavailable actions

- No enabled learning action may fail silently.
- When eligibility is knowable before tap, prefer an unavailable/disabled affordance with concise reason text.
- When eligibility changes asynchronously or is discovered only after action, show a stable nonfatal status message.
- Empty `incorrect` and `unanswered` selections are normal product states, not fatal errors.
- Store unavailability must not block free learning.

## 5. Home primary-action precedence

Home must guide rather than present every feature as equal priority. The reusable precedence is:

1. resumable active session;
2. eligible incorrect-answer review when incorrect items exist;
3. deterministic recommendation/weakness-driven unit action when available;
4. unanswered/start-learning action;
5. secondary unit/practice/mock/history choices.

Purchase is a product surface, not the default primary learning action. Secondary modes remain discoverable without competing visually with the current primary action.

## 6. Source-aware explanation

`QuizCard.sourceTitle`, `sourceVersion`, and `sourceSection` are the reusable provenance seam.

- Practice may show provenance only after answer commit.
- Mock exam may show provenance only after mock completion in review.
- Render only fields that are present; missing fields produce no placeholder noise.
- Source display must not imply official endorsement.
- Qualification-specific source terminology may be configured/composed, but the underlying component is shared.

## 7. Loading, errors, and status

- Loading has a user-readable semantic status, not an unlabeled spinner only.
- Raw exception text is not learner-facing production copy.
- Fatal data-load failures use stable user copy and a recovery action only where recovery is actually supported.
- Expected nonfatal conditions use one consistent status/message mechanism.
- Error/status presentation must never discard valid local learning state.

## 8. Accessibility and responsive gates

Before Product UX Closure, shared surfaces must pass widget gates covering:

- compact phone width of 320 logical pixels;
- text scaling at 2.0x;
- long Japanese question and choice fixtures;
- scroll reachability of all essential actions;
- mock header usability with progress and remaining time;
- no render overflow on Home, Quiz, Result, Unlock, or review surfaces;
- semantic labels for essential controls and live feedback/state changes;
- correctness not conveyed by color alone;
- touch targets provided by standard Material controls unless a custom control proves equivalent accessibility.

## 9. Product claims and metrics

- Do not display unsupported pass probability, AI pass/fail judgment, `本番力`, or official endorsement claims.
- Metrics should lead to a useful learner action; avoid adding decorative dashboards before core actions are clear.
- A missing configured pass rule is represented explicitly as no pass/fail judgment.

## 10. Qualification-specific UX boundary

A qualification-specific UX addition is accepted only when it is tied to a defensible qualification difference such as official terminology, exam structure, source presentation, learning path, or domain-specific explanatory context.

Cosmetic duplication is not sufficient. Reusable requirements must be implemented once in the Factory. Drone-specific UX should compose shared contracts rather than create a separate runtime.

## 11. Implementation order

The first blocking implementation sequence is:

1. `UX-P0-001` — enforce mock feedback boundary;
2. `UX-P0-002` — intentional leave/Home/resume semantics;
3. `UX-P0-003` — eliminate silent no-op practice actions.

After all P0 findings close, proceed through accepted shared P1 findings before Drone-specific P1 work, unless a dependency requires a paired transition.

## Acceptance

This contract is the behavioral authority for subsequent UI/UX Autopilot implementation. A later transition may amend it only through durable GitHub evidence and explicit rationale. Production behavior is not changed by adopting this contract.
