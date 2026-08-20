import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'session_models.dart';

abstract interface class ValidationSessionStore {
  Future<ValidationSessionDocument?> loadActive();

  Future<void> write(ValidationSessionDocument document);
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
    final json =
        (jsonDecode(await file.readAsString())! as Map).cast<String, Object?>();
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
    final pointerAlreadyActive = await pointer.exists() &&
        (await pointer.readAsString()).trim() == sessionId;
    await _atomicWrite(
      File('${root.path}/$sessionId.json'),
      '${const JsonEncoder.withIndent('  ').convert(document.toJson())}\n',
    );
    if (!pointerAlreadyActive) {
      await _atomicWrite(pointer, '$sessionId\n');
    }
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
  bool failNextWrite = false;

  ValidationSessionDocument? get document => _document;

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
}
