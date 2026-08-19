# Drone second-class question bank authoring

This bank instantiates the permanent `DRONE` question namespace. It contains
the initial five Stage 9 calibration questions, five B1A questions, seven B1B
questions, eight B1C questions, eight B2A questions, five B2B questions, two
B3A Clean Sentinel questions, five B3B Routed Sentinel questions, and 14 B4 D1
Coverage questions, ten B5 D2-A Coverage questions, ten B6 D2-B Coverage
questions, ten B7 D3 Coverage questions, and 11 B8 D4 Coverage questions. The
B4 D1, B5 D2-A, B6 D2-B, B7 D3, and B8 D4 questions passed the Source-first
Gate, Question Authoring Content Gate, Human Author Verification, and QID Gate.
All 100 authored questions remain draft.

## Release state

- 100 / 100 authored questions are complete.
- Cross-Bank Audit passed with non-blocking observations.
- V0-Core Bank Readiness is `GO`.
- The formal validation snapshot `bank_revision` is
  `drone-second-class-v0-core-2026-08-19`, with `content_as_of=2026-08-19`.
- All currently authored questions remain `draft`, so generated runtime output
  intentionally contains zero active questions and an empty deck list.
- Runtime remains inactive, V0-Panel has not started, and release approval has
  not been granted.
- `unreleased-bootstrap-2026-08-18` was the preceding tooling working revision.
- Difficulty, importance, and free/paid fields contain neutral working values
  required by authoring schema v2. They are not product decisions while the
  rows remain draft.

## Validation snapshot identity

`drone-second-class-v0-core-2026-08-19` identifies the 100-question V0-Core
validation snapshot. It does not indicate an App Store or production release,
release approval, runtime activation, `Question status=active`, V0-Panel PASS,
or Product Validation PASS.

Once a formal `bank_revision` identifies a merged validation snapshot, that
revision value must not be reused for materially different validation content.
Changes to question content, version, or status; source binding; bank structure;
or validation-relevant metadata require a new `bank_revision`. This bank-level
reproducibility rule is independent of the question-level
`question_id` / `question_version` identity contract.

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
| VS-034 | DRONE-Q-000034 |
| VS-028 | DRONE-Q-000035 |
| VS-035 | DRONE-Q-000036 |
| VS-029 | DRONE-Q-000037 |
| VS-036 | DRONE-Q-000038 |
| VS-041 | DRONE-Q-000039 |
| VS-042 | DRONE-Q-000040 |
| VS-037 | DRONE-Q-000041 |
| VS-038 | DRONE-Q-000042 |
| VS-040 | DRONE-Q-000043 |
| VS-043 | DRONE-Q-000044 |
| VS-044 | DRONE-Q-000045 |
| VS-045 | DRONE-Q-000046 |
| VS-046 | DRONE-Q-000047 |
| VS-047 | DRONE-Q-000048 |
| VS-048 | DRONE-Q-000049 |
| VS-049 | DRONE-Q-000050 |
| VS-050 | DRONE-Q-000051 |
| VS-051 | DRONE-Q-000052 |
| VS-052 | DRONE-Q-000053 |
| VS-053 | DRONE-Q-000054 |
| VS-054 | DRONE-Q-000055 |
| VS-055 | DRONE-Q-000056 |
| VS-056 | DRONE-Q-000057 |
| VS-057 | DRONE-Q-000058 |
| VS-058 | DRONE-Q-000059 |
| VS-059 | DRONE-Q-000060 |
| VS-060 | DRONE-Q-000061 |
| VS-061 | DRONE-Q-000062 |
| VS-062 | DRONE-Q-000063 |
| VS-063 | DRONE-Q-000064 |
| VS-064 | DRONE-Q-000065 |
| VS-065 | DRONE-Q-000066 |
| VS-066 | DRONE-Q-000067 |
| VS-067 | DRONE-Q-000068 |
| VS-068 | DRONE-Q-000069 |
| VS-070 | DRONE-Q-000070 |
| VS-071 | DRONE-Q-000071 |
| VS-072 | DRONE-Q-000072 |
| VS-073 | DRONE-Q-000073 |
| VS-074 | DRONE-Q-000074 |
| VS-075 | DRONE-Q-000075 |
| VS-076 | DRONE-Q-000076 |
| VS-077 | DRONE-Q-000077 |
| VS-078 | DRONE-Q-000078 |
| VS-079 | DRONE-Q-000079 |
| VS-080 | DRONE-Q-000080 |
| VS-081 | DRONE-Q-000081 |
| VS-082 | DRONE-Q-000082 |
| VS-083 | DRONE-Q-000083 |
| VS-084 | DRONE-Q-000084 |
| VS-085 | DRONE-Q-000085 |
| VS-086 | DRONE-Q-000086 |
| VS-087 | DRONE-Q-000087 |
| VS-088 | DRONE-Q-000088 |
| VS-089 | DRONE-Q-000089 |
| VS-090 | DRONE-Q-000090 |
| VS-091 | DRONE-Q-000091 |
| VS-092 | DRONE-Q-000092 |
| VS-093 | DRONE-Q-000093 |
| VS-094 | DRONE-Q-000094 |
| VS-095 | DRONE-Q-000095 |
| VS-096 | DRONE-Q-000096 |
| VS-097 | DRONE-Q-000097 |
| VS-098 | DRONE-Q-000098 |
| VS-099 | DRONE-Q-000099 |
| VS-100 | DRONE-Q-000100 |

