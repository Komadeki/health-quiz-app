import 'package:eisei1/generated/app_manifest.g.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Eisei1 preserves the official 44-question mock-exam structure', () {
    final profile = GeneratedAppManifest.definition.examProfile!;

    expect(profile.questionCount, 44);
    expect(profile.timeLimitMinutes, 180);
    expect(profile.overallPassPercent, 60);
    expect(
      profile.allocations.map((allocation) => allocation.questionCount),
      orderedEquals([10, 10, 7, 7, 10]),
    );
    expect(
      profile.sectionPassRules.map((rule) => rule.minimumPercent),
      everyElement(40),
    );
  });
}
