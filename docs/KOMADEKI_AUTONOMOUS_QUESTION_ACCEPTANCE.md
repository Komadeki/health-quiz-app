# KOMADEKI Autonomous Question Acceptance Contract v1.0

Status: **ADOPTED / LIFECYCLE BRIDGE IMPLEMENTED**

This contract governs autonomous Question Bank review for qualification-app expansion. It does not remove or rewrite legacy HUMAN review evidence. It defines a separate AI-governed path that can advance candidates to `READY_FOR_ID` only when its durable acceptance packet passes the fail-closed lifecycle bridge.

## 1. Non-negotiable identity rule

AI must never claim or synthesize `HUMAN` review. Existing human-reviewed batches remain valid historical evidence. New autonomous work uses explicit roles:

- `AI_AUTHOR` — creates the candidate and source/collision evidence.
- `AI_REVIEWER` — independently audits the candidate; must be distinct from the author.
- `AI_DIRECTOR` — adjudicates the reviewer result and is the only role that can produce the final autonomous acceptance decision; must be distinct from author and reviewer.

## 2. Acceptance sequence

`AI_PRE_ACCEPT -> independent AI review -> Director adjudication -> AI_GOVERNED_ACCEPT -> READY_FOR_ID`

`AI_GOVERNED_ACCEPT` is not equivalent to HUMAN_ACCEPT and must never be serialized as HUMAN review.

The durable packet for candidate `<candidate_id>` is stored at:

`authoring/batches/<batch>/acceptance_packets/<candidate_id>.json`

A valid packet is evidence for the AI-governed path. The candidate row itself moves from `AI_PRE_ACCEPT` to `READY_FOR_ID`; no fake Human review row is created.

## 3. Required evidence

Every autonomous candidate acceptance packet must preserve:

- candidate identity;
- authoritative `source_id`, `source_version`, and `source_locator`;
- answer-defining proposition;
- tested misconception;
- reasoning path / decision boundary;
- semantic-collision evidence against the released bank, existing canonical drafts, and the candidate batch;
- independent reviewer decision and rationale;
- Director decision and rationale;
- distinct author, reviewer, and Director identities.

The lifecycle bridge additionally binds packet source/proposition/misconception/reasoning/collision evidence back to the current candidate row. A stale or mismatched packet fails closed.

## 4. Decision rules

An autonomous candidate is accepted only when all of the following are true:

1. authoring state before promotion is `AI_PRE_ACCEPT`;
2. independent reviewer decision is `ACCEPT`;
3. Director decision is `ACCEPT`;
4. author, reviewer, and Director IDs are non-empty and pairwise distinct;
5. source evidence is complete and matches the candidate row;
6. semantic-collision checks are recorded as complete and the collision note matches the candidate row;
7. answer-defining proposition, tested misconception, and reasoning path are non-empty and match the candidate row;
8. no autonomous actor claims the `HUMAN` role;
9. the acceptance packet requests `AI_GOVERNED_ACCEPT`;
10. no unresolved HOLD/REWORK/REJECT condition exists.

A reviewer `REWORK`, `REJECT`, or `HOLD` cannot be overridden by omission. Acceptance after reviewer disagreement requires a new independent reviewer round rather than unilateral Director acceptance.

## 5. Lifecycle bridge

The existing expansion lifecycle remains backward compatible:

- genuine Human path: latest real Human `ACCEPT` review satisfies the post-accept gate;
- AI-governed path: a valid durable acceptance packet satisfies the same post-accept gate without creating a Human review record.

`tooling/question_bank/ai_governance.py` performs fail-closed packet binding and atomic promotion from `AI_PRE_ACCEPT` to `READY_FOR_ID`.

`tooling/question_bank/expansion.py` recognizes a post-accept candidate only when either:

- a genuine latest Human `ACCEPT` review exists; or
- the candidate has a valid AI-governed acceptance packet.

`QuestionExpansionTransaction` continues to allocate from accepted pre-ID states. The AI path reaches it through `READY_FOR_ID`, so permanent-ID allocation, duplicate-ID checks, partial-state detection, and rollback protections are unchanged.

## 6. Separation from source verification

Autonomous acceptance is a content-selection gate only. It does **not** satisfy canonical source verification. Existing `VERIFIED` requirements, including authoritative source/version binding, remain unchanged.

## 7. Durable evidence

Completion is recognized only when the acceptance packet is persisted on GitHub. Chat-only, browser-only, or local-only evidence is non-authoritative.

Promotion is atomic across `candidates.csv`: if any selected candidate has missing, malformed, mismatched, or non-accepted AI evidence, no selected candidate is promoted.

## 8. Legacy compatibility

Legacy batches with genuine Human review remain valid under Production Question Bank Expansion Protocol v1.0. The autonomous path is additive. Existing Human-review rows remain `reviewer_role=HUMAN`; AI evidence is kept in separate JSON packets and is never serialized as Human review.

## 9. Gate after lifecycle bridge

Once this bridge passes required CI and is merged:

- `autonomous_acceptance` may advance from `MIGRATION_REQUIRED` to `AI_GOVERNED`;
- new autonomous batches may progress from `AI_PRE_ACCEPT` to `READY_FOR_ID` through valid AI-governed acceptance;
- canonical `VERIFIED` and release gates remain unchanged.
