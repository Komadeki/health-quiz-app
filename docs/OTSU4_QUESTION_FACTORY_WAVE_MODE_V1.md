# Otsu4 Question Factory Wave Mode v1

Status: ADOPTED
Date: 2026-08-25
Amended: 2026-08-26
Product: 危険物取扱者 乙種第4類

## 1. Purpose

Increase Production Question Bank throughput without weakening source binding, independent AI review, semantic-collision controls, AI role separation, Permanent Question ID integrity, source verification, or release gates.

This protocol is subordinate to `QUESTION_BANK_CONTRACT_V0.md`, `OTSU4_600Q_PRODUCTION_TARGET_DECISION_V1.md`, `OTSU4_600Q_PINPOINT_SOURCE_CATALOG_V1.md`, and the repository AI-governance contract. Any conflict fails closed to the stricter upstream contract.

## 2. Two-range wave — effective from Wave 5

Beginning with the next newly planned production wave after Wave 4, one wave may contain **up to two coverage ranges**, implemented as up to two authoring batches.

Each batch has a maximum of 24 AI_PRE_ACCEPT candidates, so a newly planned wave has a ceiling of 48 candidates.

The ceiling is not a quota. No rejected, reworked, source-limited, or semantically redundant candidate is backfilled merely to preserve 24 or 48.

Wave authoring may run ahead across both selected ranges before review because no Permanent IDs, canonical rows, released rows, runtime rows, or source-verification decisions exist at AI_PRE_ACCEPT.

The two ranges must be selected from the highest-value remaining coverage gaps using, in order: exam relevance, current canonical coverage gap, authoritative-source reproducibility, and expected non-duplicate educational value. There is no requirement to force one range from every exam subject in each wave.

## 3. Historical three-range waves remain valid

Waves 1 through 4 were planned under the prior three-batch ceiling. Their durable authored, reviewed, accepted, canonical, and source-verification evidence remains valid and is not retroactively discarded or re-reviewed solely because of this amendment.

In particular, Wave 4 already completed independent review with 35 accepted candidates. Those accepted candidates remain eligible for the existing post-review integration path. This amendment changes **future new authoring**, not already completed review decisions.

Historical Wave 1 consisted of:

- B4: `O4-FIR-KT-PROPERTIES` — up to 24 candidates using the frozen MHLW SDS/label source set.
- B5: `O4-PHY-KT-MATTER-HEAT` — up to 24 candidates using the frozen MEXT pinpoint ranges.
- B6: `O4-LAW-KT-FACILITIES-INSPECTION` — up to 24 candidates using current e-Gov Act/Decree/Rule pinpoint articles.

The canonical/source-verified baseline before Wave 1 was 51 questions.

## 4. Collision contract

Authoring must collision-check against:

1. all released questions;
2. all canonical drafts;
3. all earlier candidates in the same batch; and
4. all candidates already authored in the same wave.

Independent review re-runs semantic-collision review across the full wave. A question may be rejected even when source-correct if it adds insufficient educational value.

Reducing a wave from three ranges to two does not weaken collision checking; it deliberately reduces the simultaneous review surface so duplicate and low-value variants are easier to detect.

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

## 7. CI and execution routing

Candidate planning, AI_PRE_ACCEPT authoring, independent review, Director/acceptance metadata, acceptance packets, candidate-state promotion, and Otsu4 machine-state-only changes may use the dedicated Question Bank validation path when permitted by the current owner execution policy.

The owner direction recorded on 2026-08-26 prohibits relying on GitHub Actions for subsequent Otsu4 transitions. Therefore Otsu4 transitions must use direct/local deterministic validation and durable GitHub evidence without treating an Actions run as completion evidence unless the owner later changes that direction.

Any app code, package code, generic tooling, canonical runtime implementation, or mixed-scope change remains fail-safe and must receive validation appropriate to its actual scope.

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
