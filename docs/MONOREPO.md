# Monorepo contract

## Boundaries

Flutter applications are direct children of `apps/`. Shared pure Dart code is
under `packages/`, shared question-bank sources are under `question_banks/`, and
build-time validation lives under `tooling/`. Root `docs/` and `.github/` are
repository-wide.

```text
apps/*
  -> packages/qualification_app
  -> packages/quiz_engine
```

App-to-app imports and path dependencies are forbidden. Shared packages must
not depend on any app. Factory apps use `qualification_app`, which owns the
Flutter/device production shell and depends on the UI-independent
`quiz_engine` contracts.

## App and path discovery

Only `apps/<app>/app.yaml` is an app manifest source. Root `app.yaml`,
`reference_apps/`, and nested `apps/<group>/<app>/app.yaml` are rejected. The
repository root is detected with portable marker directories:

- `apps/`
- `packages/quiz_engine/`
- `tooling/app_manifest/`

Machine-specific paths are never part of this contract.

The following manifest values are always relative to the repository root:

- `question_bank.runtime_path`
- `question_bank.manifest_path`
- `question_bank.asset_output`

Generated Dart and native files are instead placed relative to the directory
containing the manifest:

```text
apps/<app>/lib/generated/app_manifest.g.dart
apps/<app>/ios/Flutter/AppManifest.xcconfig
apps/<app>/android/app/app-manifest.properties
apps/<app>/android/app/src/main/res/values/app_manifest.xml
```

An optional `asset_output` is byte-for-byte copied from its root-relative
runtime bank. Native Xcode projects remain hand-maintained; the generator does
not rewrite `project.pbxproj`.

## Shared Factory boundary

Adding a qualification app does not require a new learning, progress,
persistence, practice, mock-exam, or purchase architecture. Change shared
contracts only for a proven reusable requirement. Qualification-specific exam
rules, terminology, source presentation, branding, and defensible product UX
remain configuration or thin composition.
