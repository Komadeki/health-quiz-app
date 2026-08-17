import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'manifest.dart';
import 'validation_result.dart';

void validateDependencyBoundaries(
  Directory repositoryRoot,
  Iterable<AppManifest> manifests,
  ManifestValidationResult result,
) {
  final apps = manifests.toList(growable: false);
  final appRoots = {
    for (final app in apps)
      app: p.normalize(p.join(repositoryRoot.path, app.appDirectory)),
  };
  final pubspecs = <AppManifest, Map<String, Object?>>{};
  final packageNames = <AppManifest, String>{};

  for (final app in apps) {
    final pubspec = File(p.join(appRoots[app]!, 'pubspec.yaml'));
    final decoded = _readYamlMap(pubspec, repositoryRoot, result);
    if (decoded == null) continue;
    pubspecs[app] = decoded;
    final packageName = decoded['name'];
    if (packageName is! String || packageName.trim().isEmpty) {
      result.error(
        'invalid_app_package_name',
        'Each app pubspec must declare a package name.',
        p.relative(pubspec.path, from: repositoryRoot.path),
      );
      continue;
    }
    packageNames[app] = packageName.trim();
  }

  for (final app in apps) {
    final pubspec = pubspecs[app];
    if (pubspec == null) continue;
    _validateAppPubspec(
      repositoryRoot,
      app,
      appRoots,
      pubspec,
      result,
    );
    _validateDartImports(
      repositoryRoot: repositoryRoot,
      sourceRoot: Directory(p.join(appRoots[app]!, 'lib')),
      owner: app,
      appRoots: appRoots,
      packageNames: packageNames,
      result: result,
    );
  }

  _validateQuizEngine(
    repositoryRoot,
    appRoots,
    packageNames,
    result,
  );
}

void _validateAppPubspec(
  Directory repositoryRoot,
  AppManifest app,
  Map<AppManifest, String> appRoots,
  Map<String, Object?> pubspec,
  ManifestValidationResult result,
) {
  final dependencies = _stringMap(pubspec['dependencies']);
  final quizEngine = _stringMap(dependencies?['quiz_engine']);
  final quizEnginePath = quizEngine?['path'];
  final expectedEngine = p.normalize(
    p.join(repositoryRoot.path, 'packages', 'quiz_engine'),
  );
  final resolvedEngine = quizEnginePath is String
      ? p.normalize(p.join(appRoots[app]!, quizEnginePath))
      : null;
  if (resolvedEngine == null || !p.equals(resolvedEngine, expectedEngine)) {
    result.error(
      'invalid_quiz_engine_path_dependency',
      'Each app must depend on packages/quiz_engine by relative path.',
      app.appPath('pubspec.yaml'),
    );
  }

  for (final sectionName in ['dependencies', 'dev_dependencies']) {
    final section = _stringMap(pubspec[sectionName]);
    if (section == null) continue;
    for (final entry in section.entries) {
      final dependency = _stringMap(entry.value);
      final dependencyPath = dependency?['path'];
      if (dependencyPath is! String) continue;
      final resolved = p.normalize(p.join(appRoots[app]!, dependencyPath));
      for (final other in appRoots.entries) {
        if (other.key == app) continue;
        if (_isAtOrWithin(resolved, other.value)) {
          result.error(
            'app_to_app_path_dependency',
            '${app.appKey} must not depend on ${other.key.appKey}.',
            app.appPath('pubspec.yaml'),
          );
        }
      }
    }
  }
}

