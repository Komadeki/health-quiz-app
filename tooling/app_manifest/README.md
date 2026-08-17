# App manifest tooling

Each direct child `apps/<app>/app.yaml` is the build-time source of truth for
app identity, question-bank, identity-policy, monetization, exam, and branding
values. Nested app directories are not scanned, and apps never load YAML at
runtime.

`question_bank.runtime_path`, `question_bank.manifest_path`, and
`question_bank.asset_output` are always repository-root-relative paths.
Generated Dart and native configuration are written under the directory that
contains each manifest.

From this directory:

```bash
dart run bin/validate.dart --repository-root ../.. --check-generated
dart run bin/generate.dart --repository-root ../..
dart run bin/generate.dart --repository-root ../.. --check
```

The generator only writes files carrying a `GENERATED FILE - DO NOT EDIT`
notice: typed Dart configuration, native identity configuration, and declared
question-bank asset copies. Native project wiring is intentionally maintained
as a small human-readable source diff.

Repository root discovery uses the portable marker directories `apps/`,
`packages/quiz_engine/`, and `tooling/app_manifest/`. Root `app.yaml` and
`reference_apps/` are rejected as legacy source locations.
