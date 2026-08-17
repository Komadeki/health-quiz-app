import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/generated/app_manifest.g.dart';
import 'package:health_quiz_app/quiz_app_definition.dart';

void main() {
  test('health generated manifest freezes authoritative app values', () {
    expect(GeneratedAppManifest.appKey, 'health');
    expect(GeneratedAppManifest.displayName, '高校保健 一問一答');
    expect(GeneratedAppManifest.iosDisplayName, 'Health Quiz App');
    expect(GeneratedAppManifest.androidDisplayName, '高校保健 一問一答');
    expect(GeneratedAppManifest.iosBundleId, 'jp.mokeke.healthquiz');
    expect(GeneratedAppManifest.androidApplicationId, 'jp.mokeke.healthquiz');
    expect(GeneratedAppManifest.publisher, 'KENTO MORI');
    expect(GeneratedAppManifest.brandName, 'KOMADEKI');
    expect(GeneratedAppManifest.legalese, '© 2025 もけけapp');
    expect(
      GeneratedAppManifest.supportUrl,
      'https://docs.google.com/forms/d/e/'
      '1FAIpQLScnTXDqyc_usBF4tsAvJSuU4GolMPn30iWceCGOwdno9g0Z1w/'
      'viewform?usp=pp_url',
    );
    expect(
      GeneratedAppManifest.privacyUrl,
      'https://sites.google.com/view/mokeke-healthquiz-privacy/',
    );
    expect(GeneratedAppManifest.marketingUrl, isNull);
  });

  test('health compatibility wrapper is assembled from generated values', () {
    expect(currentQuizApp.appKey, GeneratedAppManifest.appKey);
    expect(currentQuizApp.appName, GeneratedAppManifest.displayName);
    expect(currentQuizApp.devAppName, GeneratedAppManifest.devDisplayName);
    expect(currentQuizApp.qaAppName, GeneratedAppManifest.qaDisplayName);
    expect(currentQuizApp.publisherName, GeneratedAppManifest.publisher);
    expect(currentQuizApp.brandName, GeneratedAppManifest.brandName);
    expect(currentQuizApp.legalese, GeneratedAppManifest.legalese);
    expect(currentQuizApp.preferExplicitStableIds, isFalse);
    expect(currentQuizApp.usesLegacyDeckBundles, isTrue);
  });

  test('Phase 2E keeps health runtime title and native compatibility values',
      () {
    expect(
      File('lib/main.dart').readAsStringSync(),
      contains("title: '高校保健一問一答'"),
    );
    expect(
      File('ios/Flutter/AppManifest.xcconfig').readAsStringSync(),
      contains('APP_DISPLAY_NAME=Health Quiz App'),
    );
    expect(
      File('android/app/src/prod/res/values/strings.xml').readAsStringSync(),
      contains('<string name="app_name">高校保健 一問一答</string>'),
    );
  });
}
