import 'dart:convert';

import 'package:flutter/services.dart';

import 'validation_provenance.dart';

typedef ValidationAssetReader = Future<String> Function(String assetKey);

class ValidationQuestion {
  const ValidationQuestion({
    required this.questionId,
    required this.questionVersion,
    required this.prompt,
    required this.choices,
    required this.correctIndex,
    required this.explanation,
    required this.slotId,
    required this.contaminationGroup,
    required this.primaryRole,
    required this.coverageId,
    required this.sentinelId,
    required this.alternateOf,
  });

  final String questionId;
  final int questionVersion;
  final String prompt;
  final List<String> choices;
  final int correctIndex;
  final String explanation;
  final String slotId;
  final String contaminationGroup;
  final String primaryRole;
  final String? coverageId;
  final String? sentinelId;
  final String? alternateOf;

  factory ValidationQuestion.fromJson(Map<String, Object?> json) {
    final metadata =
        (json['validation_metadata']! as Map).cast<String, Object?>();
    return ValidationQuestion(
      questionId: json['question_id']! as String,
      questionVersion: json['question_version']! as int,
      prompt: json['question']! as String,
      choices: (json['choices']! as List).cast<String>(),
      correctIndex: json['correct_index']! as int,
      explanation: json['explanation']! as String,
      slotId: metadata['slot_id']! as String,
      contaminationGroup: metadata['contamination_group'] as String? ??
          metadata['sentinel_id'] as String? ??
          metadata['coverage_id'] as String? ??
          'UNASSIGNED',
      primaryRole: metadata['primary_role']! as String,
      coverageId: metadata['coverage_id'] as String?,
      sentinelId: metadata['sentinel_id'] as String?,
      alternateOf: metadata['alternate_of'] as String?,
    );
  }
}

class ValidationBundle {
  ValidationBundle({
    required this.provenance,
    required this.questions,
    required this.protocol,
  })  : questionsById = <String, ValidationQuestion>{
          for (final question in questions) question.questionId: question,
        },
        questionsBySlot = <String, ValidationQuestion>{
          for (final question in questions) question.slotId: question,
        },
        questionsByCoverage = <String, ValidationQuestion>{
          for (final question in questions)
            if (question.coverageId != null) question.coverageId!: question,
        },
        questionsBySentinel = <String, ValidationQuestion>{
          for (final question in questions)
            if (question.sentinelId != null) question.sentinelId!: question,
        };

  final ValidationProvenance provenance;
  final List<ValidationQuestion> questions;
  final Map<String, Object?> protocol;
  final Map<String, ValidationQuestion> questionsById;
  final Map<String, ValidationQuestion> questionsBySlot;
  final Map<String, ValidationQuestion> questionsByCoverage;
  final Map<String, ValidationQuestion> questionsBySentinel;
}

class ValidationBundleLoader {
  ValidationBundleLoader({
    AssetBundle? assetBundle,
    ValidationAssetReader? assetReader,
  }) : assetReader = assetReader ?? (assetBundle ?? rootBundle).loadString;

  final ValidationAssetReader assetReader;

  Future<ValidationBundle> load() async {
    final values = await Future.wait<String>(<Future<String>>[
      assetReader('assets/validation/protocol.json'),
      assetReader('assets/validation/validation_bundle.json'),
      assetReader('assets/validation/validation_manifest.json'),
    ]);
    final protocol = (jsonDecode(values[0])! as Map).cast<String, Object?>();
    final bundleJson = (jsonDecode(values[1])! as Map).cast<String, Object?>();
    final manifest = (jsonDecode(values[2])! as Map).cast<String, Object?>();

    final provenance = ValidationProvenance(
      bankRevision: bundleJson['bank_revision']! as String,
      formalSnapshotCommitSha:
          bundleJson['formal_snapshot_commit_sha']! as String,
      formalSnapshotSourceHash:
          bundleJson['formal_snapshot_source_hash']! as String,
      validationProtocolVersion:
          bundleJson['validation_protocol_version']! as String,
      validationBundleHash: manifest['validation_bundle_hash']! as String,
    );
    provenance.requireExpected();
    _requireEqual(protocol['bank_revision'], provenance.bankRevision);
    _requireEqual(
      protocol['formal_snapshot_commit_sha'],
      provenance.formalSnapshotCommitSha,
    );
    _requireEqual(
      protocol['formal_snapshot_source_hash'],
      provenance.formalSnapshotSourceHash,
    );
    _requireEqual(
      protocol['validation_protocol_version'],
      provenance.validationProtocolVersion,
    );
    _requireEqual(manifest['bank_revision'], provenance.bankRevision);
    _requireEqual(
      manifest['formal_snapshot_commit_sha'],
      provenance.formalSnapshotCommitSha,
    );
    _requireEqual(
      manifest['formal_snapshot_source_hash'],
      provenance.formalSnapshotSourceHash,
    );
    _requireEqual(
      manifest['validation_protocol_version'],
      provenance.validationProtocolVersion,
    );
    _requireEqual(
      canonicalSha256(bundleJson),
      provenance.validationBundleHash,
    );
    if (bundleJson['artifact_purpose'] != 'VALIDATION_ONLY' ||
        manifest['artifact_purpose'] != 'VALIDATION_ONLY' ||
        manifest['bundle_question_count'] != 100) {
      throw const FormatException('Validation-only bundle contract failed.');
    }

    final questions = (bundleJson['questions']! as List)
        .map(
          (item) => ValidationQuestion.fromJson(
            (item! as Map).cast<String, Object?>(),
          ),
        )
        .toList(growable: false);
    if (questions.length != 100 ||
        questions.any(
          (question) => int.parse(question.questionId.split('-').last) > 100,
        )) {
      throw const FormatException('Unexpected validation question namespace.');
    }
    return ValidationBundle(
      provenance: provenance,
      questions: questions,
      protocol: protocol,
    );
  }

  void _requireEqual(Object? actual, Object? expected) {
    if (actual != expected) {
      throw const FormatException('Validation provenance mismatch.');
    }
  }
}
