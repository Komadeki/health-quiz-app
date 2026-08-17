import 'dart:io';

import 'package:app_manifest_tooling/app_manifest.dart';
import 'package:test/test.dart';

void main() {
  final repositoryRoot = findRepositoryRoot();

  test('generation is byte-for-byte deterministic', () {
    final manifests = loadAppManifests(repositoryRoot);
    final first = buildGeneratedFiles(repositoryRoot, manifests);
    final second = buildGeneratedFiles(repositoryRoot, manifests);

    expect(first.map((file) => file.relativePath),
        second.map((file) => file.relativePath));
    for (var index = 0; index < first.length; index++) {
      expect(first[index].bytes, second[index].bytes);
    }
    expect(
      first.where((file) => file.relativePath.endsWith('.g.dart')).every(
            (file) =>
                String.fromCharCodes(file.bytes).contains(generatedNotice),
          ),
      isTrue,
    );
  });

  test('repository manifests and committed generated files validate', () {
    final result = validateRepository(repositoryRoot, checkGenerated: true);
    expect(result.issues, isEmpty);
  });

  test('discovers only direct child app manifests', () {
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      'app_manifest_discovery_test.',
    );
    addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
    File('${temporaryDirectory.path}/apps/health/app.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('app_key: health\n');
    File('${temporaryDirectory.path}/apps/nested/child/app.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('app_key: nested\n');

    final discovered = discoverManifestFiles(temporaryDirectory);

    expect(discovered, hasLength(1));
    expect(
      discovered.single.path,
      endsWith('/apps/health/app.yaml'),
    );
  });

  test('repository question-bank paths are root-relative', () {
    final manifests = {
      for (final manifest in loadAppManifests(repositoryRoot))
        manifest.appKey: manifest,
    };

    expect(
      manifests['health']!.questionBank.runtimePath,
      'apps/health/assets/decks',
    );
    expect(
      manifests['health']!.questionBank.manifestPath,
      'apps/health/test/fixtures/health_question_bank_contract.json',
    );
    expect(
      manifests['qualification_fixture']!.questionBank.assetOutput,
      'apps/_single_unlock_fixture/assets/question_bank/'
      'qualification_fixture_bank.json',
    );
  });

  test('legacy manifest source locations are rejected', () {
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      'legacy_manifest_layout_test.',
    );
    addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
    Directory('${temporaryDirectory.path}/apps').createSync();
    Directory('${temporaryDirectory.path}/reference_apps').createSync();
    File('${temporaryDirectory.path}/app.yaml').writeAsStringSync('legacy');

    final result = validateRepository(temporaryDirectory);

    expect(
      result.issues.map((issue) => issue.code),
      containsAll(['legacy_root_manifest', 'legacy_reference_apps']),
    );
  });

  test('dependency validator rejects app-to-app imports', () {
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      'app_dependency_test.',
    );
    addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
    final manifests = loadAppManifests(repositoryRoot);
    for (final manifest in manifests) {
      final packageName = manifest.appKey == 'health'
          ? 'health_quiz_app'
          : 'single_unlock_fixture';
      File('${temporaryDirectory.path}/${manifest.appDirectory}/pubspec.yaml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
name: $packageName
dependencies:
  quiz_engine:
    path: ../../packages/quiz_engine
''');
      Directory('${temporaryDirectory.path}/${manifest.appDirectory}/lib')
          .createSync(recursive: true);
    }
    File('${temporaryDirectory.path}/packages/quiz_engine/pubspec.yaml')
      ..createSync(recursive: true)
      ..writeAsStringSync('name: quiz_engine\n');
    Directory('${temporaryDirectory.path}/packages/quiz_engine/lib')
        .createSync(recursive: true);
    File('${temporaryDirectory.path}/apps/health/lib/leak.dart')
        .writeAsStringSync(
      "import 'package:single_unlock_fixture/main.dart';\n",
    );
    File('${temporaryDirectory.path}/packages/quiz_engine/lib/leak.dart')
        .writeAsStringSync(
      "import 'package:health_quiz_app/main.dart';\n",
    );
    final result = ManifestValidationResult();

    validateDependencyBoundaries(
      temporaryDirectory,
      manifests,
      result,
    );

    expect(
      result.issues.map((issue) => issue.code),
      containsAll(['app_to_app_import', 'quiz_engine_app_import']),
    );
  });

  test('duplicate app and native identities are rejected', () {
    final manifest = loadAppManifests(repositoryRoot).first;
    final result = ManifestValidationResult();

    validateUniqueIdentities([manifest, manifest], result);

    expect(
      result.issues.map((issue) => issue.code),
      containsAll([
        'duplicate_app_key',
        'duplicate_ios_bundle_id',
        'duplicate_android_application_id',
      ]),
    );
  });

  test('single full unlock rejects legacy products', () {
    final source = File(
      '${repositoryRoot.path}/apps/_single_unlock_fixture/app.yaml',
    ).readAsStringSync();
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      'app_manifest_test.',
    );
    addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
    final manifestFile = File('${temporaryDirectory.path}/app.yaml');
    manifestFile.writeAsStringSync(
      source.replaceFirst(
        'full_unlock_product_id: fixture_full_unlock',
        'full_unlock_product_id: fixture_full_unlock\n'
            '    bundle5_product_id: forbidden_bundle',
      ),
    );
    final manifest = AppManifest.fromFile(manifestFile, temporaryDirectory);
    final result = ManifestValidationResult();

    validateManifestSemantics(manifest, result);

    expect(
      result.issues.map((issue) => issue.code),
      contains('mixed_monetization_products'),
    );
  });

  test('invalid IDs, URLs, policies, and architectures are rejected', () {
    final source = File(
      '${repositoryRoot.path}/apps/_single_unlock_fixture/app.yaml',
    ).readAsStringSync();
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      'app_manifest_invalid_test.',
    );
    addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
    final manifestFile = File('${temporaryDirectory.path}/app.yaml');
    manifestFile.writeAsStringSync(
      source
          .replaceFirst(
            'com.komadeki.qualificationfixture',
            'invalid bundle id',
          )
          .replaceFirst(
            'com.komadeki.qualificationfixture',
            'invalid android id',
          )
          .replaceFirst(
            'https://example.invalid/qualification-fixture/support',
            'not-a-url',
          )
          .replaceFirst('explicit_v1', 'unsupported_identity')
          .replaceFirst('singleFullUnlock', 'unsupported_architecture'),
    );
    final manifest = AppManifest.fromFile(manifestFile, temporaryDirectory);
    final result = ManifestValidationResult();

    validateManifestSemantics(manifest, result);

    expect(
      result.issues.map((issue) => issue.code),
      containsAll([
        'invalid_ios_bundle_id',
        'invalid_android_application_id',
        'invalid_url',
        'unsupported_question_identity_policy',
        'unsupported_monetization_architecture',
      ]),
    );
  });

  test('missing full unlock product is rejected', () {
    final source = File(
      '${repositoryRoot.path}/apps/_single_unlock_fixture/app.yaml',
    ).readAsStringSync();
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      'app_manifest_product_test.',
    );
    addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
    final manifestFile = File('${temporaryDirectory.path}/app.yaml');
    manifestFile.writeAsStringSync(
      source.replaceFirst(
        '  products:\n    full_unlock_product_id: fixture_full_unlock\n',
        '  products: {}\n',
      ),
    );
    final manifest = AppManifest.fromFile(manifestFile, temporaryDirectory);
    final result = ManifestValidationResult();

    validateManifestSemantics(manifest, result);

    expect(
      result.issues.map((issue) => issue.code),
      contains('missing_full_unlock_product'),
    );
  });

  test('missing generated outputs are detected as drift', () {
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      'app_manifest_drift_test.',
    );
    addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
    final generated = buildGeneratedFiles(
      repositoryRoot,
      loadAppManifests(repositoryRoot),
    );

    expect(
      findGeneratedDrift(temporaryDirectory, generated),
      hasLength(generated.length),
    );
  });
}
