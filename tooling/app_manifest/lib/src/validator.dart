import 'dart:io';

import 'package:path/path.dart' as p;

import 'dependency_validation.dart';
import 'generator.dart';
import 'manifest.dart';
import 'native_validation.dart';
import 'question_bank_validation.dart';
import 'repository.dart';
import 'validation_result.dart';

export 'validation_result.dart';

ManifestValidationResult validateRepository(
  Directory repositoryRoot, {
  bool checkGenerated = false,
}) {
  final result = ManifestValidationResult();
  _validateRepositoryLayout(repositoryRoot, result);
  final manifests = <AppManifest>[];
  final manifestFiles = discoverManifestFiles(repositoryRoot);
  if (manifestFiles.isEmpty) {
    result.error('missing_manifest', 'No app.yaml files found.', '.');
    return result;
  }

  for (final file in manifestFiles) {
    final relativePath = p.relative(file.path, from: repositoryRoot.path);
    try {
      final manifest = AppManifest.fromFile(file, repositoryRoot);
      manifests.add(manifest);
      validateManifestSemantics(manifest, result);
    } on ManifestFormatException catch (error) {
      result.error('invalid_manifest', error.message, relativePath);
    }
  }

  validateUniqueIdentities(manifests, result);
  for (final manifest in manifests) {
    validateQuestionBank(repositoryRoot, manifest, result, checkGenerated);
    validateNativeWiring(repositoryRoot, manifest, result);
  }
  validateDependencyBoundaries(repositoryRoot, manifests, result);

  if (checkGenerated && result.isValid) {
    try {
      final expected = buildGeneratedFiles(repositoryRoot, manifests);
      for (final drift in findGeneratedDrift(repositoryRoot, expected)) {
        result.error(
          'generated_manifest_drift',
          'Regenerate committed app-manifest output.',
          drift,
        );
      }
    } on StateError catch (error) {
      result.error('generation_failed', error.message, '.');
    }
  }

  return result;
}

void _validateRepositoryLayout(
  Directory repositoryRoot,
  ManifestValidationResult result,
) {
  if (File(p.join(repositoryRoot.path, 'app.yaml')).existsSync()) {
    result.error(
      'legacy_root_manifest',
      'Root app.yaml is not a monorepo manifest source.',
      'app.yaml',
    );
  }
  if (Directory(p.join(repositoryRoot.path, 'reference_apps')).existsSync()) {
    result.error(
      'legacy_reference_apps',
      'reference_apps/ must not remain after the apps/ migration.',
      'reference_apps',
    );
  }

  final apps = Directory(p.join(repositoryRoot.path, 'apps'));
  if (!apps.existsSync()) {
    result.error(
      'missing_apps_directory',
      'Repository root must contain apps/.',
      'apps',
    );
    return;
  }
  for (final entity in apps.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || p.basename(entity.path) != 'app.yaml') continue;
    final relativePath = p.relative(entity.path, from: repositoryRoot.path);
    if (p.split(relativePath).length != 3) {
      result.error(
        'nested_app_manifest',
        'Only apps/<app>/app.yaml is a manifest source.',
        relativePath,
      );
    }
  }
}

void validateManifestSemantics(
  AppManifest manifest,
  ManifestValidationResult result,
) {
  final location = manifest.sourcePath;
  if (manifest.schemaVersion != 1) {
    result.error(
      'unsupported_schema_version',
      'schema_version must be 1.',
      location,
    );
  }
  if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(manifest.appKey)) {
    result.error('invalid_app_key', 'app_key has an invalid format.', location);
  }
  for (final entry in {
    'display_name': manifest.displayName,
    'ios.display_name': manifest.ios.displayName,
    'android.display_name': manifest.android.displayName,
  }.entries) {
    if (entry.value.trim().isEmpty) {
      result.error(
        'empty_display_name',
        '${entry.key} must not be empty.',
        location,
      );
    }
  }

  _validatePlatformIdentifiers(manifest, result);
  _validateUrls(manifest, result);
  _validateQuestionConfiguration(manifest, result);
  _validateProducts(manifest, result);
  _validateExamAndBranding(manifest, result);
  _validateFactory(manifest, result);
}

void validateUniqueIdentities(
  Iterable<AppManifest> manifests,
  ManifestValidationResult result,
) {
  _validateUnique(
    manifests,
    (manifest) => manifest.appKey,
    'duplicate_app_key',
    'app_key',
    result,
  );
  _validateUnique(
    manifests,
    (manifest) => manifest.ios.identifier,
    'duplicate_ios_bundle_id',
    'iOS bundle ID',
    result,
  );
  _validateUnique(
    manifests,
    (manifest) => manifest.android.identifier,
    'duplicate_android_application_id',
    'Android application ID',
    result,
  );
}

