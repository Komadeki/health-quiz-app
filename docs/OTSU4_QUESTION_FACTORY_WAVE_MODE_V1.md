# Otsu4 Question Factory Wave Mode v1

Status: ADOPTED
Date: 2026-08-25
Product: 危険物取扱者 乙種第4類

## 1. Purpose

Increase Production Question Bank throughput without weakening source binding, independent AI review, semantic-collision controls, AI role separation, Permanent Question ID integrity, source verification, or release gates.

This protocol is subordinate to `QUESTION_BANK_CONTRACT_V0.md`, `OTSU4_600Q_PRODUCTION_TARGET_DECISION_V1.md`, `OTSU4_600Q_PINPOINT_SOURCE_CATALOG_V1.md`, and the repository AI-governance contract. Any conflict fails closed to the stricter upstream contract.

## 2. Three-batch wave

A production wave may contain up to three authoring batches. Each batch has a maximum of 24 AI_PRE_ACCEPT candidates, so one wave has a ceiling of 72 candidates.

The ceiling is not a quota. No rejected, reworked, source-limited, or semantically redundant candidate is backfilled merely to preserve 24 or 72.

Wave authoring may run ahead across all three batches before review because no Permanent IDs, canonical rows, released rows, runtime rows, or source-verification decisions exist at AI_PRE_ACCEPT.

## 3. Wave 1

Wave 1 consists of:

- B4: `O4-FIR-KT-PROPERTIES` — up to 24 candidates using the frozen MHLW SDS/label source set.
- B5: `O4-PHY-KT-MATTER-HEAT` — up to 24 candidates using the frozen MEXT pinpoint ranges.
- B6: `O4-LAW-KT-FACILITIES-INSPECTION` — up to 24 candidates using current e-Gov Act/Decree/Rule pinpoint articles.

The canonical/source-verified baseline before Wave 1 is 51 questions.

## 4. Collision contract

Authoring must collision-check against:

1. all released questions;
2. all canonical drafts, including the 51-question Wave-1 baseline;
3. all earlier candidates in the same batch; and
4. all candidates already authored in the same wave.

Independent review re-runs semantic-collision review across the full wave. A question may be rejected even when source-correct if it adds insufficient educational value.

## 5. Review and acceptance

The independent AI reviewer remains separate from the AI author and AI Director. Human review is never fabricated.

After independent review, the following previously separate mechanical steps are combined into one fail-closed `DIRECTOR_ACCEPT_AND_PROMOTE` transaction per reviewed wave or batch:

1. Director adjudication;
2. content-bound Acceptance Packet materialization for Director-accepted candidates; and
3. promotion of those candidates to `READY_FOR_ID`.

The transaction must validate distinct author/reviewer/Director identities, exact candidate fingerprints, reviewer decisions, source evidence, collision evidence, and absence of partial packet/promotion state before commit.

A reviewer REWORK/REJECT/HOLD remains blocking and cannot be bypassed by the combined transaction.

## 6. Permanent IDs and source verification

Permanent ID allocation/canonical integration remains a separate fail-closed transaction. Source verification remains a separate gate after canonical integration. Released/runtime activation remains separate.

Wave mode never preallocates IDs and never performs source verification merely because a candidate was accepted.

## 7. CI routing

Candidate planning, AI_PRE_ACCEPT authoring, independent review, Director/acceptance metadata, acceptance packets, candidate-state promotion, and Otsu4 machine-state-only changes may use the dedicated Question Bank CI path when all non-documentation changes are confined to:

- `question_banks/otsu4/**`; and
- `tooling/komadeki_autopilot/otsu4_state.json`.

That CI path must run Otsu4 state validation, Question Bank unit tests, all Otsu4 batch expansion validators, generated-bank validation, and diff hygiene. It deliberately does not install Flutter.

Any app code, package code, generic tooling, workflow, unknown path, canonical runtime implementation, or mixed-scope change falls back to existing fail-safe CI and may run full Flutter checks.

## 8. Safety properties

Wave mode changes throughput, not quality thresholds. The following remain invariant:

- original independently authored questions only;
- no copyrighted past-question reproduction;
- exact source_id/source_version/pinpoint locator binding;
- no wording-only variants;
- no quota filler;
- independent AI review;
- distinct AI author/reviewer/Director identities;
- content-bound fingerprints;
- deterministic Permanent ID allocation only after acceptance;
- independent source verification before release;
- durable GitHub evidence required.
