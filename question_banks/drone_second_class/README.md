# Drone second-class question bank bootstrap

This bank instantiates the permanent `DRONE` question namespace for the five
Stage 9 calibration questions that passed the QID Gate and Human Author
Verification.

## Release state

- `unreleased-bootstrap-2026-08-18` is a tooling-required working revision.
  It is not a formal release `bank_revision`.
- All five questions remain `draft`, so generated runtime output intentionally
  contains zero active questions.
- Formal release remains on hold until the 100/100 bank, Cross-Bank Audit, and
  V0-Core candidate gates pass.
- Difficulty, importance, and free/paid fields contain neutral working values
  required by authoring schema v2. They are not product decisions while the
  rows remain draft.

## Permanent allocation

| Slot | Permanent question ID |
|---|---|
| VS-001 | DRONE-Q-000001 |
| VS-004 | DRONE-Q-000002 |
| VS-027 | DRONE-Q-000003 |
| VS-039 | DRONE-Q-000004 |
| VS-069 | DRONE-Q-000005 |

The registry uses the existing `used` status. Because none of the questions
has entered a released bank, `first_used_bank_revision` remains empty. IDs
beyond these five are not reserved.

The shared schema has no verification-state field. The existing
`notes_internal` field records `author_source_verified` and the Stage 9 role,
KT, and family/coverage binding. It does not grant `independent_reviewed`,
`subject_matter_expert_reviewed`, or `release_approved`.

VS-039 (`DRONE-Q-000004`) remains the US-C Sentinel. VS-069
(`DRONE-Q-000005`) remains its COV-25 neighbor and does not expose the
transmitter, receiver, or remote-command sequence in its stem, choices, or
explanation.
