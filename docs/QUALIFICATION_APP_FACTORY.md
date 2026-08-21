# Qualification App Factory v1.0

Qualification App Factory is the shared production architecture for commercial
KOMADEKI qualification apps. `packages/quiz_engine` owns versioned, UI-free
learning contracts and calculations. `packages/qualification_app` owns the
Material 3 shell and device integrations. An app under `apps/<app_key>` is a
thin composition of its generated `QualificationAppDefinition` and that shell.

Shared architecture does not mean an identical App Store product. Each
qualification must still differ where the qualification itself differs:

- official sources and Question Bank;
- exam structure, section terminology, and pass rules;
- learning path, source presentation, product copy, and branding;
- support, privacy, legal, and App Store metadata.

These seams support product differentiation without duplicating learning,
progress, persistence, practice, mock-exam, or purchase architecture. They do
not guarantee App Review acceptance.

## Build-time definition

`apps/<app_key>/app.yaml` is the Source of Truth. Manifest tooling validates it
and generates Dart/native configuration. YAML is never loaded at runtime.

The optional `factory` section opts a qualification app into Factory v1 and
defines the app version, home/source copy, enabled standard modes, practice
size, recent-performance window, and presentation feature flags. The existing
`exam` section defines the version, count, optional time limit, allocations,
optional overall/section pass rules, and shuffle behavior. A null pass rule is
preserved as “no configured result”; the runtime never invents one.

The Question Bank remains responsible for permanent question IDs, question
versions, bank revision, sources, units, premium flags, and released answer
content. Manifest generation copies the validated runtime bank byte-for-byte
to the Flutter asset.

## Learning data and local-first boundary

`LearningEventV1` is the canonical answer event. It records app/session/attempt
identity, permanent question ID and version, bank revision, unit, optional
knowledge target, choice, correctness, UTC answer time, non-negative duration,
deterministic attempt number, typed mode, and app version. It contains no PII.

`JsonLinesLearningRepository` stores a namespaced, append-only, versioned local
journal under application support storage. The schema header is checked before
records are read; an unsupported schema fails closed. Active resume state and
the full-unlock cache are small namespaced SharedPreferences records. Factory
v1 has no backend, login, cloud sync, or analytics SDK.

## Shared learning behavior

Factory v1 supplies unit, random, unanswered, most-recent-incorrect, retry, and
mock-exam sessions. Question order is frozen when a session starts. Resume
rejects incompatible bank revisions, missing questions, invalid responses,
unsupported exam profiles, and inaccessible content.

Progress counts unique permanent question IDs and keeps repeated attempts in
accuracy/attempt metrics without inflating completion. History preserves
completed practice and mock sessions. Weakness is a transparent unit baseline
with optional knowledge-target metrics. The deterministic recommendation uses
those local metrics and exposes a reason code.

`PredictionEngine` and `PredictionEvaluation` are extension contracts only.
Production uses `UnavailablePredictionEngine`; Factory v1 displays no pass
probability, AI decision, or unsupported “real exam ability” claim. Historical
V0 Panel research remains isolated and is not a production dependency.

## Adding a second qualification

The standard Question Factory pipeline is:

```text
Official Source Freeze
→ Source Registry
→ Knowledge / Coverage Map
→ Human bank-size decision
→ Authoring Plan
→ 50–100Q draft batches
→ Human source verification
→ deterministic duplicate / coverage QC
→ Permanent ID / canonical authoring
→ final Human release approval
→ released snapshot
→ runtime generation
```

Pre-ID AI drafts may exist outside canonical `questions.csv`. Once a Question
enters canonical authoring, it must follow the explicit permanent-identity
rules. The factory validates declared coverage and source-version evidence; it
does not decide semantic correctness, source authority, or whether a Human
coverage taxonomy/bank size is sufficient.

1. Freeze the official-source inputs and create `question_banks/<app_key>` with
   `sources.json`, `coverage.json`, source-verification records, and canonical
   Questions under the permanent-ID contract.
2. Create a direct-child `apps/<app_key>` Flutter composition and native IDs.
3. Add `app.yaml` with `qualification_runtime_v2`, `explicit_v1`,
   `singleFullUnlock`, exam/branding details, and a `factory` profile.
4. Depend on both `packages/quiz_engine` and `packages/qualification_app` by
   relative path. The production entrypoint should pass only the generated
   definition to `QualificationProductionBootstrap`.
5. Run the deterministic Question Factory readiness report, manifest
   generation/validation, question-bank validation, and `tooling/ci/check_all.sh`.
   Direct-child Factory apps are discovered by CI;
   adding a qualification does not require a new learning architecture.

App-specific UI is appropriate for defensible product presentation or an
official exam rule that cannot be expressed by the current profile. It should
compose shared contracts, not fork controllers, session stores, selection
algorithms, purchase handling, or standard screens.
