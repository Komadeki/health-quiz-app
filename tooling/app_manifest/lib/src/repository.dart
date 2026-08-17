import 'dart:io';

import 'package:path/path.dart' as p;

import 'manifest.dart';

Directory findRepositoryRoot({String? explicitPath}) {
  if (explicitPath != null) {
    return Directory(p.normalize(p.absolute(explicitPath)));
  }

  var directory = Directory.current.absolute;
  while (true) {
    if (File(p.join(directory.path, 'app.yaml')).existsSync() &&
        Directory(p.join(directory.path, 'packages', 'quiz_engine'))
            .existsSync()) {
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
  final rootManifest = File(p.join(repositoryRoot.path, 'app.yaml'));
  if (rootManifest.existsSync()) files.add(rootManifest);

  final referenceApps = Directory(
    p.join(repositoryRoot.path, 'reference_apps'),
  );
  if (referenceApps.existsSync()) {
    for (final entity in referenceApps.listSync(recursive: true)) {
      if (entity is File && p.basename(entity.path) == 'app.yaml') {
        files.add(entity);
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
