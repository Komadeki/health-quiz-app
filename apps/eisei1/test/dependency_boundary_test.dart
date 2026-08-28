import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Eisei1 is a thin Factory composition without app-local runtime', () {
    final violations = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains('package:health_quiz_app/') ||
          RegExp(r'''import\s+['"](?:\.\./)+lib/''').hasMatch(source)) {
        violations.add(entity.path);
      }
    }

    expect(violations, isEmpty);
    expect(File('lib/eisei1_bank.dart').existsSync(), isFalse);
    expect(File('lib/eisei1_shell_controller.dart').existsSync(), isFalse);
    expect(
      File('lib/eisei1_app.dart').readAsStringSync(),
      contains('QualificationProductionBootstrap'),
    );
  });
}