The registry uses the existing `used` status. Because none of the questions
has entered a released bank, `first_used_bank_revision` remains empty. IDs
beyond `DRONE-Q-000100` are not reserved.

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

The B2B rows preserve three breadth pairs. HB-5 binds existing VS-027
(`DRONE-Q-000003`) observed to VS-034 held-out with counterbalance `YES`; HB-6
binds VS-028 observed to VS-035 held-out with counterbalance `YES` while
keeping spatial and temporal wind variation separate; and HB-7 binds VS-029
observed to VS-036 held-out with counterbalance `YES` while keeping external
and aircraft-state monitoring separate. These bindings only record the
measurement structure; they do not activate questions, execute
counterbalancing, or issue a formal release `bank_revision`.

The B3A Clean Sentinel rows add Human Author Verified VS-041 / US-E and
VS-042 / US-F with permanent IDs allocated. Both remain draft; this allocation
does not implement runtime Sentinel routing or issue a formal release
`bank_revision`.

The B3B Routed Sentinel rows add Human Author Verified VS-037 / US-A, VS-038 /
US-B, VS-040 / US-D, VS-043 / US-G, and VS-044 / US-H after passing the QID
Gate. All five remain draft; this allocation records their permanent identities
without implementing the runtime Sentinel protocol, activating questions, or
issuing a formal release `bank_revision`.

The B4 D1 Coverage rows add Human Author Verified VS-045 through VS-058 /
COV-01 through COV-14 after passing the Source-first Gate, Question Authoring
Content Gate, Human Author Verification, and QID Gate. All 14 remain draft;
this allocation does not author B4 D2, activate questions, or issue a formal
release `bank_revision`.

The B5 D2-A Coverage rows add Human Author Verified VS-059 through VS-068 /
COV-15 through COV-24 after passing the Source-first Gate, Question Authoring
Content Gate, Human Author Verification, and QID Gate. All ten remain draft;
this allocation does not activate questions or issue a formal release
`bank_revision`.

The B6 D2-B Coverage rows add Human Author Verified VS-070 through VS-079 /
COV-26 through COV-35 after passing the Source-first Gate, Question Authoring
Content Gate, Human Author Verification, and QID Gate. All ten remain draft;
the B6 allocation itself did not author B7, activate questions, or issue a
formal release `bank_revision`.

The B7 D3 Coverage rows add Human Author Verified VS-080 through VS-089 /
COV-36 through COV-45 after passing the Source-first Gate, Question Authoring
Content Gate, Human Author Verification, and QID Gate. All ten remain draft;
this allocation does not author B8, activate questions, reserve IDs beyond
`DRONE-Q-000089`, or issue a formal release `bank_revision`. COV-39 records
AFTER-US-B administration routing without implementing the runtime Sentinel
protocol.

The B8 D4 Coverage rows add Human Author Verified VS-090 through VS-100 /
COV-46 through COV-56 after passing the Source-first Gate, Question Authoring
Content Gate, Human Author Verification, and QID Gate. All 11 remain draft.
Reaching 100 authored questions alone did not declare the Cross-Bank Audit
passed, activate runtime, grant release approval, or issue a formal validation
snapshot; IDs beyond `DRONE-Q-000100` remain unreserved.

VS-039 (`DRONE-Q-000004`) remains the US-C Sentinel. VS-069
(`DRONE-Q-000005`) remains its COV-25 neighbor and does not expose the
transmitter, receiver, or remote-command sequence in its stem, choices, or
explanation.
