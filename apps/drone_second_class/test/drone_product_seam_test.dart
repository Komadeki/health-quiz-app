import 'package:drone_second_class/generated/app_manifest.g.dart';
import 'package:drone_second_class/production/production_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';

import 'production_test_support.dart';

void main() {
  testWidgets('Drone composes official-source and mock-profile study guidance', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(640, 1600);
    tester.view.devicePixelRatio = 2;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final controller = createProductionController();
    await controller.initialize();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      QualificationProductionApp(
        definition: GeneratedAppManifest.definition,
        controller: controller,
        homeSupplementBuilder: buildDroneHomeSupplement,
      ),
    );

    final guide = find.byKey(const Key('drone-study-guide'));
    expect(guide, findsOneWidget);
    expect(find.text('二等学科の学習ガイド'), findsOneWidget);
    expect(
      find.text(
        '基準資料: ${GeneratedAppManifest.definition.learningProduct.sourceLabel}',
      ),
      findsOneWidget,
    );
    expect(
      find.text('単元別・復習で確認した後、このアプリの模擬試験（50問・30分）で仕上げます。'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('primary-learning-action')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
