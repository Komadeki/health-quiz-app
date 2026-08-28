# Eisei1 400-Question Independent AI Review v1

Date: 2026-08-28

Branch: `codex/eisei1-b9-integration`

Status: AI-reviewed content-freeze candidate; production freeze and release are not executed.

## Decision

The 400-question authoring bank is suitable as a content-freeze candidate after
the independent-review corrections described below.  This decision does not
activate the bank, update `bank_revision`, publish generated runtime content,
or replace Human release approval.

The scaling decision is **500 questions remain valuable**.  The next 100 must
be allocated to thin knowledge targets and evidence-distinct learning
decisions, not used to repeat dense targets or to win a question-count race.

## Reviewed inventory

- 400 contiguous stable IDs, `EISEI1-Q-000001` through `EISEI1-Q-000400`.
- Official-category allocation: 91 / 91 / 64 / 64 / 90.
- 400 source-verification records and 400 coverage bindings.
- 37 of 37 required knowledge targets covered.
- Correct-choice positions: A, B, C, D, and E each 80.
- Every question has explanations for choices A through E.

## Reviewer separation and method

A fresh-context, read-only AI reviewer inspected the canonical 400-question
inventory independently of the integrating agent.  The reviewer proposed
findings and replacements but did not edit the repository.  The integrating
agent reopened the primary sources, adjudicated the findings, applied the
accepted changes, synchronized candidate rows, canonical rows, acceptance
fingerprints, source verification, and coverage, and reran the complete gates.

The audit compared normalized stems and answer-defining propositions globally,
then inspected high-similarity pairs for whether they required a materially
different learning decision.  It also checked correct positions, all-choice
explanations, source locators, current-law exceptions, and coverage-target
alignment.

## Material findings resolved

- Correct-answer or explanation defects were repaired in Q214, Q377, Q391,
  and Q395.
- Safety-critical respirator guidance was corrected in Q329 and current PPE
  management terminology was applied in Q335.
- Current electronic reporting and its exception boundary were reflected in
  Q309; the legal application context was restored in Q381.
- Organic-solvent and specified-chemical work-supervisor locators were repaired
  in Q137--Q139 and Q151--Q153.
- Direct source mappings were added or corrected for the three-management
  framework, mental-health guidance, erythropoietin, vitamin D, digestive and
  kidney physiology, and related items.
- Thirty low-value, duplicate, over-split, or weakly supported propositions
  were replaced.  The replaced clusters included asbestos facilities,
  vibration-disorder factors, information-equipment education, repeated kidney
  functions, repeated biological monitoring definitions, and repeated airway
  anatomy.
- Thirteen exact-stem clusters were removed.  Exact normalized duplicate stems
  and exact answer-defining propositions are both now zero.
- Ten replacement questions were remapped to the correct knowledge targets so
  that coverage evidence still describes the revised content.
- Final precision fixes covered Q99, Q140, Q251, Q252, Q273, Q286, Q309, and
  Q370.

Primary evidence used for these corrections includes the current
[e-Gov occupational safety and health regulation](https://laws.e-gov.go.jp/law/347M50002000032/20260101_507M60000100097/),
[MHLW biological-monitoring table](https://anzeninfo.mhlw.go.jp/yougo/yougo21_1.html),
[MHLW chemical-management manual](https://www.mhlw.go.jp/content/11300000/001683952.pdf),
[NIDDK kidney guide](https://www.niddk.nih.gov/health-information/kidney-disease/kidneys-how-they-work),
and [NIDDK digestive-system guide](https://www.niddk.nih.gov/health-information/digestive-diseases/digestive-system-how-it-works).

## Verification evidence

- Bank validator with generated-drift check: 0 errors, 0 warnings.
- Exact normalized duplicate audit: 0 duplicate clusters.
- Question-bank regression: 158 tests passed.
- Shared Flutter application tests: 33 passed.
- Shared Flutter analysis: no errors; 78 existing warnings/information findings
  remain outside this question-bank-only scope.
- `git diff --check` with the repository's CRLF rule: clean.

## Why 500 questions remain useful

The category totals are already balanced, but the knowledge-target density is
not.  Ten required targets still have only one bound question, while the
largest target has 57.  Full coverage therefore does not yet mean uniform
variation depth.  A targeted additional 100 questions can add meaningful
rule-exception, threshold, case, and misconception variants to those thin
targets without changing the shared UI or architecture.

Market count claims also make 400 a credible but not leading number.  Current
store listings advertise [465 all-choice-explained questions](https://apps.apple.com/jp/app/%E7%AC%AC%E4%B8%80%E7%A8%AE%E8%A1%9B%E7%94%9F%E7%AE%A1%E7%90%86%E8%80%85-%E8%A9%A6%E9%A8%93%E5%AF%BE%E7%AD%96-%E5%85%A8%E8%82%A2%E8%A7%A3%E8%AA%AC465%E5%95%8F/id6780137318),
[500 questions](https://play.google.com/store/apps/details?hl=ja&id=com.msaitodev.healthsupervisor.humanmed),
and [716 questions with all-choice explanations](https://apps.apple.com/jp/app/%E8%A1%9B%E7%94%9F%E7%AE%A1%E7%90%86%E8%80%85%E3%82%B3%E3%83%B3%E3%83%97%E3%83%AA%E3%83%BC%E3%83%88%E3%83%9E%E3%82%B9%E3%82%BF%E3%83%BC-%E7%AC%AC%E4%B8%80%E7%A8%AE-%E7%AC%AC%E4%BA%8C%E7%A8%AE/id6782693876?platform=ipad).
The defensible position is therefore source-verified quality and learning
coverage first, with 500 as the next useful density gate.  Expansion beyond 500
should wait for learner completion, error-rate, and repeat-use evidence.

## Remaining production and Human gates

All 400 questions remain draft content.  `target_bank_size` is still bootstrap,
`bank_revision` is unchanged, and runtime output remains intentionally empty.
Production freeze must be a separate explicit transition that sets the approved
bank size and revision, changes the authorized publication state, regenerates
runtime artifacts, and repeats application validation.

Before that transition, obtain a stratified Human subject-matter review.  The
minimum recommended sample is two official-distribution mock exams (88
questions), including at least 20 questions from Q361--Q400 and every revised
safety-critical legal, chemical, or respirator item.  A stronger sales claim
requires review of Q301--Q400 plus one official-distribution sample from
Q1--Q300.  Numeric thresholds, deadlines, exceptions, and current-law items
should receive priority from a qualified reviewer.
