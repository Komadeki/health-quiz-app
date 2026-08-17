# Adding a qualification app

Do not begin with code reuse. Confirm the market, user problem, commercial
model, content rights, and product specification first.

1. Finalize the market and product specification.
2. Create an independent Flutter project at `apps/<app_key>`.
3. Add its own direct-child `apps/<app_key>/app.yaml`.
4. Assign unique iOS Bundle ID and Android application ID values.
5. Author the bank under `question_banks/<app_key>`.
6. Use `explicit_v1` question identity for qualification content.
7. Start with the `singleFullUnlock` monetization architecture unless the
   product specification proves a different requirement.
8. Run app-manifest generation and commit the generated Dart/native files.
9. Validate authored data, generated bank drift, and the Flutter asset copy.
10. Build qualification-specific learning and navigation UX in the app.
11. Add app, contract, identity, purchase, and question-bank tests.
12. Run `flutter build ios --no-codesign` from the app directory.
13. Defer real IAP, signing, App Store Connect, and TestFlight verification to
    the release phase.

## Apple guideline 4.3 product differentiation

A production app must not be a repeated shell with only an icon and question
bank changed. Each qualification needs a deliberate product experience based
on its exam structure, sections, terminology, learning path, mock-exam rules,
weakness reporting, source presentation, and qualification-specific UX.

`apps/_single_unlock_fixture` proves technical boundaries only. Never submit
that fixture shell directly to the App Store.

## Shared code decision

Keep product-specific behavior in the new app. Do not modify `quiz_engine` for
every new product; only move a capability into the engine when multiple real
apps demonstrate the same requirement and contract.
