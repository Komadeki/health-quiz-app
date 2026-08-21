# Qualification question bank contract

Phase 2C keeps the published health bank in `apps/health/assets/decks/`
unchanged. New
qualification banks use a separate authoring and generation contract:

```text
questions.csv + bank.json + sources.json + coverage.json + source verifications
  + ID/release registries
  -> validate.py
  -> generate.py
  -> runtime bank JSON + bank manifest
  -> quiz_engine models
```

CSV + JSON is intentional. It uses only the Python standard library and does
not rely on an undeclared host YAML package. The committed files under
`generated/` are build artifacts and must not be edited directly.

## Permanent question identity

Qualification IDs use `<APP>-Q-<six digits>`, for example
`DRONE-Q-000001`. An ID identifies one question and does not encode deck,
unit, difficulty, law name, or source version.

- Never reuse an ID once assigned, including a retired ID.
- Moving a question between decks or units does not change its ID.
- Typographical, punctuation, explanation, and source-locator fixes keep the
  ID and increment `question_version`.
- A minor choice wording improvement may keep the ID only when the correct
  answer and meaning are unchanged.
- A changed answer, changed legal conclusion, or materially different thing
  being asked requires a new question ID. `question_version + 1` is not enough.
- `ExplicitQuestionIdentityV1` fails when the ID is absent; it never falls back
  to a legacy hash.

`question_id_registry.csv` is the permanent allocation ledger. A `retired`
row is a tombstone. `released_questions.json` freezes released answer contracts
and choice snapshots. Changing `correct_choice` under the same ID fails;
changing choice text warns and requires a `question_version` increment.

For a Question that has entered `released_questions.json`, its registry row
must retain a non-empty `first_used_bank_revision`. This is historical identity
evidence, not a value a generator may replace when the current bank revision
changes. Retired rows remain tombstones; a declared `replacement_id` must point
to another allocated permanent ID.

## Authoring schema v2

`questions.csv` has these columns:

```text
question_id, question_version, status, deck_id, unit_id, question,
choice1, choice2, choice3, choice4, correct_choice, explanation,
source_id, source_locator, difficulty, importance, is_free,
valid_from, valid_until, last_reviewed_at, supersedes_id, tags,
notes_internal
```

Three- and four-choice questions are supported. `correct_choice` is authored
as `A`, `B`, `C`, or `D`; the generator alone converts it to zero-based
`answerIndex`. Tags use `;` inside the CSV cell. Status is `draft`, `active`,
or `retired`, and only `active` rows enter the runtime bank.

Dates are explicit `YYYY-MM-DD` inputs. Expiration and review-age checks use
the bank's committed `content_as_of`, never the machine clock. This keeps
generation and validation deterministic. An `active` question whose
`valid_from` is after `content_as_of` is rejected as not yet effective.

## Source registry

`sources.json` stores `source_id`, `title`, `issuer`, `edition`,
`source_version`, `published_at`, `effective_from`, `url`, `retrieved_at`, and
`usage_basis`. Only `source_id`, `title`, `source_version`, and `usage_basis`
are required. `usage_basis` records provenance for editorial review; the
validator does not make a legal judgment.

`source_verifications.json` is the minimum release-readiness evidence, separate
from historical `notes_internal` workflows. Every active Question has exactly
one record with `question_id`, `source_id`, `source_version`,
`verification_state`, and `verified_at`. Factory v1 accepts an active Question
only when `verification_state` is `author_source_verified`, its source ID
matches the Question, and its verified source version matches the current
`sources.json` entry. A source-version mismatch requires Human review before
release readiness; independent/SME review and AI drafting remain risk-based
workflow choices, not universal gates.

## Coverage and bank-size evidence

`coverage.json` is authoring-only. It deliberately uses generic `unit_id`
parents rather than a universal Domain/Topic taxonomy. It records knowledge
targets, required/optional status, importance, minimum active counts, optional
variation requirements, Question-to-target bindings, and the Human-approved
target bank size with a rationale. Qualification-specific taxonomy can be
additional metadata, but the shared validator does not interpret it.

The validator checks declared IDs, units, bindings, active/draft counts,
required minima, required variations, and unbound active Questions. Optional
gaps and deterministic near-duplicate candidates are warnings. It cannot prove
that a taxonomy, Question set, bank size, source authority, or semantic overlap
is sufficient; those remain AI-assisted and Human-decided review.

## Runtime and provenance

Generated cards contain the permanent ID (`stableId`), `questionVersion`,
question, choices, zero-based `answerIndex`, explanation, unit, source ID,
source title/locator/version, difficulty, importance, and `isPremium`.
Authoring-only `status`, `notes_internal`, and `usage_basis` do not enter the
runtime card.

The bank manifest records schema version, app key, bank revision,
`content_as_of`, active/free counts, source versions, exam profile version, and
a SHA-256 hash of canonical runtime content. No execution timestamp is added.

## Commands

From the repository root:

```bash
python3 tooling/question_bank/validate.py \
  --bank question_banks/qualification_fixture --check-generated

python3 tooling/question_bank/generate.py \
  --bank question_banks/qualification_fixture

python3 tooling/question_bank/report.py \
  --bank question_banks/qualification_fixture \
  --check-generated --json

python3 -m unittest discover \
  -s tooling/question_bank/tests -p 'test_*.py'
```

CI reruns validation and compares deterministic output with the committed
runtime JSON and manifest. Any difference is generated drift and fails.
Coverage and verification remain authoring-only and do not change runtime bank
or manifest architecture.
