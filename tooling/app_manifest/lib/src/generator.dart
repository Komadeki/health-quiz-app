import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'manifest.dart';

const generatedNotice = 'GENERATED FILE - DO NOT EDIT';

final class GeneratedFile {
  const GeneratedFile({required this.relativePath, required this.bytes});

  final String relativePath;
  final List<int> bytes;
}

List<GeneratedFile> buildGeneratedFiles(
  Directory repositoryRoot,
  Iterable<AppManifest> manifests,
) {
  final generated = <GeneratedFile>[];
  for (final manifest in manifests) {
    generated
      ..add(
        GeneratedFile(
          relativePath: manifest.appPath('lib/generated/app_manifest.g.dart'),
          bytes: utf8.encode(_renderDart(manifest)),
        ),
      )
      ..add(
        GeneratedFile(
          relativePath: manifest.appPath('ios/Flutter/AppManifest.xcconfig'),
          bytes: utf8.encode(_renderXcconfig(manifest)),
        ),
      )
      ..add(
        GeneratedFile(
          relativePath: manifest.appPath('android/app/app-manifest.properties'),
          bytes: utf8.encode(_renderAndroidProperties(manifest)),
        ),
      )
      ..add(
        GeneratedFile(
          relativePath: manifest.appPath(
            'android/app/src/main/res/values/app_manifest.xml',
          ),
          bytes: utf8.encode(_renderAndroidResource(manifest)),
        ),
      );

    final assetOutput = manifest.questionBank.assetOutput;
    if (assetOutput != null) {
      final runtime = File(
        p.join(repositoryRoot.path, manifest.questionBank.runtimePath),
      );
      if (!runtime.existsSync()) {
        throw StateError('Missing question-bank runtime: ${runtime.path}');
      }
      generated.add(
        GeneratedFile(
          relativePath: assetOutput,
          bytes: runtime.readAsBytesSync(),
        ),
      );
    }
  }
  generated.sort(
    (left, right) => left.relativePath.compareTo(right.relativePath),
  );
  return List.unmodifiable(generated);
}

