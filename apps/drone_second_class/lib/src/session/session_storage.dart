import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/panel_route.dart';
import 'session_models.dart';

abstract interface class ValidationSessionStore {
  Future<ValidationSessionDocument?> loadActive();

  Future<void> write(ValidationSessionDocument document);

  Future<bool> hasParticipant(String participantId);

  Future<void> archive(ValidationSessionDocument document);
}

class FileValidationSessionStore implements ValidationSessionStore {
  FileValidationSessionStore({Future<Directory> Function()? supportDirectory})
    : _supportDirectory = supportDirectory ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _supportDirectory;

  Future<Directory> _root() async {
    final support = await _supportDirectory();
    final root = Directory('${support.path}/drone_v0_panel/sessions');
    await root.create(recursive: true);
    return root;
  }

  @override
  Future<ValidationSessionDocument?> loadActive() async {
    final root = await _root();
    final pointer = File('${root.parent.path}/active_session_id.txt');
    if (!await pointer.exists()) return null;
    final sessionId = (await pointer.readAsString()).trim();
    if (!_safeId.hasMatch(sessionId)) {
      throw const FormatException('Invalid active validation session ID.');
    }
    final file = File('${root.path}/$sessionId.json');
    if (!await file.exists()) {
      throw const FileSystemException('Active validation session is missing.');
    }
    final json = (jsonDecode(await file.readAsString())! as Map)
        .cast<String, Object?>();
    return ValidationSessionDocument.fromJson(json);
  }

  @override
  Future<void> write(ValidationSessionDocument document) async {
    document.validate();
    final root = await _root();
    final sessionId = document.session.sessionId;
    if (!_safeId.hasMatch(sessionId)) {
      throw const FormatException('Invalid validation session ID.');
    }
    final pointer = File('${root.parent.path}/active_session_id.txt');
    final pointerExists = await pointer.exists();
    final activeId = pointerExists
        ? (await pointer.readAsString()).trim()
        : null;
    if (activeId != null && activeId != sessionId) {
      throw StateError('Another unarchived session is active.');
    }
    final pointerAlreadyActive = activeId == sessionId;
    final target = File('${root.path}/$sessionId.json');
    if (!pointerAlreadyActive && await target.exists()) {
      throw StateError('A completed session cannot be overwritten.');
    }
    await _atomicWrite(
      target,
      '${const JsonEncoder.withIndent('  ').convert(document.toJson())}\n',
    );
    if (!pointerAlreadyActive) {
      await _atomicWrite(pointer, '$sessionId\n');
    }
  }

  @override
  Future<bool> hasParticipant(String participantId) async {
    final root = await _root();
    final archive = Directory('${root.parent.path}/archive');
    for (final directory in <Directory>[root, archive]) {
      if (!await directory.exists()) continue;
      await for (final entity in directory.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final json = (jsonDecode(await entity.readAsString())! as Map)
            .cast<String, Object?>();
        final session = (json['session']! as Map).cast<String, Object?>();
        if (session['participant_id'] == participantId) return true;
      }
    }
    return false;
  }

  @override
  Future<void> archive(ValidationSessionDocument document) async {
    document.validate();
    if (document.session.currentPhase != PanelPhase.complete ||
        document.session.completedAt == null) {
      throw StateError('Only a completed session can be archived.');
    }
    final root = await _root();
    final pointer = File('${root.parent.path}/active_session_id.txt');
    if (!await pointer.exists() ||
        (await pointer.readAsString()).trim() != document.session.sessionId) {
      throw StateError('The completed session is not active.');
    }
    final active = File('${root.path}/${document.session.sessionId}.json');
    if (!await active.exists()) {
      throw const FileSystemException('Active session file is missing.');
    }
    final archiveRoot = Directory('${root.parent.path}/archive');
    await archiveRoot.create(recursive: true);
    final archived = File(
      '${archiveRoot.path}/${document.session.sessionId}.json',
    );
    final activeBytes = await active.readAsBytes();
    if (await archived.exists()) {
      final archivedBytes = await archived.readAsBytes();
      if (!_sameBytes(activeBytes, archivedBytes)) {
        throw StateError('Archived session bytes are immutable.');
      }
      await active.delete();
    } else {
      await active.rename(archived.path);
    }
    await pointer.delete();
  }

  Future<void> _atomicWrite(File target, String contents) async {
    final temporary = File('${target.path}.tmp');
    final sink = temporary.openWrite(mode: FileMode.writeOnly);
    sink.write(contents);
    await sink.flush();
    await sink.close();
    await temporary.rename(target.path);
  }

  static final _safeId = RegExp(r'^[A-Za-z0-9._-]+$');
}

class InMemoryValidationSessionStore implements ValidationSessionStore {
  ValidationSessionDocument? _document;
  final Map<String, ValidationSessionDocument> _archived =
      <String, ValidationSessionDocument>{};
  bool failNextWrite = false;

  ValidationSessionDocument? get document => _document;

  Map<String, ValidationSessionDocument> get archived =>
      Map<String, ValidationSessionDocument>.unmodifiable(_archived);

  @override
  Future<ValidationSessionDocument?> loadActive() async => _document;

  @override
  Future<void> write(ValidationSessionDocument document) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw const FileSystemException('Synthetic persistence failure.');
    }
    final copy = (jsonDecode(jsonEncode(document.toJson()))! as Map)
        .cast<String, Object?>();
    _document = ValidationSessionDocument.fromJson(copy);
  }

  @override
  Future<bool> hasParticipant(String participantId) async {
    return _document?.session.participantId == participantId ||
        _archived.values.any(
          (document) => document.session.participantId == participantId,
        );
  }

  @override
  Future<void> archive(ValidationSessionDocument document) async {
    if (document.session.currentPhase != PanelPhase.complete ||
        document.session.completedAt == null) {
      throw StateError('Only a completed session can be archived.');
    }
    if (_document?.session.sessionId != document.session.sessionId) {
      throw StateError('The completed session is not active.');
    }
    final copy = (jsonDecode(jsonEncode(document.toJson()))! as Map)
        .cast<String, Object?>();
    final archived = ValidationSessionDocument.fromJson(copy);
    final existing = _archived[document.session.sessionId];
    if (existing != null &&
        jsonEncode(existing.toJson()) != jsonEncode(archived.toJson())) {
      throw StateError('Archived session bytes are immutable.');
    }
    _archived[document.session.sessionId] = archived;
    _document = null;
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) return false;
  }
  return true;
}
