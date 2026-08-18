# Drone second-class question bank authoring

This bank instantiates the permanent `DRONE` question namespace. It contains
the initial five Stage 9 calibration questions, the five B1A questions, and the
seven B1B questions that passed the QID Gate and Human Author Verification.

## Release state

- `unreleased-bootstrap-2026-08-18` is a tooling-required working revision.
  It is not a formal release `bank_revision`.
- All currently authored questions remain `draft`, so generated runtime output
  intentionally contains zero active questions.
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
| VS-002 | DRONE-Q-000006 |
| VS-003 | DRONE-Q-000007 |
| VS-015 | DRONE-Q-000008 |
| VS-021 | DRONE-Q-000009 |
| VS-022 | DRONE-Q-000010 |
| VS-005 | DRONE-Q-000011 |
| VS-006 | DRONE-Q-000012 |
| VS-016 | DRONE-Q-000013 |
| VS-007 | DRONE-Q-000014 |
| VS-008 | DRONE-Q-000015 |
| VS-009 | DRONE-Q-000016 |
| VS-017 | DRONE-Q-000017 |

The registry uses the existing `used` status. Because none of the questions
has entered a released bank, `first_used_bank_revision` remains empty. IDs
beyond `DRONE-Q-000017` are not reserved.

The shared schema has no verification-state field. The existing
`notes_internal` field records `author_source_verified` and the measurement
role, KT, and family/coverage binding. It does not grant `independent_reviewed`,
`subject_matter_expert_reviewed`, or `release_approved`.

The B1A rows preserve the M3 measurement structure: VS-002 is the H2 primary,
VS-003 is its alternate, VS-015 is H5 held-out, VS-021 is H3 Form A, and
VS-022 is H4 Form B. The H2 relationship is recorded for later administration
logic; this bank does not activate or co-administer the pair.

The B1B rows preserve the third-party T1/T2/T3 and GNSS G1/G2/G3 measurement
structures. VS-005 is the T2 primary and VS-006 is its alternate; VS-016 is T3
held-out. VS-007 is the G1 primary and VS-009 is its alternate; VS-008 is G2
observed and VS-017 is G3 held-out. These relationships are recorded for later
administration logic without activating the questions or exposing held-out
answer truth in existing observed questions.

VS-039 (`DRONE-Q-000004`) remains the US-C Sentinel. VS-069
(`DRONE-Q-000005`) remains its COV-25 neighbor and does not expose the
transmitter, receiver, or remote-command sequence in its stem, choices, or
explanation.
