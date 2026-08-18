# Drone second-class question bank authoring

This bank instantiates the permanent `DRONE` question namespace. It contains
the initial five Stage 9 calibration questions, five B1A questions, seven B1B
questions, eight B1C questions, and eight B2A questions that passed the QID
Gate and Human Author Verification. All 33 authored questions remain draft.

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
| VS-010 | DRONE-Q-000018 |
| VS-011 | DRONE-Q-000019 |
| VS-018 | DRONE-Q-000020 |
| VS-019 | DRONE-Q-000021 |
| VS-012 | DRONE-Q-000022 |
| VS-013 | DRONE-Q-000023 |
| VS-014 | DRONE-Q-000024 |
| VS-020 | DRONE-Q-000025 |
| VS-023 | DRONE-Q-000026 |
| VS-030 | DRONE-Q-000027 |
| VS-024 | DRONE-Q-000028 |
| VS-031 | DRONE-Q-000029 |
| VS-025 | DRONE-Q-000030 |
| VS-032 | DRONE-Q-000031 |
| VS-026 | DRONE-Q-000032 |
| VS-033 | DRONE-Q-000033 |

The registry uses the existing `used` status. Because none of the questions
has entered a released bank, `first_used_bank_revision` remains empty. IDs
beyond `DRONE-Q-000033` are not reserved.

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

The B1C rows preserve the Auto-to-Manual A1/A2/A3/A4 and TEM E1/E2/E3
measurement structures. VS-010 (A1) and VS-011 (A4) are observed; VS-018 (A2)
and VS-019 (A3) are held-out and remain separate families. VS-012 is the E1
primary, VS-014 is its E1 alternate, VS-013 is E2 observed, and VS-020 is E3
held-out. These bindings do not activate the questions or expose held-out
answer truth in existing observed explanations.

The B2A rows preserve four breadth pairs. HB-1 binds VS-023 observed to VS-030
held-out with counterbalance `YES`; HB-2 binds VS-024 observed to VS-031
held-out with counterbalance `PARTIAL_ONLY`; HB-3 binds VS-025 observed to
VS-032 held-out with counterbalance `YES`; and HB-4 binds VS-026 observed to
VS-033 held-out with counterbalance `YES`. These bindings do not activate the
questions or implement counterbalance routing.

VS-039 (`DRONE-Q-000004`) remains the US-C Sentinel. VS-069
(`DRONE-Q-000005`) remains its COV-25 neighbor and does not expose the
transmitter, receiver, or remote-command sequence in its stem, choices, or
explanation.
