import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shared production package contains no qualification identity', () {
    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      for (final forbidden in [
        'Drone',
        'Health',
        'drone_second_class',
        'package:drone_second_class/',
        'package:health_quiz_app/',
      ]) {
        expect(source, isNot(contains(forbidden)), reason: file.path);
      }
    }
  });
}
