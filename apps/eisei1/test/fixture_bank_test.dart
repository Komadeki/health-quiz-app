import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';
import 'package:eisei1/generated/app_manifest.g.dart';

void main() {
  test('generated bank contains the frozen 400-question explicit-ID bank', () {
    final bank = QualificationBank.decode(
      File(GeneratedAppManifest.questionBankAssetPath!).readAsStringSync(),
      GeneratedAppManifest.definition,
    );

    expect(bank.cards, hasLength(400));
    expect(
      bank.cards.map((card) => card.isPremium),
      hasLength(400),
    );
    expect(
      GeneratedAppManifest.questionIdentityPolicy,
      isA<ExplicitQuestionIdentityV1>(),
    );
    expect(
      bank.cards.map(bank.stableId),
      containsAll(['EISEI1-Q-000001', 'EISEI1-Q-000400']),
    );
    expect(bank.cards.where((card) => !card.isPremium), hasLength(30));
  });
}
