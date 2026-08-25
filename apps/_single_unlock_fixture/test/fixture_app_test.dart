import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:single_unlock_fixture/fixture_app.dart';
import 'package:single_unlock_fixture/generated/app_manifest.g.dart';

void main() {
  testWidgets(
    'non-Drone fixture boots the shared Factory and unlocks premium',
    (tester) async {
      await tester.pumpWidget(const FixtureApp());
      await tester.pumpAndSettle();

      expect(find.text(GeneratedAppManifest.displayName), findsOneWidget);
      expect(find.text('架空資格のFactory検証'), findsOneWidget);
      expect(find.text('1問を無料で体験'), findsOneWidget);
      for (final unitKey in [
        'unit-fixture_safety',
        'unit-fixture_operations',
      ]) {
        final unit = find.byKey(Key(unitKey));
        await tester.scrollUntilVisible(unit, 160);
        expect(unit, findsOneWidget);
      }

      final random = find.byKey(const Key('start-random'));
      await tester.scrollUntilVisible(random, 200);
      expect(random, findsOneWidget);
      expect(find.byKey(const Key('start-mock-exam')), findsOneWidget);

      final purchase = find.byKey(const Key('purchase-full-unlock'));
      await tester.scrollUntilVisible(purchase, 300);
      await tester.drag(find.byType(ListView), const Offset(0, -120));
      await tester.pump();
      await tester.tap(purchase);
      await tester.pumpAndSettle();

      expect(find.text('全2問 解放済み'), findsOneWidget);
    },
  );
}
