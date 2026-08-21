# Production Question Bank Expansion Protocol v1.0

This protocol governs the pre-ID authoring lifecycle used to expand an existing qualification question bank. It is additive to, and does not redesign, the canonical Question Factory pipeline.

```text
Official Source
  -> Coverage / Knowledge Target
  -> pre-ID expansion batch
  -> Permanent ID Gate
  -> canonical Question
  -> validator
  -> generator
  -> generated runtime
```

Canonical `questions.csv`, permanent question identity, ID registry status, `coverage.json`, source verification, generation, and runtime contracts remain unchanged.

## Expansion trigger and target-size decision history

An expansion batch exists only after a Human decision to investigate or execute bank expansion. Bank-size decisions are recorded in `batch.json.target_size_decisions` as append-only history. Each decision records `decision_id`, `previous_approved_target`, `current_released_count`, `proposed_target_min`, `proposed_target_max`, `approved_new_target`, `rationale`, `decision_date`, and `evidence`.

`approved_new_target` records the approved target after that decision and may equal the previous target when an exploratory expansion does not change the canonical approved target. Candidate counts are always derived from `candidates.csv`; they are never stored as authoritative summary counts. A drafting instruction such as “+75” is not itself a quota or an approved bank-size decision.

## Standard batch artifact

Each batch uses:

```text
question_banks/<app_key>/authoring/batches/<directory_slug>/
  batch.json
  candidates.csv
  reviews.csv
```

`batch_id` is the stable logical identity. A directory slug may differ only when an existing repository convention makes that clearer; the mapping must be explicit in `batch.json` and must not create another identity layer.

## Candidate lifecycle

Allowed candidate states are:

`DRAFT`, `AI_PRE_ACCEPT`, `HUMAN_ACCEPT`, `READY_FOR_ID`, `ID_ALLOCATED`, `INTEGRATED`, `VERIFIED`, `RELEASED`, `REWORK`, `HOLD`, and `REJECT`.

Candidate IDs are unique within a qualification/batch. A rejected candidate ID is a tombstone for that batch and must not be reused. Candidate rows remain in the artifact after Permanent ID allocation and production integration.

`candidates.csv` columns are:

```text
candidate_id,state,unit_id,domain,knowledge_target_id,family,question,
choice1,choice2,choice3,choice4,proposed_correct,explanation,source_id,
source_version,source_locator,answer_defining_proposition,tested_misconception,
reasoning_path,collision_note,permanent_question_id
```

`unit_id` is the shared canonical parent. `domain` and `knowledge_target_id` may carry qualification-specific metadata. Shared validation must not encode Drone-specific taxonomy.

For pre-ID states, `permanent_question_id` is empty. A Permanent ID appears only at `ID_ALLOCATED` or a later production state.

## Persistence invariant

Persistence is an invariant, not a state. There is no `PERSISTED_DRAFT` state.

A candidate at `AI_PRE_ACCEPT` or later must exist in the repository artifact. A `DRAFT` that must survive a Chat, model, or reviewer transition must also be persisted before that transition. Chat memory is never the Source of Truth.

## Human Review

`reviews.csv` is append-only and contains:

```text
candidate_id,review_round,decision,reason_code,reason_detail,
collided_question_id,collided_candidate_id,reviewed_at,reviewer_role,resume_condition
```

Human decisions are `ACCEPT`, `REWORK`, `REJECT`, and `HOLD`. The latest review must agree with the candidate’s current Human-review state.

Legacy migration may use an empty `reviewed_at` when no exact timestamp exists in the authoritative packet. `reviewer_role=HUMAN` is sufficient when the exact individual identity was not recorded. A timestamp or person must never be inferred.

## REJECT and HOLD

A `REJECT` review requires a non-empty reason code or reason detail. A `HOLD` review requires both a reason and a non-empty `resume_condition`. Rejected IDs remain non-reusable even when the legacy question packet is unavailable.

When an exact legacy packet is unavailable, do not fabricate a Question row. Record the missing identity as migration evidence/blocker in `batch.json` rather than weakening `candidates.csv` into a placeholder format.

## Coverage Limit

A Coverage Limit is a Human/AI evidence decision that a requested allocation cannot be safely filled from the current source/construct boundary. It is recorded in `batch.json.coverage_limit_decisions`. The shared validator checks structure and evidence presence only; it does not hard-code target names or declare semantic sufficiency.

## Semantic duplicate boundary

Deterministic validation may check IDs, mappings, fields, and declared collision references. It must not claim that two Questions are semantically distinct or materially duplicated. Semantic collision remains an AI-assisted and Human-decided judgment.

## Permanent ID Gate

Permanent IDs are allocated only after a candidate has passed the batch’s Human and coverage gates and reaches `READY_FOR_ID`. Allocation moves the candidate to `ID_ALLOCATED` and records the permanent ID on the same row. The canonical registry remains the sole permanent allocation ledger; this protocol adds no `reserved` registry state.

## Production Integration Gate

`ID_ALLOCATED` is not release. Canonical authoring, source verification, canonical validation, generation, and release controls remain the production integration path. `INTEGRATED`, `VERIFIED`, and `RELEASED` describe progress through those existing gates; they do not replace them.

## Batch checkpoint / PR and resumption

A batch is checkpointed through repository commits/PRs. The persisted batch artifacts are sufficient to resume work without relying on Chat history. A status report is derived from `batch.json`, `candidates.csv`, and `reviews.csv`; summary counts are not hand-maintained files.

The report includes batch identity/status, current target decision, counts by state, Human ACCEPT/REJECT/HOLD counts, production-state counts, blockers, and next actionable states.

## Multi-qualification applicability

The protocol is shared across qualification apps. Qualification-specific `domain`, target labels, source semantics, and coverage-limit evidence remain data. The shared validator validates structure and lifecycle invariants only.
