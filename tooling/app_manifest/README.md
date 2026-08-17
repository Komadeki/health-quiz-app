# App manifest tooling

`app.yaml` is the build-time source of truth for app identity, question-bank,
identity-policy, monetization, exam, and branding values. Apps never load YAML
at runtime.

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
