# Drone second-class app

This Flutter app ships the production `drone_second_class` experience for
`二等無人航空機 学科対策`.

It is the Qualification App Factory v1 Reference Product. Drone production is
a thin generated-definition composition; shared learning, local history,
practice, progress, mock exam, recommendation, and purchase behavior live in
`packages/quiz_engine` and `packages/qualification_app`.

The production entrypoint is `lib/main.dart`. It loads the generated 188-question
runtime, offers four unit sessions, keeps progress on-device, and uses one
non-consumable full unlock:

- Free: 20 questions, five in each unit.
- Full unlock: all 188 questions (20 free + 168 premium).
- Product ID: `drone_second_class_full_unlock`.
- Backend, login, external telemetry, and Prediction: none.

The historical V0-Panel is preserved behind `lib/main_validation.dart`. It is a
separate validation entrypoint and is not routed from the production app. Its
source bank is the frozen snapshot under
`question_banks/drone_second_class/validation/formal_snapshot/`; it does not read
live production authoring.

The validation protocol, bundle, and manifest remain in the repository for V0
tooling and automated tests, but are intentionally not declared as production
Flutter assets. After a production iOS build, verify that boundary with:

```bash
python3 tool/verify_production_asset_bundle.py \
  --flutter-assets build/ios/iphoneos/Runner.app/Frameworks/App.framework/flutter_assets
```

To check the copied validation bundle assets from the repository root:

```bash
python3 apps/drone_second_class/tool/sync_validation_assets.py --check
```

`main_validation.dart` and its Researcher PIN flow remain historical
validation-only source. They must not be launched through this production app
configuration or stored in the production Flutter asset bundle.

Production identity and external URLs are generated from `app.yaml`. Do not
hand-edit generated manifest files or the synced question-bank asset.
