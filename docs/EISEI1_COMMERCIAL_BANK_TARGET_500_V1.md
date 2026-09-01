# Eisei1 Commercial Bank Target 500 v1

Status: ACTIVE — explicit Product Direction.

Product: 第一種衛生管理者 (`eisei1`)

Decision date: 2026-09-02

## 1. Authoritative decision

The commercial Eisei1 bank target is fixed at **500 accepted and
source-verified canonical questions**.

This owner decision supersedes the deferred/final-size language in the Eisei1
bootstrap and initial-two-lane contracts. It does not change the definition of
an accepted question, authorize quota filling, or authorize release activation.

The durable execution state is
`tooling/komadeki_autopilot/eisei1_state.json`. Issue #40 remains the project
control record; its Drone physical-device blocker applies only to the Drone
release line and does not block Eisei1 Question Bank Completion.

## 2. Quality policy

The following gates remain mandatory for every question:

- correctness and one unambiguously best answer;
- current authoritative source grounding with an exact answer-determining
  locator;
- exactly five choices and five-choice explanation;
- deterministic shared-factory validation and regression checks;
- canonical source verification before counting toward the 500 target; and
- global collision review that prevents catastrophic duplicates.

The factory may use a wider variety of granular coverage, close variants,
easier questions, and repeated high-value concepts **only** where each item
has a distinct answer-defining proposition, tested condition, misconception,
or reasoning path. The following remain collisions and must be rejected:

- the same answer-defining proposition with only stem wording changed;
- a choice-order permutation of an existing question; or
- a context relabel that does not change the knowledge discrimination.

The prior requirements for maximally diverse difficulty mix and materially
distinct reasoning paths across every related item are relaxed only to this
extent. Plausible same-domain distractors, source precision, and explanation
quality are not relaxed.

## 3. Operating route

Use the lightest capable authoring/review route by default. Escalate to a
standard model only for ambiguous legal interpretation, conflict among current
authoritative sources, or repeated deterministic-validator/reviewer failure.
Pro is not required.

Eisei1 continues one atomic transition at a time:

1. author or review one bounded non-quota batch;
2. materialize only accepted content-bound acceptance packets;
3. allocate and integrate only accepted candidates;
4. source-verify the exact canonical bindings; and
5. update the durable Eisei1 state to the next single transition.

No batch count is a quota. A batch that cannot produce supported, non-
catastrophically-duplicative candidates may be smaller or zero; follow-up
coverage is then expanded or subdivided rather than padding the batch.

## 4. Completion criterion

Question Bank Completion for this direction requires exactly 500 canonical
questions that have passed the normal acceptance and source-verification
gates. Release, runtime, free/premium, and bank-revision changes remain
separate explicit gates.
