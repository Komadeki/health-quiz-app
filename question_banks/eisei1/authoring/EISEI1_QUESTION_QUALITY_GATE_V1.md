# Eisei1 Question Quality Gate v1

Status: authoritative for all new Eisei1 candidate authoring and review.

This contract supplements the shared Question Factory and the Eisei1 bootstrap
contract. It does not fork the common schema, ID lifecycle, source-verification
rules, expansion protocol, canonical generation, or release process.

## 1. Product quality objective

Eisei1 questions SHALL train the discrimination required by the real
five-option exam. A candidate is not production-quality merely because the
correct option is legally or scientifically true.

Each candidate SHALL satisfy all of the following:

- exactly five answer choices;
- one unambiguously best answer under the stated conditions;
- four plausible distractors from neighboring propositions in the same exam
  domain;
- a current authoritative source that determines the answer;
- a concrete tested misconception or confusion;
- a reasoning path that is meaningfully distinct from persisted candidates,
  except for the bounded close-variant allowance in
  `EISEI1_COMMERCIAL_BANK_TARGET_500_V1.md`;
- an explanation that teaches why all five choices are correct or incorrect.

## 2. Distractor standard

Distractors SHALL be plausible to a learner who has studied the topic
incompletely. They SHOULD be built from errors such as:

- confusing adjacent regulatory categories, duties, frequencies or thresholds;
- applying the right rule to the wrong substance, workplace or worker class;
- reversing a control hierarchy or measurement purpose;
- confusing health effects, exposure routes, target organs or protective
  equipment;
- using a true proposition whose conditions do not match the stem;
- using a close numerical, timing, retention, frequency or exception rule when
  the authoritative source supports that distinction.

Distractors SHALL NOT be padded with obviously unrelated business concepts,
advertising, sales, customer metrics, arbitrary administrative acts, or other
options that can be rejected without knowing occupational health or law.

If four credible distractors cannot be supported, the candidate SHALL be
reworked or rejected rather than filled to a quota.

## 3. Answer-position control

Correctness is determined only by the underlying proposition. Reviewers SHALL
NOT change the correct proposition to improve answer-position balance.

Before a batch is promoted, answer positions SHALL be inspected for obvious
bias. A batch in which one answer letter dominates because the author always
places the correct proposition first SHALL be REWORKED by reordering choices
without changing their meaning or the answer-defining proposition.

All A-E positions are valid and SHALL be exercised over time.

## 4. Five-choice explanation standard

The canonical `explanation` field SHALL teach all five options without adding a
qualification-specific schema fork. A production-ready explanation SHOULD use
compact A-E reasoning and SHALL state, for each option, one of:

- why the proposition is correct under the stem;
- why it is incorrect; or
- the condition under which the otherwise true proposition would become
  correct.

A one-sentence restatement of the correct answer is insufficient for promotion.

## 5. Lane A: 関係法令（有害業務）

A Lane A candidate SHALL materially depend on an hazardous-work condition or a
rule that belongs to hazardous-work regulation. Generic appointment, patrol,
or general health-management rules belong in the general-law lane unless the
hazardous-work condition changes the legal conclusion being tested.

Preferred proposition families include, where supported by current primary
law:

- 特定化学物質障害予防規則;
- 有機溶剤中毒予防規則;
- 鉛中毒予防規則;
- 粉じん障害防止規則;
- 酸素欠乏症等防止規則;
- 電離放射線障害防止規則;
- 石綿障害予防規則;
- 作業環境測定, records, evaluation and responsive measures;
- 特殊健康診断 and post-examination measures;
- hazardous-work qualification, education and labor restrictions;
- chemical labeling, SDS and risk-management duties.

Legal, numeric, timing, exception and retention propositions require an exact
current article, paragraph, item, table or appendix locator before acceptance.

## 6. Lane B: 労働衛生（有害業務）

Lane B SHALL test occupational-hygiene understanding, not recognition of a law
article against obviously non-health concepts.

Preferred proposition families include:

- state of matter and exposure routes;
- substitution and engineering / administrative / PPE control hierarchy;
- organic-solvent and specific-chemical health effects;
- metals and metal compounds;
- dust, pneumoconiosis and asbestos;
- oxygen deficiency, hydrogen sulfide and carbon monoxide;
- noise and vibration;
- ionizing and non-ionizing radiation;
- heat, cold and high-pressure environments;
- respiratory and other occupational protective equipment;
- work-environment, personal-exposure and biological monitoring.

Health-effect or control-method claims SHALL cite a current primary or current
MHLW authoritative source with a precise locator.

## 7. Source and published-question rules

Correctness hierarchy remains:

1. current e-Gov primary statutes, orders and regulations;
2. current MHLW authoritative materials where the proposition is not fully
   determined by legal text;
3. Safety and Health Examination Association published questions only for exam
   style, coverage and distractor signals.

Published-question wording SHALL NOT be copied into production candidates.
Published questions SHALL NOT be used as the sole authority for a current-law
conclusion.

## 8. Coverage and collision gate

Authoring follows coverage before candidates. The first two open lanes use the
granular targets in `coverage.json`; broad bootstrap targets SHALL NOT be used
as a substitute for proposition-level planning.

Every candidate SHALL be checked against:

- all canonical Eisei1 questions;
- all persisted candidates in both open lanes;
- candidates under review in the same wave.

A paraphrase, answer-order permutation, or stem-context relabeling of an
existing proposition is a collision. The only close variants allowed by
`EISEI1_COMMERCIAL_BANK_TARGET_500_V1.md` must change the answer-defining
proposition, tested condition, misconception, or reasoning path.

## 9. Difficulty and variation

A production bank SHALL not collapse into definition recall. Across accepted
questions, the factory SHOULD deliberately mix:

- direct factual discrimination;
- condition/application questions;
- correct/incorrect statement selection;
- combination questions where appropriate;
- exception questions;
- numeric, frequency, timing or retention distinctions where authoritative;
- cause/effect and control-method reasoning.

Variation SHALL be evidence-driven. Artificial complexity that is unlike the
exam is not a quality improvement. The 500-question commercial target permits
additional easier and close-variant items when they meet the collision rule
above; it does not permit wording-only filler.

## 10. Batch discipline

Candidate count is always a ceiling, never a quota. Review may accept fewer
than planned, and no rejected slot is backfilled merely to reach a count.

No permanent question ID is allocated before acceptance. No canonical row,
release snapshot or runtime artifact changes until the normal shared gates
authorize them.

## 11. Promotion gate

A candidate may advance only when all applicable checks PASS:

1. authoritative proposition and locator;
2. exact five-choice integrity;
3. plausible distractors;
4. no answer-position authoring bias at batch level;
5. all-five-choice explanation;
6. correct lane and granular coverage binding;
7. global collision review;
8. distinct misconception / reasoning path;
9. no copied published-question wording;
10. shared expansion validation and regression checks.

Failure of any item is REWORK or REJECT, not a reason to relax the gate.
