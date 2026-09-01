# Eisei1 Initial Two-Lane Authoring Contract v2

Status: authoritative for the next Eisei1 authoring wave.

This contract supersedes `EISEI1_INITIAL_TWO_LANE_CONTRACT_V1.md` for future
candidate authoring. V1 remains historical evidence of the bootstrap state.

Upstream quality gate:

- `EISEI1_QUESTION_QUALITY_GATE_V1.md`
- `docs/EISEI1_QUESTION_FACTORY_BOOTSTRAP_V1.md`
- shared Production Question Bank Expansion Protocol

Only two units are open for this historical replacement pilot:

- Lane A: `eisei1_law_hazardous`
- Lane B: `eisei1_hygiene_hazardous`

The remaining three exam units stay coverage-mapped but closed for candidate
authoring in this wave. `EISEI1_COMMERCIAL_BANK_TARGET_500_V1.md` supersedes
that closure for subsequent waves: all five coverage-mapped units are eligible
for source-first planning, while each atomic wave may open no more than two
bounded coverage ranges.

## 1. Purpose of the replacement pilot

The prior Batch 1 proposal was rejected at Director Gate because CI-valid data
was not yet commercially useful question content: distractors were often
obviously irrelevant, answer position was uniformly A, several Lane A items
were generic rather than hazardous-work-specific, Lane B items overused trivial
statutory-category recognition, and explanations did not teach all five
choices.

This wave therefore tests question quality and review throughput before the
subsequent 500-question commercial-bank execution waves.

## 2. Initial curated coverage

The first replacement pilot SHALL author only from the following granular
targets unless a target is explicitly added by a later repository-resident
coverage decision.

### Lane A — 関係法令（有害業務）

- `E1-LH-003` 特定化学物質障害予防規則
- `E1-LH-004` 有機溶剤中毒予防規則
- `E1-LH-006` 粉じん障害防止規則
- `E1-LH-007` 酸素欠乏症等防止規則
- `E1-LH-010` 作業環境測定・評価・記録

### Lane B — 労働衛生（有害業務）

- `E1-HH-002` 有害性低減の優先順位
- `E1-HH-003` 有機溶剤の健康影響
- `E1-HH-006` 粉じん・じん肺・石綿
- `E1-HH-007` 酸素欠乏・硫化水素・一酸化炭素
- `E1-HH-013` 労働衛生保護具

These targets were selected because they support authentic hazardous-work
reasoning, have current authoritative source paths, and provide enough
variation to test distractor quality without broadening beyond two lanes.

## 3. Candidate ceiling

The replacement pilot has a maximum of 10 candidates:

- Lane A: at most 5;
- Lane B: at most 5.

Ten is not a quota. One strong candidate per listed target is the preferred
starting shape, but a target may produce zero candidates when four credible
distractors or an exact source locator cannot be established.

No slot is backfilled solely to reach ten.

## 4. Source requirements

Lane A uses exact current e-Gov primary-law locators. Relevant registered
sources include the specific hazardous-work regulations in `sources.json`, not
only the umbrella Occupational Safety and Health Act / Ordinance.

Lane B health-effect and control propositions use current primary or current
MHLW authoritative evidence with precise locators. A legal duty within Lane B
still requires the relevant primary legal source.

The Safety and Health Examination Association material is used only to tune
exam style, topic emphasis and plausible distractor structure. Its wording is
not copied and it is not the sole authority for current law.

## 5. Authoring constraints

Every candidate SHALL:

- have exactly five choices;
- bind exactly one primary knowledge target and one answer-defining
  proposition;
- use four plausible same-domain distractors;
- record a tested misconception and distinct reasoning path;
- explain A through E in the existing explanation field;
- use the exact source locator that determines the answer;
- pass global collision review across canonical and persisted candidates;
- avoid systematic answer-position bias across the batch.

A candidate that cannot satisfy these constraints is rejected rather than
simplified into an easy item.

## 6. Difficulty mix for the pilot

Across the accepted pilot set, prefer a mix of:

- direct but close factual discrimination;
- condition/application reasoning;
- rule-to-workplace or substance matching;
- health-effect / exposure / control matching;
- frequency, measurement, equipment or exception distinctions when supported.

Do not force every structure into the first ten questions. The objective is to
measure whether the quality gate reliably produces exam-like, teachable items.

## 7. Gate sequence

1. Author pre-ID candidates only.
2. Run shared expansion validation.
3. Run independent content-quality review against
   `EISEI1_QUESTION_QUALITY_GATE_V1.md`.
4. REWORK or REJECT weak distractors, source ambiguity, collisions, lane
   mismatch, answer-position authoring bias or incomplete five-choice
   explanations.
5. Allocate permanent IDs only to accepted candidates through the shared gate.
6. Verify canonical sources before release readiness.

No candidate in this pilot is entitled to acceptance because a validator or CI
passes.

## 8. Next-wave decision

After this pilot, the Director evaluates:

- acceptance / rework / rejection rates;
- source-verification burden;
- collision rate;
- distractor-quality failures;
- coverage gaps;
- reasoning and difficulty variation;
- all-five-choice explanation quality.

Only then may the next two-range wave be opened or the granular coverage be
adjusted. The commercial bank-size planning range does not create an authoring
quota.
