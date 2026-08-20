import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/panel_route.dart';
import 'session_models.dart';
import 'session_repository.dart';

class PilotExportArtifact {
  const PilotExportArtifact({
    required this.filename,
    required this.bytes,
    required this.sha256Digest,
  });

  final String filename;
  final List<int> bytes;
  final String sha256Digest;
}

PilotExportArtifact buildPilotExportArtifact(
  ValidationSessionDocument document,
) {
  final completedAt = document.session.completedAt?.toUtc();
  final slotId = document.assignment.assignmentSlotId;
  if (document.session.currentPhase != PanelPhase.complete ||
      completedAt == null ||
      slotId == null) {
    throw StateError('A completed Pilot session is required to export.');
  }
  final timestamp = completedAt
      .toIso8601String()
      .replaceAll('-', '')
      .replaceAll(':', '')
      .replaceAll('.', '');
  final filename =
      'v0p3_${document.session.participantId}_'
      '${document.session.sessionId}_${slotId}_$timestamp.json';
  final bytes = List<int>.unmodifiable(
    utf8.encode('${buildValidationExport(document)}\n'),
  );
  return PilotExportArtifact(
    filename: filename,
    bytes: bytes,
    sha256Digest: 'sha256:${sha256.convert(bytes)}',
  );
}

class PilotExportWriter {
  PilotExportWriter({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectory;

  Future<File> save(PilotExportArtifact artifact) async {
    final support = await _supportDirectory();
    final root = Directory('${support.path}/drone_v0_panel/exports');
    await root.create(recursive: true);
    final target = File('${root.path}/${artifact.filename}');
    if (await target.exists()) {
      final existing = await target.readAsBytes();
      if (!_sameBytes(existing, artifact.bytes)) {
        throw StateError('Existing Pilot export bytes do not match.');
      }
      return target;
    }
    final temporary = File('${target.path}.tmp');
    await temporary.writeAsBytes(artifact.bytes, flush: true);
    await temporary.rename(target.path);
    return target;
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
