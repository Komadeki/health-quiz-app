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

Assignments are explicit JSON inputs. The compiler supports the protocol target
IDs `HAZARD_RISK_M3`, `THIRD_PARTY`, `GNSS`, `AUTO_MANUAL`, and `TEM`; breadth
IDs `HB-1` through `HB-7`; participant-assigned Sentinel IDs; explicit coverage
IDs; and explicit alternate-slot selections. No assignment is sampled or
randomly completed by the runner.

To verify validation asset copies from the repository root:

```bash
python3 apps/drone_second_class/tool/sync_validation_assets.py --check
```

Omit `--check` to refresh the copies deterministically from the bank-side V0P-1
artifacts.
