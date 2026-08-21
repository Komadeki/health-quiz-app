# Drone second-class app

This Flutter app ships the production `drone_second_class` experience for
`二等無人航空機 学科対策`.

It is the Qualification App Factory v1 Reference Product. Drone production is
a thin generated-definition composition; shared learning, local history,
practice, progress, mock exam, recommendation, and purchase behavior live in
`packages/quiz_engine` and `packages/qualification_app`.

The production entrypoint is `lib/main.dart`. It loads the generated 100-question
runtime, offers four unit sessions, keeps progress on-device, and uses one
non-consumable full unlock:

- Free: 20 questions, five in each unit.
- Full unlock: all 100 questions.
- Product ID: `drone_second_class_full_unlock`.
- Backend, login, external telemetry, and Prediction: none.

The historical V0-Panel is preserved behind `lib/main_validation.dart`. It is a
separate validation entrypoint and is not routed from the production app. Its
source bank is the frozen snapshot under
`question_banks/drone_second_class/validation/formal_snapshot/`; it does not read
live production authoring.

To check the copied validation bundle assets from the repository root:

```bash
python3 apps/drone_second_class/tool/sync_validation_assets.py --check
```

The validation runner still requires an operator-supplied Researcher PIN and
must never store that PIN in the repository:

```bash
flutter run -t lib/main_validation.dart \
  --dart-define=V0P3_RESEARCHER_PIN=<operator-selected-value>
```

Production identity and external URLs are generated from `app.yaml`. Do not
hand-edit generated manifest files or the synced question-bank asset.
