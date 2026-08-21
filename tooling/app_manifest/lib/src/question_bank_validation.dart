import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'manifest.dart';
import 'validation_result.dart';

void validateQuestionBank(
  Directory repositoryRoot,
  AppManifest manifest,
  ManifestValidationResult result,
  bool checkGenerated,
) {
  final runtime = File(
    p.join(repositoryRoot.path, manifest.questionBank.runtimePath),
  );
  final runtimeDirectory = Directory(runtime.path);
  final manifestFile = File(
    p.join(repositoryRoot.path, manifest.questionBank.manifestPath),
  );
  final runtimeExists = runtime.existsSync() || runtimeDirectory.existsSync();
  if (!runtimeExists) {
    result.error(
      'missing_question_bank_runtime',
      'Question-bank runtime does not exist.',
      manifest.questionBank.runtimePath,
    );
  }
  if (!manifestFile.existsSync()) {
    result.error(
      'missing_question_bank_manifest',
      'Question-bank manifest does not exist.',
      manifest.questionBank.manifestPath,
    );
  }
  if (manifest.questionBank.format != 'qualification_runtime_v2' ||
      !runtime.existsSync() ||
      !manifestFile.existsSync()) {
    return;
  }

  final runtimeJson = _readJsonMap(runtime, result);
  final bankManifest = _readJsonMap(manifestFile, result);
  if (runtimeJson == null || bankManifest == null) return;

  if (runtimeJson['schemaVersion'] != 2) {
    result.error(
      'runtime_schema_mismatch',
      'Qualification runtime schemaVersion must be 2.',
      manifest.questionBank.runtimePath,
    );
  }
  if (bankManifest['schema_version'] != 1) {
    result.error(
      'bank_manifest_schema_mismatch',
      'Question-bank manifest schema_version must be 1.',
      manifest.questionBank.manifestPath,
    );
  }
  if (runtimeJson['appKey'] != manifest.appKey ||
      bankManifest['app_key'] != manifest.appKey) {
    result.error(
      'question_bank_app_key_mismatch',
      'App manifest and question-bank app keys must match.',
      manifest.sourcePath,
    );
  }
  if (runtimeJson['bankRevision'] != bankManifest['bank_revision']) {
    result.error(
      'bank_revision_mismatch',
      'Runtime and bank manifest revisions must match.',
      manifest.questionBank.runtimePath,
    );
  }
  if (runtimeJson['examProfileVersion'] !=
          bankManifest['exam_profile_version'] ||
      runtimeJson['examProfileVersion'] != manifest.exam.profileVersion) {
    result.error(
      'exam_profile_version_mismatch',
      'App manifest, runtime, and bank manifest profile versions must match.',
      manifest.sourcePath,
    );
  }

  final cards = _runtimeCards(
    runtimeJson,
    result,
    manifest.questionBank.runtimePath,
  );
  final unitCounts = _runtimeUnitCounts(runtimeJson);
  if (bankManifest['question_count'] != cards.length ||
      (manifest.exam.questionCount != null &&
          manifest.exam.questionCount != cards.length)) {
    result.error(
      'question_count_mismatch',
      'Runtime, bank manifest, and app exam question counts must match.',
      manifest.sourcePath,
    );
  }
  for (final allocation in manifest.exam.allocations) {
    final actual = unitCounts[allocation.unitId];
    if (actual == null || actual < allocation.questionCount) {
      result.error(
        'exam_allocation_not_satisfied',
        'Exam allocation ${allocation.unitId} requires '
            '${allocation.questionCount} questions, found ${actual ?? 0}.',
        manifest.sourcePath,
      );
    }
  }
  for (final rule in manifest.exam.sectionPassRules) {
    if (!unitCounts.containsKey(rule.unitId)) {
      result.error(
        'section_pass_unit_missing',
        'Section pass rule unit does not exist: ${rule.unitId}.',
        manifest.sourcePath,
      );
    }
  }
  final ids = <String>{};
  for (final card in cards) {
    final stableId = card['stableId'];
    if (stableId is! String || stableId.trim().isEmpty) {
      result.error(
        'explicit_question_id_missing',
        'Every qualification card requires a non-empty stableId.',
        manifest.questionBank.runtimePath,
      );
    } else if (!ids.add(stableId)) {
      result.error(
        'duplicate_explicit_question_id',
        'Duplicate runtime stableId: $stableId',
        manifest.questionBank.runtimePath,
      );
    }
  }

  final expectedHash =
      'sha256:${sha256.convert(utf8.encode(_canonicalJson(runtimeJson)))}';
  if (bankManifest['content_hash'] != expectedHash) {
    result.error(
      'question_bank_content_hash_mismatch',
      'Runtime content does not match bank manifest content_hash.',
      manifest.questionBank.manifestPath,
    );
  }

  if (checkGenerated && manifest.questionBank.assetOutput != null) {
    final asset = File(
      p.join(repositoryRoot.path, manifest.questionBank.assetOutput),
    );
    if (!asset.existsSync() ||
        !_bytesEqual(runtime.readAsBytesSync(), asset.readAsBytesSync())) {
      result.error(
        'question_bank_asset_drift',
        'Generated app asset must exactly match the source runtime bank.',
        manifest.questionBank.assetOutput!,
      );
    }
  }
}

Map<String, int> _runtimeUnitCounts(Map<String, Object?> runtime) {
  final result = <String, int>{};
  final decks = runtime['decks'];
  if (decks is! List<Object?>) return result;
  for (final deck in decks.whereType<Map<String, Object?>>()) {
    final units = deck['units'];
    if (units is! List<Object?>) continue;
    for (final unit in units.whereType<Map<String, Object?>>()) {
      final id = unit['id'];
      final cards = unit['cards'];
      if (id is String && cards is List<Object?>) result[id] = cards.length;
    }
  }
  return result;
}

Map<String, Object?>? _readJsonMap(
  File file,
  ManifestValidationResult result,
) {
  try {
    final value = jsonDecode(file.readAsStringSync());
    if (value is Map<String, Object?>) return value;
  } on FormatException {
    // Report the shared error below.
  }
  result.error('invalid_json', 'Expected a JSON object.', file.path);
  return null;
}

List<Map<String, Object?>> _runtimeCards(
  Map<String, Object?> runtime,
  ManifestValidationResult result,
  String location,
) {
  final cards = <Map<String, Object?>>[];
  final decks = runtime['decks'];
  if (decks is! List<Object?>) {
    result.error(
      'invalid_runtime_decks',
      'Runtime decks must be a list.',
      location,
    );
    return cards;
  }
  for (final deck in decks) {
    if (deck is! Map<String, Object?>) continue;
    final units = deck['units'];
    if (units is! List<Object?>) continue;
    for (final unit in units) {
      if (unit is! Map<String, Object?>) continue;
      final rawCards = unit['cards'];
      if (rawCards is! List<Object?>) continue;
      cards.addAll(rawCards.whereType<Map<String, Object?>>());
    }
  }
  return cards;
}

String _canonicalJson(Object? value) {
  Object? sort(Object? item) {
    if (item is Map<String, Object?>) {
      final sorted = SplayTreeMap<String, Object?>();
      for (final entry in item.entries) {
        sorted[entry.key] = sort(entry.value);
      }
      return sorted;
    }
    if (item is List<Object?>) return item.map(sort).toList();
    return item;
  }

  return jsonEncode(sort(value));
}

bool _bytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
