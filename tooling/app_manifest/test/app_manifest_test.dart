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
      '${repositoryRoot.path}/reference_apps/_single_unlock_fixture/app.yaml',
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
      '${repositoryRoot.path}/reference_apps/_single_unlock_fixture/app.yaml',
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
      '${repositoryRoot.path}/reference_apps/_single_unlock_fixture/app.yaml',
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