void _validateQuizEngine(
  Directory repositoryRoot,
  Map<AppManifest, String> appRoots,
  Map<AppManifest, String> packageNames,
  ManifestValidationResult result,
) {
  final engineRoot = p.join(repositoryRoot.path, 'packages', 'quiz_engine');
  final pubspec = File(p.join(engineRoot, 'pubspec.yaml'));
  final decoded = _readYamlMap(pubspec, repositoryRoot, result);
  if (decoded != null) {
    for (final sectionName in ['dependencies', 'dev_dependencies']) {
      final section = _stringMap(decoded[sectionName]);
      if (section == null) continue;
      for (final entry in section.entries) {
        final dependency = _stringMap(entry.value);
        final dependencyPath = dependency?['path'];
        if (dependencyPath is! String) continue;
        final resolved = p.normalize(p.join(engineRoot, dependencyPath));
        if (appRoots.values.any((root) => _isAtOrWithin(resolved, root))) {
          result.error(
            'quiz_engine_app_path_dependency',
            'quiz_engine must not depend on apps/*.',
            p.relative(pubspec.path, from: repositoryRoot.path),
          );
        }
      }
    }
  }

  _validateDartImports(
    repositoryRoot: repositoryRoot,
    sourceRoot: Directory(p.join(engineRoot, 'lib')),
    owner: null,
    appRoots: appRoots,
    packageNames: packageNames,
    result: result,
  );
}

void _validateDartImports({
  required Directory repositoryRoot,
  required Directory sourceRoot,
  required AppManifest? owner,
  required Map<AppManifest, String> appRoots,
  required Map<AppManifest, String> packageNames,
  required ManifestValidationResult result,
}) {
  if (!sourceRoot.existsSync()) return;
  final directive = RegExp(
    r'''(?:import|export|part)\s+['"]([^'"]+)['"]''',
  );
  for (final entity in sourceRoot.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final source = entity.readAsStringSync();
    for (final match in directive.allMatches(source)) {
      final uri = match.group(1)!;
      if (uri.startsWith('package:')) {
        final packageName = uri.substring('package:'.length).split('/').first;
        for (final entry in packageNames.entries) {
          if (entry.key != owner && entry.value == packageName) {
            _reportAppImport(repositoryRoot, entity, owner, entry.key, result);
          }
        }
        continue;
      }
      if (uri.startsWith('dart:') || uri.contains('://')) continue;
      final resolved = p.normalize(p.join(entity.parent.path, uri));
      for (final entry in appRoots.entries) {
        if (entry.key != owner && _isAtOrWithin(resolved, entry.value)) {
          _reportAppImport(repositoryRoot, entity, owner, entry.key, result);
        }
      }
    }
  }
}

void _reportAppImport(
  Directory repositoryRoot,
  File source,
  AppManifest? owner,
  AppManifest dependency,
  ManifestValidationResult result,
) {
  result.error(
    owner == null ? 'quiz_engine_app_import' : 'app_to_app_import',
    owner == null
        ? 'quiz_engine must not import ${dependency.appKey}.'
        : '${owner.appKey} must not import ${dependency.appKey}.',
    p.relative(source.path, from: repositoryRoot.path),
  );
}

Map<String, Object?>? _readYamlMap(
  File file,
  Directory repositoryRoot,
  ManifestValidationResult result,
) {
  if (!file.existsSync()) {
    result.error(
      'missing_pubspec',
      'Expected pubspec.yaml.',
      p.relative(file.path, from: repositoryRoot.path),
    );
    return null;
  }
  try {
    final decoded = _stringMap(loadYaml(file.readAsStringSync()));
    if (decoded != null) return decoded;
  } on YamlException catch (error) {
    result.error(
      'invalid_pubspec',
      'Invalid pubspec YAML: ${error.message}',
      p.relative(file.path, from: repositoryRoot.path),
    );
    return null;
  }
  result.error(
    'invalid_pubspec',
    'pubspec.yaml must contain a map.',
    p.relative(file.path, from: repositoryRoot.path),
  );
  return null;
}

Map<String, Object?>? _stringMap(Object? value) {
  if (value is! Map) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is String) result[entry.key as String] = entry.value;
  }
  return result;
}

bool _isAtOrWithin(String path, String directory) =>
    p.equals(path, directory) || p.isWithin(directory, path);
