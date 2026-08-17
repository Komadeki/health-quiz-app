# Monorepo contract

## Boundaries

Flutter applications are direct children of `apps/`. Shared pure Dart code is
under `packages/`, shared question-bank sources are under `question_banks/`, and
build-time validation lives under `tooling/`. Root `docs/` and `.github/` are
repository-wide.

```text
apps/*
  -> packages/quiz_engine
```

App-to-app imports and path dependencies are forbidden. `quiz_engine` must not
depend on any app. Moving an app does not justify extracting its widgets or
product behavior into another shared package.

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

## Shared-engine freeze

After Phase 2F, adding a qualification app does not normally require changing
`quiz_engine`. Change the shared engine only after a requirement is proven to
be common to multiple applications. Qualification-specific UI and product
behavior stay in that app.
