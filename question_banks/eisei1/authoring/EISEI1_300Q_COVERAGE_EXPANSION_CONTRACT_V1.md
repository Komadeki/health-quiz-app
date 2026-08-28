# Eisei1 300-question Coverage Expansion Contract v1

Status: authoritative for the post-B9 coverage-expansion waves.

This contract replaces the two-lane limitation in
`EISEI1_INITIAL_TWO_LANE_CONTRACT_V2.md`.  It does not alter the shared
Question Factory, five-choice requirement, permanent-ID lifecycle, source
verification gate, generated-artifact rules, or release process.

## Scope and decision

The B2--B9 pilot has produced 16 integrated, source-verified draft questions
across the original two lanes.  The product decision is now to build a
300-question *draft* bank, first closing every required target in
`coverage.json`, then adding evidence-distinct variation.  All five official
exam units are open for authoring under the existing quality gate.

The prior two-lane restriction was a pilot throughput control, not a product
taxonomy rule.  It is superseded only for Eisei1 coverage-expansion batches.

## Gates

1. **Coverage gate (about 50 questions):** every one of the 37 required
   targets has at least one source-verified, integrated draft question.
2. **Exam gate (at least 44 questions):** a 10/10/7/7/10 mock can be compiled
   without reusing a question.  This is a functional gate, not a sales claim.
3. **Density gates (100 and 200 questions):** review category balance,
   semantic collisions, source-version drift, and answer-position distribution
   before authoring the next wave.
4. **300-question freeze candidate:** reach the target profile below, run the
   full source, collision, generated-drift, regression, Flutter-analysis, and
   Flutter-test gates.  Only then consider a `bank_revision` change.  This
   contract does not itself update it.

## 300-question target profile

| Official unit | Target |
| --- | ---: |
| 関係法令（有害業務） | 68 |
| 労働衛生（有害業務） | 68 |
| 関係法令（有害業務以外） | 48 |
| 労働衛生（有害業務以外） | 48 |
| 労働生理 | 68 |
| **Total** | **300** |

Targets are planning ceilings, not quotas.  A weak, duplicate, ambiguous, or
source-incomplete question is rejected and is never retained just to satisfy a
number.

## Batch discipline

- Author at most ten candidates per batch.
- Bind one primary knowledge target and one answer-defining proposition per
  candidate.
- Before permanent-ID allocation, run the shared expansion validator and an
  independent global collision review against every persisted Eisei1 item.
- Verify the primary source and its locator after integration; use the date of
  verification as the source version boundary.
- Inspect A--E answer distribution cumulatively and per batch.  Reorder only
  choices, never the proposition, to correct an authoring-order bias.
- Preserve draft/released separation.  Do not add a release snapshot, modify
  generated runtime data, or change `bank_revision` during the expansion.

## Stop conditions

Hold or reject a candidate if current primary law, MHLW guidance, and an
otherwise applicable source do not determine one unambiguous answer; if four
plausible same-domain distractors cannot be substantiated; or if its reasoning
path is materially equivalent to a persisted question.

## Post-300 decision evidence

The 400--500 decision is deferred until the 300-question gate records: target
variation remaining, category thinness against the official profile, measured
semantic duplication, the incremental verification/review cost, competitor
comparison, and real-user completion/incorrect-answer patterns.  No claim that
users will exhaust 300 questions may be made before that product evidence
exists.
