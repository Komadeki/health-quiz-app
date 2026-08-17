# Health Quiz App

The published health Flutter application lives in this directory. Its Dart
package remains `health_quiz_app`; moving the project into the monorepo does not
change its runtime behavior, native identity, purchases, persistence, or
question identity.

Run app commands from `apps/health`:

```bash
flutter pub get
flutter analyze --no-fatal-infos --no-fatal-warnings
flutter test test/compatibility
flutter test
flutter build ios --no-codesign
```

`app.yaml` is the app identity and product source of truth. Its question-bank
fields are repository-root-relative, while Flutter continues to load the
unchanged `assets/decks/` asset paths declared in this app's `pubspec.yaml`.
