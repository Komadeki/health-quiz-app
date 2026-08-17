import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_engine/quiz_engine.dart';
import 'package:single_unlock_fixture/fixture_bank.dart';
import 'package:single_unlock_fixture/generated/app_manifest.g.dart';

void main() {
  test('generated bank contains only two active explicit-ID cards', () {
    final bank = FixtureBank.decode(
      File(GeneratedAppManifest.questionBankAssetPath!).readAsStringSync(),
    );

    expect(bank.cards, hasLength(2));
    expect(
        bank.cards.map((card) => card.isPremium), containsAll([true, false]));
    expect(
      GeneratedAppManifest.questionIdentityPolicy,
      isA<ExplicitQuestionIdentityV1>(),
    );
    expect(
      bank.cards.map(
        GeneratedAppManifest.questionIdentityPolicy.stableIdFor,
      ),
      unorderedEquals(['FIXTURE-Q-000001', 'FIXTURE-Q-000002']),
    );
  });
}
