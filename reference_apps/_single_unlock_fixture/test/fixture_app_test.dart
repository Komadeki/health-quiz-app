import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:single_unlock_fixture/fixture_app.dart';
import 'package:single_unlock_fixture/generated/app_manifest.g.dart';

void main() {
  testWidgets('app boots, loads two active cards, and unlocks premium', (
    tester,
  ) async {
    await tester.pumpWidget(const FixtureApp());
    await tester.pumpAndSettle();

    expect(find.text(GeneratedAppManifest.displayName), findsOneWidget);
    expect(find.text('2 active questions'), findsOneWidget);
    expect(find.text('free / 利用可能'), findsOneWidget);
    expect(find.text('premium / ロック中'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fixture-full-unlock')));
    await tester.pumpAndSettle();

    expect(find.text('premium / 利用可能'), findsOneWidget);
    expect(find.text('premium / ロック中'), findsNothing);
  });
}