void _validatePlatformIdentifiers(
  AppManifest manifest,
  ManifestValidationResult result,
) {
  final location = manifest.sourcePath;
  final appleIdentifier = RegExp(r'^[A-Za-z][A-Za-z0-9-]*(\.[A-Za-z0-9-]+)+$');
  if (!appleIdentifier.hasMatch(manifest.ios.identifier)) {
    result.error(
      'invalid_ios_bundle_id',
      'Invalid iOS bundle ID: ${manifest.ios.identifier}',
      location,
    );
  }
  final androidIdentifier = RegExp(
    r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
  );
  if (!androidIdentifier.hasMatch(manifest.android.identifier)) {
    result.error(
      'invalid_android_application_id',
      'Invalid Android application ID: ${manifest.android.identifier}',
      location,
    );
  }
}

void _validateUrls(AppManifest manifest, ManifestValidationResult result) {
  for (final entry in {
    'support': manifest.urls.support,
    'privacy': manifest.urls.privacy,
    if (manifest.urls.marketing != null) 'marketing': manifest.urls.marketing!,
  }.entries) {
    final uri = Uri.tryParse(entry.value);
    if (uri == null ||
        !(uri.scheme == 'https' || uri.scheme == 'http') ||
        uri.host.isEmpty) {
      result.error(
        'invalid_url',
        '${entry.key} must be an absolute HTTP(S) URL.',
        manifest.sourcePath,
      );
    }
  }
}

void _validateQuestionConfiguration(
  AppManifest manifest,
  ManifestValidationResult result,
) {
  final location = manifest.sourcePath;
  if (!{
    'legacy_hash_v1',
    'explicit_v1',
  }.contains(manifest.questionIdentityPolicy)) {
    result.error(
      'unsupported_question_identity_policy',
      'Unsupported question identity policy: '
          '${manifest.questionIdentityPolicy}',
      location,
    );
  }
  if (!{
    'legacy_assets_v1',
    'qualification_runtime_v2',
  }.contains(manifest.questionBank.format)) {
    result.error(
      'unsupported_question_bank_format',
      'Unsupported question-bank format: ${manifest.questionBank.format}',
      location,
    );
  }
  for (final entry in {
    'runtime_path': manifest.questionBank.runtimePath,
    'manifest_path': manifest.questionBank.manifestPath,
    if (manifest.questionBank.assetOutput != null)
      'asset_output': manifest.questionBank.assetOutput!,
  }.entries) {
    if (p.isAbsolute(entry.value) || p.split(entry.value).contains('..')) {
      result.error(
        'invalid_repository_path',
        '${entry.key} must be a repository-relative path without ..',
        location,
      );
    }
  }
  if (manifest.questionBank.format == 'qualification_runtime_v2' &&
      manifest.questionIdentityPolicy != 'explicit_v1') {
    result.error(
      'qualification_identity_not_explicit',
      'qualification_runtime_v2 requires explicit_v1 identity.',
      location,
    );
  }
  if (manifest.questionBank.format == 'qualification_runtime_v2' &&
      manifest.questionBank.assetOutput == null) {
    result.error(
      'missing_asset_output',
      'qualification_runtime_v2 requires asset_output.',
      location,
    );
  }
}

void _validateProducts(AppManifest manifest, ManifestValidationResult result) {
  final products = manifest.monetization.products;
  final productIds = products.productIds.toList();
  if (productIds.toSet().length != productIds.length) {
    result.error(
      'duplicate_product_id',
      'Product IDs must be unique within one app.',
      manifest.sourcePath,
    );
  }
  final deckIds = products.decks.map((product) => product.deckId).toList();
  if (deckIds.toSet().length != deckIds.length) {
    result.error(
      'duplicate_deck_id',
      'Deck IDs must be unique within one app.',
      manifest.sourcePath,
    );
  }

  switch (manifest.monetization.architecture) {
    case 'legacyDeckBundles':
      if (products.decks.isEmpty ||
          products.bundle5ProductId == null ||
          products.bundleAllProductId == null ||
          products.proProductId == null) {
        result.error(
          'missing_legacy_product',
          'legacyDeckBundles requires deck, bundle5, bundleAll, and Pro IDs.',
          manifest.sourcePath,
        );
      }
      if (products.fullUnlockProductId != null) {
        result.error(
          'mixed_monetization_products',
          'legacyDeckBundles must not declare full_unlock_product_id.',
          manifest.sourcePath,
        );
      }
    case 'singleFullUnlock':
      if (products.fullUnlockProductId == null) {
        result.error(
          'missing_full_unlock_product',
          'singleFullUnlock requires full_unlock_product_id.',
          manifest.sourcePath,
        );
      }
      if (products.decks.isNotEmpty ||
          products.bundle5ProductId != null ||
          products.bundleAllProductId != null ||
          products.proProductId != null) {
        result.error(
          'mixed_monetization_products',
          'singleFullUnlock must not include legacy products.',
          manifest.sourcePath,
        );
      }
    default:
      result.error(
        'unsupported_monetization_architecture',
        'Unsupported monetization architecture: '
            '${manifest.monetization.architecture}',
        manifest.sourcePath,
      );
  }
}

