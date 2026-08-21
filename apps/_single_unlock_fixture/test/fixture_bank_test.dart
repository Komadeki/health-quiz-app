import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';
import 'package:single_unlock_fixture/generated/app_manifest.g.dart';

void main() {
  test('generated bank contains only two active explicit-ID cards', () {
    final bank = QualificationBank.decode(
      File(GeneratedAppManifest.questionBankAssetPath!).readAsStringSync(),
      GeneratedAppManifest.definition,
    );

    expect(bank.cards, hasLength(2));
    expect(
      bank.cards.map((card) => card.isPremium),
      containsAll([true, false]),
    );
    expect(
      GeneratedAppManifest.questionIdentityPolicy,
      isA<ExplicitQuestionIdentityV1>(),
    );
    expect(
      bank.cards.map(bank.stableId),
      unorderedEquals(['FIXTURE-Q-000001', 'FIXTURE-Q-000002']),
    );
  });
}
