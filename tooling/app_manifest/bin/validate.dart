import 'dart:io';

import 'package:app_manifest_tooling/app_manifest.dart';

void main(List<String> arguments) {
  final repositoryRoot = findRepositoryRoot(
    explicitPath: optionValue(arguments, '--repository-root'),
  );
  final result = validateRepository(
    repositoryRoot,
    checkGenerated: arguments.contains('--check-generated'),
  );
  for (final issue in result.issues) {
    stderr.writeln(issue);
  }
  stdout.writeln(
    'Validation complete: ${result.issues.length} error(s).',
  );
  if (!result.isValid) exitCode = 1;
}