void _validateExamAndBranding(
  AppManifest manifest,
  ManifestValidationResult result,
) {
  if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(manifest.branding.seedColor)) {
    result.error(
      'invalid_seed_color',
      'branding.seed_color must use #RRGGBB.',
      manifest.sourcePath,
    );
  }
  if (manifest.exam.questionCount != null && manifest.exam.questionCount! < 1) {
    result.error(
      'invalid_exam_question_count',
      'exam.question_count must be positive when set.',
      manifest.sourcePath,
    );
  }
  final passPercent = manifest.exam.overallPassPercent;
  if (passPercent != null && (passPercent < 1 || passPercent > 100)) {
    result.error(
      'invalid_overall_pass_percent',
      'exam.overall_pass_percent must be between 1 and 100.',
      manifest.sourcePath,
    );
  }
  final timeLimit = manifest.exam.timeLimitMinutes;
  if (timeLimit != null && timeLimit < 1) {
    result.error(
      'invalid_exam_time_limit',
      'exam.time_limit_minutes must be positive when set.',
      manifest.sourcePath,
    );
  }
  final allocations = manifest.exam.allocations;
  final allocationIds = allocations.map((item) => item.unitId).toList();
  if (allocationIds.toSet().length != allocationIds.length) {
    result.error(
      'duplicate_exam_allocation',
      'exam.allocations unit_id values must be unique.',
      manifest.sourcePath,
    );
  }
  if (allocations.any((item) => item.questionCount < 1)) {
    result.error(
      'invalid_exam_allocation_count',
      'exam allocation question_count must be positive.',
      manifest.sourcePath,
    );
  }
  final questionCount = manifest.exam.questionCount;
  if (allocations.isNotEmpty &&
      questionCount != null &&
      allocations.fold<int>(0, (sum, item) => sum + item.questionCount) !=
          questionCount) {
    result.error(
      'exam_allocation_total_mismatch',
      'exam allocations must sum to exam.question_count.',
      manifest.sourcePath,
    );
  }
  final rules = manifest.exam.sectionPassRules;
  final ruleIds = rules.map((item) => item.unitId).toList();
  if (ruleIds.toSet().length != ruleIds.length) {
    result.error(
      'duplicate_section_pass_rule',
      'exam.section_pass_rules unit_id values must be unique.',
      manifest.sourcePath,
    );
  }
  if (rules.any(
    (rule) => rule.minimumPercent < 1 || rule.minimumPercent > 100,
  )) {
    result.error(
      'invalid_section_pass_percent',
      'Section minimum_percent must be between 1 and 100.',
      manifest.sourcePath,
    );
  }
}

void _validateFactory(AppManifest manifest, ManifestValidationResult result) {
  final factory = manifest.factory;
  if (factory == null) return;
  const supportedModes = {
    'unit_practice',
    'random_practice',
    'unanswered_practice',
    'incorrect_practice',
    'retry',
    'mock_exam',
  };
  if (manifest.monetization.architecture != 'singleFullUnlock') {
    result.error(
      'factory_monetization_not_supported',
      'Factory v1 requires singleFullUnlock.',
      manifest.sourcePath,
    );
  }
  if (manifest.questionBank.format != 'qualification_runtime_v2' ||
      manifest.questionBank.assetOutput == null) {
    result.error(
      'factory_question_bank_not_supported',
      'Factory v1 requires a generated qualification_runtime_v2 asset.',
      manifest.sourcePath,
    );
  }
  if (factory.enabledModes.toSet().length != factory.enabledModes.length ||
      factory.enabledModes.any((mode) => !supportedModes.contains(mode))) {
    result.error(
      'invalid_factory_learning_modes',
      'factory.enabled_modes must contain unique supported modes.',
      manifest.sourcePath,
    );
  }
  if (!factory.enabledModes.contains('unit_practice')) {
    result.error(
      'missing_factory_unit_practice',
      'Factory v1 requires unit_practice.',
      manifest.sourcePath,
    );
  }
  if (factory.enabledModes.contains('mock_exam') &&
      (manifest.exam.profileVersion == null ||
          manifest.exam.questionCount == null)) {
    result.error(
      'mock_exam_profile_missing',
      'mock_exam requires profile_version and question_count.',
      manifest.sourcePath,
    );
  }
  if (factory.practiceQuestionCount < 1 || factory.recentWindowSize < 1) {
    result.error(
      'invalid_factory_learning_window',
      'Factory practice count and recent window must be positive.',
      manifest.sourcePath,
    );
  }
  if (factory.recommendationEnabled && !factory.weaknessEnabled) {
    result.error(
      'recommendation_requires_weakness',
      'Factory recommendation requires the weakness baseline.',
      manifest.sourcePath,
    );
  }
}

void _validateUnique(
  Iterable<AppManifest> manifests,
  String Function(AppManifest manifest) valueOf,
  String code,
  String label,
  ManifestValidationResult result,
) {
  final seen = <String, String>{};
  for (final manifest in manifests) {
    final value = valueOf(manifest);
    final firstPath = seen[value];
    if (firstPath != null) {
      result.error(
        code,
        'Duplicate $label $value; first declared in $firstPath.',
        manifest.sourcePath,
      );
    } else {
      seen[value] = manifest.sourcePath;
    }
  }
}
