# Eisei1 500-Question Expansion Value Review v1

Date: 2026-08-28

Branch: `codex/eisei1-b9-integration`

Status: 500-question expansion rejected at the learning-value gate.  The
source-verified 400-question bank remains the content-freeze candidate.

## Decision

**Stop at 400 questions for the current sale-freeze candidate.**

Two separate 100-question expansion designs were authored as unallocated
`AI_PRE_ACCEPT` candidates and independently reviewed.  Neither design was
allowed to allocate stable IDs or mutate the canonical bank.  Both candidate
sets were removed after rejection.

This is a quality decision, not a tooling limitation.  Reaching 500 with the
currently verified propositions would increase the displayed count without
adding 100 defensible learning decisions.

## Attempt 1: atomic density variants

The first design targeted the official category addition profile of
23 / 23 / 16 / 16 / 22 and balanced correct positions at 20 each.  All ten
batches passed structural pre-validation.

Independent review rejected the design because it contained numerous semantic
collisions with Q1--Q400, several source locators that did not directly support
the proposition, systematically weak distractors, and repetitive explanations
that restated the correct answer instead of explaining each error.  No stable
IDs were allocated.

## Attempt 2: same-source paired decisions

The second design combined two already verified canonical propositions from
the same primary source.  Its deterministic evidence was strong:

- component answer, source, and locator consistency: 100/100;
- unique correct combination: 100/100;
- A--E component truth/explanation consistency: 100/100;
- exact pair and answer-proposition collisions: 0;
- exact normalized stems: 0;
- correct positions A--E: 20 each; and
- all ten candidate batches: 0 validation errors.

The independent learning-value review nevertheless rejected all 100 as a
sale-quality expansion.  Every item joined two existing questions with an AND
decision rather than introducing a scenario, causal chain, exception boundary,
or new source-supported proposition.  The 200 component slots were
concentrated in 97 existing questions, several of which were reused seven or
eight times.  Seventy-four candidates combined different knowledge targets
while recording only one primary binding.

## Independent reviewer conclusion

The reviewer found that only 26 of the 100 pairs shared both the same source
and the same knowledge target.  With each canonical component limited to one
reuse, the maximum matching fell to nine.  After requiring a natural semantic
connection and varied formats, only five to eight candidates were likely to
provide defensible new learning value.

That limited set is not adopted here because the declared Gate was a coherent
500-question bank, not opportunistic count growth.  It can be reconsidered as
a later quality update after learner evidence exists.

## Conditions for future expansion

A future expansion should begin with new primary-source propositions rather
than recombining the present inventory.  A realistic next tranche is 20--30
questions, subject to all of the following:

1. new or materially deeper primary-source evidence;
2. scenario, comparison, procedure, threshold, or exception decisions that do
   not duplicate Q1--Q400;
3. one accurate primary knowledge-target binding per item;
4. specific reasons for every incorrect choice;
5. no concentration on a small set of existing component questions; and
6. independent review of a representative pilot batch before authoring the
   remainder.

Expansion to 500 should be reconsidered only after real learner completion,
incorrect-answer, and repeat-use data identify an unmet learning need.

## Preserved boundaries

- Canonical count remains 400 contiguous stable IDs.
- The rejected candidates never received permanent IDs.
- `bank_revision`, release snapshots, runtime content, UI, and architecture
  remain unchanged.
- Production freeze, PR creation, and release remain separate explicit Gates.