List<String> writeGeneratedFiles(
  Directory repositoryRoot,
  Iterable<GeneratedFile> generatedFiles,
) {
  final written = <String>[];
  for (final generated in generatedFiles) {
    final file = File(p.join(repositoryRoot.path, generated.relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(generated.bytes);
    written.add(generated.relativePath);
  }
  return written;
}

List<String> findGeneratedDrift(
  Directory repositoryRoot,
  Iterable<GeneratedFile> generatedFiles,
) {
  final drift = <String>[];
  for (final generated in generatedFiles) {
    final file = File(p.join(repositoryRoot.path, generated.relativePath));
    if (!file.existsSync() ||
        !_bytesEqual(file.readAsBytesSync(), generated.bytes)) {
      drift.add(generated.relativePath);
    }
  }
  return drift;
}

String _renderDart(AppManifest manifest) {
  final catalog = manifest.monetization.products;
  final deckProducts = catalog.decks.isEmpty
      ? '<DeckProduct>[]'
      : '[\n${catalog.decks.map((product) => '      DeckProduct(deckId: ${_dartString(product.deckId)}, productId: ${_dartString(product.productId)}),').join('\n')}\n    ]';
  final architecture = switch (manifest.monetization.architecture) {
    'legacyDeckBundles' => 'PurchaseArchitecture.legacyDeckBundles',
    'singleFullUnlock' => 'PurchaseArchitecture.singleFullUnlock',
    _ => throw StateError(
        'Unsupported monetization architecture: '
        '${manifest.monetization.architecture}',
      ),
  };
  final entitlementPolicy = switch (manifest.monetization.architecture) {
    'legacyDeckBundles' => 'LegacyDeckBundleEntitlementPolicy()',
    'singleFullUnlock' => 'SingleFullUnlockEntitlementPolicy()',
    _ => throw StateError('Unsupported monetization architecture.'),
  };
  final identityPolicy = switch (manifest.questionIdentityPolicy) {
    'legacy_hash_v1' => 'LegacyHashQuestionIdentityV1()',
    'explicit_v1' => 'ExplicitQuestionIdentityV1()',
    _ => throw StateError(
        'Unsupported question identity policy: '
        '${manifest.questionIdentityPolicy}',
      ),
  };
  final assetPath = manifest.questionBank.assetOutput == null
      ? null
      : p.relative(
          manifest.questionBank.assetOutput!,
          from: manifest.appDirectory,
        );
  final factory = manifest.factory;
  final factoryDefinition = factory == null
      ? ''
      : _renderFactoryDefinition(manifest, factory, assetPath!);

  return '''// $generatedNotice.
// Generated from app.yaml by tooling/app_manifest.
// ignore_for_file: unnecessary_nullable_for_final_variable_declarations

import 'package:quiz_engine/quiz_engine.dart';

abstract final class GeneratedAppManifest {
  static const int schemaVersion = ${manifest.schemaVersion};
  static const String appKey = ${_dartString(manifest.appKey)};
  static const String displayName = ${_dartString(manifest.displayName)};
  static const String devDisplayName = ${_dartString(manifest.devDisplayName)};
  static const String qaDisplayName = ${_dartString(manifest.qaDisplayName)};

  static const String publisher = ${_dartString(manifest.publisher)};
  static const String brandName = ${_dartString(manifest.brandName)};
  static const String legalese = ${_dartString(manifest.legalese)};

  static const String iosBundleId = ${_dartString(manifest.ios.identifier)};
  static const String iosDisplayName = ${_dartString(manifest.ios.displayName)};
  static const String androidApplicationId = ${_dartString(manifest.android.identifier)};
  static const String androidDisplayName = ${_dartString(manifest.android.displayName)};

  static const String supportUrl = ${_dartString(manifest.urls.support)};
  static const String privacyUrl = ${_dartString(manifest.urls.privacy)};
  static const String? marketingUrl = ${_nullableDartString(manifest.urls.marketing)};

  static const String questionBankFormat = ${_dartString(manifest.questionBank.format)};
  static const String questionBankRuntimePath = ${_dartString(manifest.questionBank.runtimePath)};
  static const String questionBankManifestPath = ${_dartString(manifest.questionBank.manifestPath)};
  static const String? questionBankAssetPath = ${_nullableDartString(assetPath)};

  static const ProductCatalog productCatalog = ProductCatalog(
    deckProducts: $deckProducts,
    bundle5ProductId: ${_nullableDartString(catalog.bundle5ProductId)},
    bundleAllProductId: ${_nullableDartString(catalog.bundleAllProductId)},
    proProductId: ${_nullableDartString(catalog.proProductId)},
    fullUnlockProductId: ${_nullableDartString(catalog.fullUnlockProductId)},
  );

  static const MonetizationDefinition monetizationDefinition =
      MonetizationDefinition(
        architecture: $architecture,
        productCatalog: productCatalog,
        entitlementPolicy: $entitlementPolicy,
      );

  static const QuestionIdentityPolicy questionIdentityPolicy =
      $identityPolicy;

  static const String? examProfileVersion = ${_nullableDartString(manifest.exam.profileVersion)};
  static const int? examQuestionCount = ${manifest.exam.questionCount ?? 'null'};
  static const int? examTimeLimitMinutes = ${manifest.exam.timeLimitMinutes ?? 'null'};
  static const int? examOverallPassPercent = ${manifest.exam.overallPassPercent ?? 'null'};

  static const String themeKey = ${_dartString(manifest.branding.themeKey)};
  static const String seedColor = ${_dartString(manifest.branding.seedColor)};$factoryDefinition
}
''';
}

String _renderFactoryDefinition(
  AppManifest manifest,
  FactoryManifest factory,
  String assetPath,
) {
  final modes = factory.enabledModes
      .map((mode) => 'LearningModeV1.${_learningModeName(mode)}')
      .join(', ');
  final allocations = manifest.exam.allocations
      .map(
        (allocation) =>
            'ExamUnitAllocationV1(unitId: ${_dartString(allocation.unitId)}, '
            'questionCount: ${allocation.questionCount})',
      )
      .join(', ');
  final sectionRules = manifest.exam.sectionPassRules
      .map(
        (rule) => 'ExamSectionPassRuleV1(unitId: ${_dartString(rule.unitId)}, '
            'minimumPercent: ${rule.minimumPercent})',
      )
      .join(', ');
  final examProfile = manifest.exam.profileVersion == null
      ? 'null'
      : '''MockExamProfileV1(
        profileVersion: ${_dartString(manifest.exam.profileVersion!)},
        questionCount: ${manifest.exam.questionCount},
        timeLimitMinutes: ${manifest.exam.timeLimitMinutes ?? 'null'},
        allocations: [$allocations],
        overallPassPercent: ${manifest.exam.overallPassPercent ?? 'null'},
        sectionPassRules: [$sectionRules],
        shuffleQuestions: ${manifest.exam.shuffleQuestions},
      )''';
  return '''

  static final QualificationAppDefinition definition =
      QualificationAppDefinition(
        appKey: appKey,
        displayName: displayName,
        publisher: publisher,
        brandName: brandName,
        legalese: legalese,
        urls: const QualificationUrls(
          support: supportUrl,
          privacy: privacyUrl,
          marketing: marketingUrl,
        ),
        questionBankAsset: ${_dartString(assetPath)},
        questionIdentityPolicy: questionIdentityPolicy,
        monetization: monetizationDefinition,
        examProfile: $examProfile,
        branding: const QualificationBranding(
          themeKey: themeKey,
          seedColorHex: seedColor,
        ),
        learningProduct: const LearningProductProfileV1(
          appVersion: ${_dartString(factory.appVersion)},
          homeHeadline: ${_dartString(factory.homeHeadline)},
          sourceLabel: ${_dartString(factory.sourceLabel)},
          enabledModes: {$modes},
          practiceQuestionCount: ${factory.practiceQuestionCount},
          recentWindowSize: ${factory.recentWindowSize},
          progressEnabled: ${factory.progressEnabled},
          historyEnabled: ${factory.historyEnabled},
          weaknessEnabled: ${factory.weaknessEnabled},
          recommendationEnabled: ${factory.recommendationEnabled},
        ),
      );''';
}

String _learningModeName(String wireName) => switch (wireName) {
      'unit_practice' => 'unitPractice',
      'random_practice' => 'randomPractice',
      'unanswered_practice' => 'unansweredPractice',
      'incorrect_practice' => 'incorrectPractice',
      'retry' => 'retry',
      'mock_exam' => 'mockExam',
      _ => throw StateError('Unsupported Factory learning mode: $wireName'),
    };

String _renderXcconfig(AppManifest manifest) => '''// $generatedNotice.
// Generated from app.yaml by tooling/app_manifest.
APP_BUNDLE_ID=${manifest.ios.identifier}
APP_DISPLAY_NAME=${manifest.ios.displayName}
''';

String _renderAndroidProperties(AppManifest manifest) => '''# $generatedNotice.
# Generated from app.yaml by tooling/app_manifest.
APP_APPLICATION_ID=${manifest.android.identifier}
APP_DISPLAY_NAME=${manifest.android.displayName}
''';

String _renderAndroidResource(AppManifest manifest) =>
    '''<?xml version="1.0" encoding="utf-8"?>
<!-- $generatedNotice. Generated from app.yaml by tooling/app_manifest. -->
<resources>
    <string name="app_name">${_xmlEscape(manifest.android.displayName)}</string>
</resources>
''';

String _dartString(String value) => jsonEncode(value);

String _nullableDartString(String? value) =>
    value == null ? 'null' : _dartString(value);

String _xmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
