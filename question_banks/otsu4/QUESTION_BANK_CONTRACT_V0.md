# Otsu4 Question Bank Contract v0

## Lifecycle

All Otsu4 candidates use the Factory lifecycle and the AI-governed path in `docs/KOMADEKI_AUTONOMOUS_QUESTION_ACCEPTANCE.md`:

`AI_PRE_ACCEPT → independent AI review → Director adjudication → AI_GOVERNED_ACCEPT → READY_FOR_ID`.

Author, reviewer, and Director identities must be distinct. No candidate may claim HUMAN review. Acceptance packets, source verification, permanent-ID allocation, release, and runtime generation use the existing Factory tooling without a fork.

## Source binding

Each candidate must cite one source from `docs/OTSU4_PRODUCT_SPEC_V0.md` by source ID, source version/effective date, and precise locator. O4-EXAM-1 may establish exam format only; it cannot supply copied question text. Legal claims use the current applicable law/regulation source. A changed source requires re-verification before release.

## Coverage taxonomy

Every candidate has one primary subject and one knowledge target:

| Subject | Prefix | Required target families |
| --- | --- | --- |
| 法令 | `O4-LAW` | classification/quantity, licensing/duties, storage/handling, facilities/inspection, transport |
| 物化 | `O4-PHY` | matter/heat, combustion, concentration, chemical change, calculation boundary |
| 性消 | `O4-FIR` | Class 4 properties, flash/ignition, hazards/prevention, extinguishing suitability, incident decision |

Each target must carry variation tags for `recall`, `application`, or `calculation_decision`; calculation/decision questions also record their tested misconception and reasoning boundary. A candidate cannot bind to multiple primary subjects merely to satisfy coverage.

## Initial batch gate

Batch 1 may contain at most 20 original candidates: 8 Law, 5 Physics/Chemistry, and 7 Properties/Fire. It must include at least two calculation/decision candidates per subject and no released, canonical-draft, or same-batch semantic collision. Passing Batch 1 does not change the 300-question product target or authorize a mock-exam release.
