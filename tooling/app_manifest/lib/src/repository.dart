import 'dart:io';

import 'package:path/path.dart' as p;

import 'manifest.dart';

Directory findRepositoryRoot({String? explicitPath}) {
  if (explicitPath != null) {
    final directory = Directory(p.normalize(p.absolute(explicitPath)));
    if (!_isRepositoryRoot(directory)) {
      throw StateError(
        'Not a quiz apps repository root: ${directory.path}',
      );
    }
    return directory;
  }

  var directory = Directory.current.absolute;
  while (true) {
    if (_isRepositoryRoot(directory)) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError('Could not locate repository root.');
    }
    directory = parent;
  }
}

List<File> discoverManifestFiles(Directory repositoryRoot) {
  final files = <File>[];
  final apps = Directory(p.join(repositoryRoot.path, 'apps'));
  if (apps.existsSync()) {
    for (final entity in apps.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      final manifest = File(p.join(entity.path, 'app.yaml'));
      if (manifest.existsSync()) {
        files.add(manifest);
      }
    }
  }

  files.sort((left, right) => left.path.compareTo(right.path));
  return files;
}

List<AppManifest> loadAppManifests(Directory repositoryRoot) =>
    discoverManifestFiles(repositoryRoot)
        .map((file) => AppManifest.fromFile(file, repositoryRoot))
        .toList(growable: false);

String? optionValue(List<String> arguments, String name) {
  final index = arguments.indexOf(name);
  if (index == -1) return null;
  if (index + 1 >= arguments.length) {
    throw ArgumentError('Missing value after $name.');
  }
  return arguments[index + 1];
}

bool _isRepositoryRoot(Directory directory) =>
    Directory(p.join(directory.path, 'apps')).existsSync() &&
    Directory(p.join(directory.path, 'packages', 'quiz_engine')).existsSync() &&
    Directory(p.join(directory.path, 'tooling', 'app_manifest')).existsSync();
