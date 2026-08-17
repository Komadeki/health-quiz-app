import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reference app Dart does not import health app code', () {
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
  });
}
