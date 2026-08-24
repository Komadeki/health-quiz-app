# KOMADEKI Autonomous Question Acceptance Contract v1.0

Status: **ADOPTED CONTRACT / LIFECYCLE BRIDGE PENDING**

This contract governs autonomous Question Bank review for qualification-app expansion. It does not remove or rewrite legacy HUMAN review evidence. It defines a separate AI-governed path that must be wired into the existing expansion lifecycle before it can advance candidates beyond `AI_PRE_ACCEPT`.

## 1. Non-negotiable identity rule

AI must never claim or synthesize `HUMAN` review. Existing human-reviewed batches remain valid historical evidence. New autonomous work uses explicit roles:

- `AI_AUTHOR` — creates the candidate and source/collision evidence.
- `AI_REVIEWER` — independently audits the candidate; must be distinct from the author.
- `AI_DIRECTOR` — adjudicates the reviewer result and is the only role that can produce the final autonomous acceptance decision; must be distinct from author and reviewer.

## 2. Acceptance sequence

`AI_PRE_ACCEPT -> independent AI review -> Director adjudication -> AI_GOVERNED_ACCEPT -> READY_FOR_ID`

`AI_GOVERNED_ACCEPT` is not equivalent to HUMAN_ACCEPT and must never be serialized as HUMAN review.

Before the lifecycle bridge is implemented, accepted autonomous packets remain evidence only and candidates must not be moved to `READY_FOR_ID`.

## 3. Required evidence

Every autonomous candidate acceptance packet must preserve:

- candidate identity and immutable content hash or equivalent content binding;
- authoritative `source_id`, `source_version`, and `source_locator`;
- answer-defining proposition;
- tested misconception;
- reasoning path / decision boundary;
- semantic-collision evidence against the released bank, existing canonical drafts, and the candidate batch;
- independent reviewer decision and rationale;
- Director decision and rationale;
- distinct author, reviewer, and Director identities.

## 4. Decision rules

An autonomous candidate is accepted only when all of the following are true:

1. authoring state is `AI_PRE_ACCEPT`;
2. independent reviewer decision is `ACCEPT`;
3. Director decision is `ACCEPT`;
4. author, reviewer, and Director IDs are non-empty and pairwise distinct;
5. source evidence is complete;
6. semantic-collision checks are recorded as complete;
7. answer-defining proposition, tested misconception, and reasoning path are non-empty;
8. neither review role is `HUMAN`;
9. no unresolved HOLD/REWORK/REJECT condition exists.

A reviewer `REWORK`, `REJECT`, or `HOLD` cannot be overridden by omission. The Director must explicitly adjudicate the result; acceptance after reviewer disagreement requires a new independent reviewer round rather than unilateral Director acceptance.

## 5. Separation from source verification

Autonomous acceptance is a content-selection gate only. It does **not** satisfy canonical source verification. Existing `VERIFIED` requirements, including authoritative source/version binding, remain unchanged.

## 6. Durable evidence

Completion is recognized only when the acceptance packet is persisted on GitHub. Chat-only, browser-only, or local-only evidence is non-authoritative.

## 7. Legacy compatibility

Legacy batches with genuine Human review remain valid under Production Question Bank Expansion Protocol v1.0. The autonomous path is additive. Migration must preserve all existing Human-review tests and Batch 1 evidence.

## 8. Lifecycle bridge requirement

The next repository change must connect this contract to the expansion lifecycle so that:

- the validator recognizes explicit AI-governed acceptance evidence;
- `READY_FOR_ID` can be reached through either genuine Human ACCEPT or valid AI-governed acceptance;
- transaction allocation accepts the AI-governed path without weakening ID/rollback protections;
- invalid role reuse, missing independent review, missing source/collision evidence, and fabricated Human identity fail closed;
- existing Human path behavior remains unchanged.

Until that bridge is merged, `autonomous_acceptance` remains `MIGRATION_REQUIRED` in the Autopilot machine state.
