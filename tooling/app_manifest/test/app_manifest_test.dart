import 'dart:io';
import 'dart:convert';

import 'package:app_manifest_tooling/app_manifest.dart';
import 'package:app_manifest_tooling/src/question_bank_validation.dart';
import 'package:test/test.dart';

final repositoryRoot = findRepositoryRoot();

void main() {
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

  test('mock exam count may be smaller than its runtime bank', () {
    final fixture = _droneQuestionBankFixture(examQuestionCount: 50);
    addTearDown(() => fixture.directory.deleteSync(recursive: true));

    expect(fixture.validate().issues, isEmpty);
  });

  test('mock exam count may equal its runtime bank', () {
    final fixture = _droneQuestionBankFixture(examQuestionCount: 100);
    addTearDown(() => fixture.directory.deleteSync(recursive: true));

    expect(fixture.validate().issues, isEmpty);
  });

  test('mock exam count cannot exceed its runtime bank', () {
    final fixture = _droneQuestionBankFixture(
      examQuestionCount: 50,
      runtimeQuestionCount: 49,
      bankManifestQuestionCount: 49,
    );
    addTearDown(() => fixture.directory.deleteSync(recursive: true));

    expect(
      fixture.validate().issues.map((issue) => issue.code),
      contains('exam_question_count_exceeds_bank_size'),
    );
  });

  test('bank manifest count must match its full runtime bank', () {
    final fixture = _droneQuestionBankFixture(
      examQuestionCount: 50,
      bankManifestQuestionCount: 99,
    );
    addTearDown(() => fixture.directory.deleteSync(recursive: true));

    expect(
      fixture.validate().issues.map((issue) => issue.code),
      contains('question_count_mismatch'),
    );
  });

  test('Factory definitions are generated only for opted-in qualification apps',
      () {
    final generated = buildGeneratedFiles(
      repositoryRoot,
      loadAppManifests(repositoryRoot),
    );
    String sourceFor(String path) => String.fromCharCodes(
          generated.singleWhere((file) => file.relativePath == path).bytes,
        );

    expect(
      sourceFor('apps/drone_second_class/lib/generated/app_manifest.g.dart'),
      contains('QualificationAppDefinition definition'),
    );
    expect(
      sourceFor(
          'apps/_single_unlock_fixture/lib/generated/app_manifest.g.dart'),
      contains('LearningModeV1.mockExam'),
    );
    expect(
      sourceFor('apps/health/lib/generated/app_manifest.g.dart'),
      isNot(contains('QualificationAppDefinition definition')),
    );
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

  test('invalid Factory mode/profile and learning windows are rejected', () {
    final source = File(
      '${repositoryRoot.path}/apps/_single_unlock_fixture/app.yaml',
    ).readAsStringSync();
    final temporaryDirectory = Directory.systemTemp.createTempSync(
      'app_manifest_factory_test.',
    );
    addTearDown(() => temporaryDirectory.deleteSync(recursive: true));
    final manifestFile = File('${temporaryDirectory.path}/app.yaml');
    manifestFile.writeAsStringSync(
      source
          .replaceFirst(
              '  profile_version: fixture-exam-v1', '  profile_version: null')
          .replaceFirst('  recent_window_size: 5', '  recent_window_size: 0'),
    );
    final manifest = AppManifest.fromFile(manifestFile, temporaryDirectory);
    final result = ManifestValidationResult();

    validateManifestSemantics(manifest, result);

    expect(
      result.issues.map((issue) => issue.code),
      containsAll([
        'mock_exam_profile_missing',
        'invalid_factory_learning_window',
      ]),
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

_DroneQuestionBankFixture _droneQuestionBankFixture({
  required int examQuestionCount,
  int? runtimeQuestionCount,
  int? bankManifestQuestionCount,
}) {
  final directory = Directory.systemTemp.createTempSync(
    'drone_question_bank_fixture.',
  );
  final appYaml = File('${directory.path}/apps/drone_second_class/app.yaml')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      File('${repositoryRoot.path}/apps/drone_second_class/app.yaml')
          .readAsStringSync()
          .replaceFirst(
            '  question_count: 50',
            '  question_count: $examQuestionCount',
          ),
    );
  final runtime = _copyJson(
    'question_banks/drone_second_class/generated/drone_second_class_bank.json',
  );
  final bankManifest = _copyJson(
    'question_banks/drone_second_class/generated/bank_manifest.json',
  );

  if (runtimeQuestionCount != null) {
    _setRuntimeQuestionCount(runtime, runtimeQuestionCount);
  }
  if (bankManifestQuestionCount != null) {
    bankManifest['question_count'] = bankManifestQuestionCount;
  }
  _writeJson(
    directory,
    'question_banks/drone_second_class/generated/drone_second_class_bank.json',
    runtime,
  );
  _writeJson(
    directory,
    'question_banks/drone_second_class/generated/bank_manifest.json',
    bankManifest,
  );

  return _DroneQuestionBankFixture(
    directory,
    AppManifest.fromFile(appYaml, directory),
  );
}

Map<String, dynamic> _copyJson(String relativePath) {
  final source = File('${repositoryRoot.path}/$relativePath');
  return (jsonDecode(source.readAsStringSync())! as Map)
      .cast<String, dynamic>();
}

void _setRuntimeQuestionCount(Map<String, dynamic> runtime, int desiredCount) {
  final units = ((runtime['decks']! as List).single as Map)['units']! as List;
  var remaining = units.fold<int>(
    0,
    (total, unit) => total + ((unit as Map)['cards']! as List).length,
  );
  for (final unit in units.reversed) {
    final cards = (unit as Map)['cards']! as List;
    final removalCount = remaining - desiredCount;
    if (removalCount <= 0) break;
    final countToRemove =
        removalCount < cards.length ? removalCount : cards.length;
    cards.removeRange(
      cards.length - countToRemove,
      cards.length,
    );
    remaining -= countToRemove;
  }
}

void _writeJson(
  Directory directory,
  String relativePath,
  Map<String, dynamic> value,
) {
  File('${directory.path}/$relativePath')
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(value));
}

class _DroneQuestionBankFixture {
  const _DroneQuestionBankFixture(this.directory, this.manifest);

  final Directory directory;
  final AppManifest manifest;

  ManifestValidationResult validate() {
    final result = ManifestValidationResult();
    validateQuestionBank(directory, manifest, result, false);
    return result;
  }
}
