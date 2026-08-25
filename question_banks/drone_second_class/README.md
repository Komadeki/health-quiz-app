# Drone second-class question bank authoring

This bank instantiates the permanent `DRONE` question namespace. It contains
the initial five Stage 9 calibration questions, five B1A questions, seven B1B
questions, eight B1C questions, eight B2A questions, five B2B questions, two
B3A Clean Sentinel questions, five B3B Routed Sentinel questions, and 14 B4 D1
Coverage questions, ten B5 D2-A Coverage questions, ten B6 D2-B Coverage
questions, ten B7 D3 Coverage questions, and 11 B8 D4 Coverage questions. The
B4 D1, B5 D2-A, B6 D2-B, B7 D3, and B8 D4 questions passed the Source-first
Gate, Question Authoring Content Gate, Human Author Verification, and QID Gate.
Production release v4 activates the complete 386-question canonical bank while preserving the
existing 30-question free selection and all permanent question identities.

## Release state

- 386 / 386 canonical questions are Production active and released.
- Production bank revision: `drone-second-class-v4-release-2026-08-26`.
- Production runtime: 386 active questions, 30 free, and 356 premium.
- Free selection preserves the exact v3 30-question set; Q189..Q386 remain premium.
- `DRONE-Q-000001..DRONE-Q-000100` preserve first use in `drone-second-class-v1-release-2026-08-20`.
- `DRONE-Q-000101..DRONE-Q-000188` preserve first use in `drone-second-class-v2-release-2026-08-24`.
- `DRONE-Q-000189..DRONE-Q-000386` record first use in `drone-second-class-v4-release-2026-08-26`.
- The current release set is frozen at 386 under `DRONE-PRODUCTION-BANK-386-RELEASE-FREEZE-2026-08-26`; later expansion is a separate bank revision.

## Validation snapshot identity

`drone-second-class-v0-core-2026-08-19` identifies the 100-question V0-Core
validation snapshot. Its byte-identical authoring and generated inputs are
frozen under `validation/formal_snapshot/`. V0 tooling reads that path rather
than live production authoring. The V0 revision does not indicate an App Store
release, V0-Panel PASS, or Product Validation PASS.

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

The registry uses the existing `used` status. `DRONE-Q-000001..DRONE-Q-000100` preserve `drone-second-class-v1-release-2026-08-20`; `DRONE-Q-000101..DRONE-Q-000188` preserve `drone-second-class-v2-release-2026-08-24`; and `DRONE-Q-000189..DRONE-Q-000386` record `drone-second-class-v4-release-2026-08-26` in `first_used_bank_revision`. IDs beyond `DRONE-Q-000386` are not reserved.

The shared schema has no verification-state field. The existing
`notes_internal` field records `author_source_verified` and the measurement
role, KT, and family/coverage binding. Independent and subject-matter-expert
review flags remain unchanged; release approval is true for production v1.

The existing M3, breadth, Sentinel, and coverage mappings remain unchanged.
They continue to support the frozen V0 evidence, while production sessions use
only the four unit mappings and permanent question IDs. Production does not
execute validation counterbalancing, Sentinel routing, researcher handoff, or
Prediction. Expansion IDs `DRONE-Q-000101..DRONE-Q-000386` are allocated and released; `DRONE-Q-000387` and later remain unreserved.

VS-039 (`DRONE-Q-000004`) remains the US-C Sentinel. VS-069
(`DRONE-Q-000005`) remains its COV-25 neighbor and does not expose the
transmitter, receiver, or remote-command sequence in its stem, choices, or
explanation.

## V0-Panel validation bundle

The independent `validation/` path compiles the fixed 100-question formal
snapshot into a deterministic, validation-only Research Bank. Source inputs
live in `validation/formal_snapshot/`, while `validation/protocol.json` retains
the typed V0-Panel blueprint and fixed formal snapshot identity. Generated
validation artifacts remain in `validation/generated/`; they never replace the
live production files in `generated/`.

Generate and verify the validation artifacts from the repository root:

```sh
python3 tooling/v0_panel_validation/generate.py \
  --bank question_banks/drone_second_class
python3 tooling/v0_panel_validation/validate.py \
  --bank question_banks/drone_second_class \
  --check-generated
```

The generator parses `notes_internal` only as authoring control metadata. Raw
`notes_internal` is not emitted to the validation bundle; Panel consumers use
the materialized `validation_metadata` fields instead.
