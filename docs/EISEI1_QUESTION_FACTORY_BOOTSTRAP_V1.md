# Eisei1 Question Factory Bootstrap Contract v1.0

Status: implementation contract

Product: 第一種衛生管理者

Repository: `Komadeki/health-quiz-app`

## 1. Purpose

Bootstrap the first-class health manager question bank by reusing the existing Drone and Otsu4 production Question Factory, with the smallest reusable change and without creating a qualification-specific parallel pipeline.

This contract governs the authoring infrastructure and source/coverage workflow. It does not set the final commercial bank size and does not authorize production question IDs before the existing acceptance gates.

## 2. Upstream contracts that remain authoritative

The following existing contracts remain in force unless this document explicitly adds a compatible requirement:

1. `question_banks/README.md`
2. `question_banks/PRODUCTION_QUESTION_BANK_EXPANSION_PROTOCOL_V1.md`
3. existing permanent-ID, source verification, coverage, deterministic generation, and release-snapshot rules

No Drone or Otsu4 lifecycle rule is relaxed by this contract.

## 3. Confirmed exam facts

As of 2026-08-26, the Safety and Health Examination Association identifies the regular 第一種衛生管理者 examination as 44 questions in three hours, using five-option single-answer questions.

Official section structure:

- 関係法令（有害業務に係るもの）: 10
- 労働衛生（有害業務に係るもの）: 10
- 関係法令（有害業務に係るもの以外）: 7
- 労働衛生（有害業務に係るもの以外）: 7
- 労働生理: 10
- total: 44

Official references:

- https://www.exam.or.jp/introduction/h_shokai502/
- https://www.exam.or.jp/lckohyo/
- https://www.exam.or.jp/wp-content/uploads/2026/04/LC20260415-1.pdf

The Association states that the questions published in April 2026 were administered from July through December 2025 and do not reflect laws effective on or after 2026-01-01. Therefore published questions are exam-format and coverage evidence, not the sole current-law authority.

## 4. Shared Factory delta required before authoring

Current shared authoring/expansion contracts support three- and four-choice questions. Eisei1 question authoring MUST NOT begin by reducing official five-option questions to four options.

The shared Factory SHALL be extended generically as follows:

- accept 3, 4, or 5 contiguous choices in the common contract;
- accept `E` as a correct-choice label when a fifth choice exists;
- preserve all existing 3/4-choice Drone and Otsu4 inputs unchanged;
- allow `choice5` as an additive optional CSV column rather than making it mandatory for legacy banks/batches;
- add an optional qualification-level expected choice count;
- Eisei1 SHALL set the expected choice count to `5`;
- a bank with expected choice count `5` SHALL reject 3/4-choice canonical questions and expansion candidates;
- deterministic runtime generation SHALL emit all authored choices and a zero-based `answerIndex`;
- transaction/integration tooling SHALL accept both the legacy schema and the additive `choice5` schema without rewriting historical batches;
- regression coverage SHALL prove legacy 3/4-choice compatibility and a five-choice / answer-E path.

The existing qualification runtime UI already renders `card.choices` dynamically and derives choice order from `card.choices.length`; no Eisei1-specific UI fork is authorized for this delta.

## 5. Eisei1 source hierarchy

Question correctness SHALL use the following source priority:

1. Current e-Gov / MHLW primary statutes, ordinances, and regulations for legal propositions.
2. Current MHLW authoritative guidance/materials for occupational-hygiene and health propositions where applicable.
3. Safety and Health Examination Association published questions for exam style, distractor patterns, section allocation, and coverage signals.

Published question text SHALL NOT be copied as production content. Production questions are independently authored from verified propositions under the existing provenance contract.

For legal limits, numerical thresholds, exceptions, appointment requirements, measurement intervals, record-retention periods, and similar change-sensitive propositions, source verification is a promotion requirement and must use a source version current to the bank `content_as_of`.

## 6. Coverage-first workflow

The official five-section structure is the top-level exam profile, not the final authoring taxonomy. Before candidates are generated, Eisei1 SHALL create a granular `coverage.json` that decomposes each section into knowledge targets.

The Otsu4/Drone expansion rules are reused:

- coverage plan before candidate generation;
- batch count is an upper bound, never a quota;
- collision review is global against the entire current Eisei1 permanent bank, not merely the active batch;
- source binding is explicit before promotion;
- permanent IDs are allocated only after the existing acceptance gate;
- canonical integration, source verification, generated runtime checks, and regression validation remain downstream gates;
- formal `bank_revision` is not advanced merely because an authoring batch exists.

## 7. Authoring parallelism

Eisei1 SHALL begin with at most two coverage ranges in parallel.

Reason: two lanes capture most of the throughput benefit while limiting duplicate construction, cross-range legal overlap, review coordination, and source-version drift. Additional parallel lanes require evidence that collision/rework rates remain low.

Recommended initial separation:

- Lane A: 関係法令（有害業務に係るもの）
- Lane B: 労働衛生（有害業務に係るもの）

The remaining three sections are prepared in the coverage map but are not authored concurrently until the first two lanes establish throughput and rework evidence.

## 8. Bank-size rule

No final production bank-size target is fixed at bootstrap.

The first expansion target SHALL be evidence-based after measuring:

- accepted candidates per coverage target;
- collision/redundancy rate;
- source-verification burden;
- rework/reject rate;
- uncovered required targets;
- sufficient variation within high-importance targets.

This prevents quota-driven low-value questions and avoids repeating authoring work only to retire redundant items later.

## 9. Permanent identity

Eisei1 uses the existing explicit permanent-ID contract. The bootstrap bank SHALL define an empty-registry `question_id_prefix` of `EISEI1` unless a conflicting repository-resident product identifier is approved before the first permanent allocation.

Candidate IDs are temporary. `EISEI1-Q-000001` and later IDs are allocated only at the existing Permanent ID Gate.

## 10. Atomic execution order

1. Merge generic 5-choice compatibility with regression coverage.
2. Bootstrap `question_banks/eisei1/` using expected choice count `5`.
3. Seed current authoritative source registry entries.
4. Commit the granular coverage map for all five official sections.
5. Open the first two coverage ranges only.
6. Generate candidates under the existing Expansion Protocol.
7. Apply acceptance/source/collision gates.
8. Allocate permanent IDs and integrate only accepted candidates.
9. Repeat in two-range waves until coverage evidence supports bank completion.
10. Freeze release bank revision only at the normal release-readiness stage.

## 11. Resource route

Generic five-choice implementation is a normal multi-file repository change with established architecture.

- Recommended implementation resource: standard repository-mutation model
- Codex: required when available for the multi-file implementation; do not use it for PR/CI review or merge
- Pro: not required
- Escalate only if the shared schema cannot remain backward-compatible, runtime behavior proves non-dynamic, or existing authoritative contracts conflict

Question drafting itself should use the lightest model that can satisfy source-grounding and collision constraints; escalate only for ambiguous legal interpretation, cross-source conflict, or repeated review failure.

## 12. Definition of ready-for-authoring

Eisei1 candidate authoring may start only when all of the following are true:

- shared 5-choice compatibility is merged to `main`;
- legacy Drone/Otsu4 validation remains green;
- a five-choice / answer-E regression path is green;
- Eisei1 bank scaffold exists with expected choice count `5`;
- source registry exists;
- coverage map exists;
- the first two coverage ranges have explicit source and collision contracts.
