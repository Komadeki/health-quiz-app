import 'dart:io';

import 'package:app_manifest_tooling/app_manifest.dart';

void main(List<String> arguments) {
  final repositoryRoot = findRepositoryRoot(
    explicitPath: optionValue(arguments, '--repository-root'),
  );
  final manifests = loadAppManifests(repositoryRoot);
  final validation = ManifestValidationResult();
  for (final manifest in manifests) {
    validateManifestSemantics(manifest, validation);
  }
  validateUniqueIdentities(manifests, validation);
  if (!validation.isValid) {
    for (final issue in validation.issues) {
      stderr.writeln(issue);
    }
    exitCode = 1;
    return;
  }

  final generated = buildGeneratedFiles(repositoryRoot, manifests);
  if (arguments.contains('--check')) {
    final drift = findGeneratedDrift(repositoryRoot, generated);
    if (drift.isEmpty) {
      stdout.writeln('App manifest generation is up to date.');
      return;
    }
    for (final path in drift) {
      stderr.writeln('ERROR [generated_manifest_drift] $path');
    }
    exitCode = 1;
    return;
  }

  for (final path in writeGeneratedFiles(repositoryRoot, generated)) {
    stdout.writeln('WROTE $path');
  }
}
