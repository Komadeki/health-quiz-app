# Drone second-class V0 Panel

This is a validation-only runner for Protocol A. It loads only the copied
artifacts under `assets/validation/`; it never uses the production runtime bank
as its panel source.

**VALIDATION-ONLY IDENTITY — MUST NOT BE USED FOR APP STORE RELEASE.**

The iOS bundle ID and Android application ID are
`com.komadeki.dronesecondclass.v0panel`. URLs and the monetization product ID in
`app.yaml` are non-production placeholders. There is no real IAP, release,
participant assignment policy, prediction algorithm, or production learning UX
in this app.

The generic compiler still accepts explicit assignments and is not a random
allocation engine. V0P-3 Pilot mode adds a separate validator around ten fixed
assignment slots (`EXT-S01` through `EXT-S10`) and keeps the pseudonymous
participant ID separate from the slot ID.

Pilot execution fails closed unless a non-empty Researcher PIN is supplied at
build/run time. Never store the PIN in the repository:

```bash
flutter run --dart-define=V0P3_RESEARCHER_PIN=<operator-selected-value>
```

Completed Pilot sessions must be saved as deterministic JSON before they can
be archived and closed. The app displays the filename, SHA-256, and local saved
path. External transfer is intentionally left to the approved operator-managed
workflow; the app does not upload or automatically send session data.

To verify validation asset copies from the repository root:

```bash
python3 apps/drone_second_class/tool/sync_validation_assets.py --check
```

Omit `--check` to refresh the copies deterministically from the bank-side V0P-1
artifacts.
