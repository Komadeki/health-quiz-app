import 'dart:convert';

import 'package:crypto/crypto.dart';

const expectedValidationProvenance = ValidationProvenance(
  bankRevision: 'drone-second-class-v0-core-2026-08-19',
  formalSnapshotCommitSha: '61eb6962416e6cd91f22cbf96126244ff760fcc6',
  formalSnapshotSourceHash:
      'sha256:19e4ce34e479c6a2b4afda12a30ada0efb173cf7fbe0c360c9e7b88006a82f08',
  validationProtocolVersion: 'drone-second-class-v0-panel-protocol-v1',
  validationBundleHash:
      'sha256:6c971d88bed58fd635891482f1d153c1787270e19aee61c6473ef50473a01ae2',
);

class ValidationProvenance {
  const ValidationProvenance({
    required this.bankRevision,
    required this.formalSnapshotCommitSha,
    required this.formalSnapshotSourceHash,
    required this.validationProtocolVersion,
    required this.validationBundleHash,
  });

  final String bankRevision;
  final String formalSnapshotCommitSha;
  final String formalSnapshotSourceHash;
  final String validationProtocolVersion;
  final String validationBundleHash;

  Map<String, Object?> toJson() => <String, Object?>{
        'bank_revision': bankRevision,
        'formal_snapshot_commit_sha': formalSnapshotCommitSha,
        'formal_snapshot_source_hash': formalSnapshotSourceHash,
        'validation_protocol_version': validationProtocolVersion,
        'validation_bundle_hash': validationBundleHash,
      };

  factory ValidationProvenance.fromJson(Map<String, Object?> json) {
    return ValidationProvenance(
      bankRevision: json['bank_revision']! as String,
      formalSnapshotCommitSha: json['formal_snapshot_commit_sha']! as String,
      formalSnapshotSourceHash: json['formal_snapshot_source_hash']! as String,
      validationProtocolVersion: json['validation_protocol_version']! as String,
      validationBundleHash: json['validation_bundle_hash']! as String,
    );
  }

  void requireExpected() {
    if (canonicalJson(toJson()) !=
        canonicalJson(expectedValidationProvenance.toJson())) {
      throw const FormatException(
        'Validation provenance does not match the immutable V0P-1 contract.',
      );
    }
  }
}

String canonicalJson(Object? value) {
  Object? normalize(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: normalize(item[key]),
      };
    }
    if (item is List) {
      return item.map(normalize).toList(growable: false);
    }
    return item;
  }

  return jsonEncode(normalize(value));
}

String canonicalSha256(Object? value) {
  return 'sha256:${sha256.convert(utf8.encode(canonicalJson(value)))}';
}
