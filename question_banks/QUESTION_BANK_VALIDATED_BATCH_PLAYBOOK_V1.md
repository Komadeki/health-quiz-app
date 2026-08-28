# Validated Question-Bank Batch Playbook v1

## Purpose

Use this playbook to grow any qualification question bank without treating a
question count as a quality signal.  It is deliberately qualification-neutral:
the bank-specific coverage model, approved sources, and examination profile are
inputs rather than changes to the shared factory or UI.

## Required inputs

Before a batch is authored, freeze the following in the bank's authoring area:

1. a stable-ID registry and the current canonical question CSV;
2. a source catalogue with version and locator rules;
3. a knowledge-target/coverage map and the target examination distribution;
4. a bank-specific quality gate defining ambiguity, distractor, and
   source-authority rules; and
5. the generated-artifact and release boundary.

Do not allocate an ID, update a release revision, or alter runtime assets just
because a candidate has been drafted.

## Repeatable batch loop

Use batches of at most ten candidates.  For each candidate, record one primary
knowledge target, one answer-defining proposition, the tested misconception,
the reasoning path, a primary source/version/locator, five choices, and a
five-choice explanation.

1. **Plan from gaps.** At early stages, select uncovered required targets.  At
   density stages, select evidence-distinct variants, not paraphrases.
2. **Author evidence-first.** Confirm the source can make exactly one choice
   best before writing distractors.  Reject candidates that cannot support four
   plausible same-domain distractors.
3. **Review independently.** Compare against every canonical question and all
   persisted candidates.  A reordered answer or relabelled stem is not a new
   item if it follows the same reasoning path.
4. **Control answer positions.** Inspect both the batch and cumulative A--E
   distribution.  Correct a position bias only by reordering unchanged choices.
5. **Validate the batch.** Run the expansion validator before and after the
   accepted-candidate transition.  Treat an error, warning, source-version
   conflict, or collision as REWORK/HOLD, never as a quota exception.
6. **Integrate transactionally.** Allocate only available IDs, write the
   canonical row, registry entry, source-verification record, and coverage
   binding as one operation.  Validate the whole bank, regenerate, and check
   generated drift.
7. **Commit a recoverable checkpoint.** Commit only the explicit batch files,
   canonical mappings, and focused tests.  Keep release snapshots,
   `bank_revision`, runtime assets, and UI unchanged until a declared freeze
   gate.

## Independent AI review protocol

At a major gate, assign a fresh-context reviewer that did not author the
questions.  The reviewer is read-only: it reports findings and proposed
replacements, while the integrating agent independently reopens the cited
primary source and owns every repository mutation.

The review must include all canonical questions, not only the newest batch:

1. verify that the source locator directly supports the answer-defining
   proposition and does not rely on an unstated inference;
2. verify the correct position and the explanation of every choice A--E;
3. compare normalized stems and answer-defining propositions across the whole
   bank, then inspect high-similarity pairs semantically;
4. reject item splitting where several questions merely enumerate parts of one
   list, rule, definition, or reasoning path;
5. verify that a replacement still matches its unit and knowledge-target
   binding; and
6. rerun deterministic validation and regression after the accepted fixes.

Store a gate report that names the reviewed inventory, reviewer separation,
source-retrieval date, findings, accepted fixes, unresolved risks, and the
remaining Human/release gate.  A pre-filled `ACCEPT` field or a reviewer name in
an acceptance packet is not proof that this review occurred.

Exact normalized duplicate stems are a fail-closed condition for a sale-freeze
candidate.  Similar wording is allowed only where the answer-defining
propositions and learning decisions are materially different, such as paired
legal thresholds or complementary anatomical functions.

## Gate schedule

| Gate | Evidence required |
| --- | --- |
| Coverage | Every required target has a source-verified draft item. |
| Exam | A mock can be assembled at the official category distribution. |
| Density | Category balance, collision risk, source freshness, and A--E distribution are reviewed. |
| Freeze candidate | Full validation, generated-drift check, regression, and scoped application checks pass. |
| Release | Separate human/release approval; update `bank_revision` only here. |

## Minimum verification commands

Run the bank-specific expansion validator for the changed batch, then:

```bash
python3 tooling/question_bank/validate.py --bank question_banks/<bank>
python3 tooling/question_bank/generate.py --bank question_banks/<bank>
python3 tooling/question_bank/validate.py --bank question_banks/<bank> --check-generated
python3 -m unittest discover -s tooling/question_bank/tests -p 'test_*.py'
```

Run the relevant application analysis and tests at declared freeze gates.  Keep
tooling results distinct from human source review, subject-matter review,
device testing, and release approval.

## Scaling decision rule

After each major gate, decide whether another 100 questions would add new
learning value.  Evaluate target-level proposition/format variation, category
thinness against the exam profile, measured collisions, answer-position skew,
source/review cost, competitor positioning, and real learner completion and
incorrect-answer data.  Do not extend solely because a competitor advertises a
larger number.

Use the knowledge-target density distribution, not only its average.  A bank
can have full target coverage while several required targets still have only
one question.  Prefer the next expansion when it can add direct-source,
evidence-distinct propositions to those thin targets without increasing
collision or review risk.
