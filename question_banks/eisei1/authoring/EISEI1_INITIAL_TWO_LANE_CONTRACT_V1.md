# Eisei1 Initial Two-Lane Authoring Contract v1

Status: ready for candidate planning after source verification.

This contract opens only the following two coverage ranges:

- Lane A: `eisei1_law_hazardous` (`E1-LH-001` through `E1-LH-003`)
- Lane B: `eisei1_hygiene_hazardous` (`E1-HH-001` through `E1-HH-003`)

The remaining three units are represented in `coverage.json` but are not open
for candidate authoring in this wave.

## Source requirements

Every legal proposition in Lane A cites the exact current article, paragraph,
item, table or appendix in `E1-LAW-ASL`, `E1-LAW-ASR`, `E1-LAW-WEM`, or
`E1-LAW-PNEUMO`. A more specific current primary regulation is added to the
registry before a candidate relies on it.

Every Lane B proposition cites a current primary legal source where it asserts
a legal requirement. Health-effect or control-method propositions may use
`E1-MHLW-WORKENV` or `E1-MHLW-OH` only with a precise publication locator.

`E1-EXAM-STRUCTURE` and `E1-EXAM-PUBLISHED-202604` are limited to exam format,
section allocation, distractor design and coverage signals. They never justify
copied question text or a current-law conclusion.

## Collision and quality controls

- Each candidate is independently authored in five choices; answer E is
  allowed and choice count is always exactly five.
- Collision review compares every candidate with all canonical Eisei1 rows and
  all persisted candidates in both open lanes, not only its own target.
- Lanes may not duplicate a proposition by relabeling an exposure-control rule
  as a legal-administration question.
- Candidate count is a ceiling set in the future batch plan, never a quota.
- No permanent ID, canonical row, release snapshot or runtime file changes are
  authorized by this planning contract.
