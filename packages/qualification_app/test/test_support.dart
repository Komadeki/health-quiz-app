import 'dart:async';
import 'dart:io';

import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

final QualificationAppDefinition fixtureDefinition = QualificationAppDefinition(
  appKey: 'qualification_fixture',
  displayName: '資格アプリ Fixture',
  publisher: 'KOMADEKI Fixture',
  brandName: 'KOMADEKI Fixture',
  legalese: 'Fixture only',
  urls: const QualificationUrls(
    support: 'https://example.invalid/support',
    privacy: 'https://example.invalid/privacy',
  ),
  questionBankAsset: 'assets/question_bank/qualification_fixture_bank.json',
  questionIdentityPolicy: const ExplicitQuestionIdentityV1(),
  monetization: const MonetizationDefinition(
    architecture: PurchaseArchitecture.singleFullUnlock,
    productCatalog: ProductCatalog(fullUnlockProductId: 'fixture_full_unlock'),
    entitlementPolicy: SingleFullUnlockEntitlementPolicy(),
  ),
  examProfile: MockExamProfileV1(
    profileVersion: 'fixture-exam-v1',
    questionCount: 2,
    timeLimitMinutes: null,
    allocations: const [
      ExamUnitAllocationV1(unitId: 'fixture_operations', questionCount: 1),
      ExamUnitAllocationV1(unitId: 'fixture_safety', questionCount: 1),
    ],
    overallPassPercent: null,
    sectionPassRules: const [],
    shuffleQuestions: true,
  ),
  branding: const QualificationBranding(
    themeKey: 'fixture_teal',
    seedColorHex: '#00695C',
  ),
  learningProduct: const LearningProductProfileV1(
    appVersion: '0.1.0',
    homeHeadline: 'Fixture learning',
    sourceLabel: 'Fixture source',
    enabledModes: {
      LearningModeV1.unitPractice,
      LearningModeV1.randomPractice,
      LearningModeV1.unansweredPractice,
      LearningModeV1.incorrectPractice,
      LearningModeV1.retry,
      LearningModeV1.mockExam,
    },
    practiceQuestionCount: 2,
    recentWindowSize: 5,
    progressEnabled: true,
    historyEnabled: true,
    weaknessEnabled: true,
    recommendationEnabled: true,
  ),
);

QualificationBank loadFixtureBank() {
  return QualificationBank.decode(
    File(
      '../../question_banks/qualification_fixture/generated/'
      'qualification_fixture_bank.json',
    ).readAsStringSync(),
    fixtureDefinition,
  );
}

final class FixedBankLoader implements QualificationBankLoader {
  FixedBankLoader(this.value);

  final QualificationBank value;

  @override
  Future<QualificationBank> load() async => value;
}

final class FakePurchaseGateway implements LifecyclePurchaseGateway {
  FakePurchaseGateway({this.storeAvailable = true});

  final bool storeAvailable;
  final _results = StreamController<PurchaseResult>.broadcast(sync: true);
  var sequence = 0;
  final purchased = <String>[];
  final completed = <String>[];

  @override
  Stream<PurchaseResult> get purchaseResults => _results.stream;

  @override
  void startListening() {}

  @override
  Future<ProductQueryResult> queryProducts(Set<String> productIds) async {
    return ProductQueryResult(
      storeAvailable: storeAvailable,
      products: storeAvailable
          ? [
              for (final id in productIds)
                PurchaseProduct(
                  id: id,
                  title: 'Full unlock',
                  description: 'All content',
                  price: 'Fixture',
                ),
            ]
          : const [],
    );
  }

  @override
  Future<void> purchase(String productId) async {
    purchased.add(productId);
    emit(productId, PurchaseResultStatus.purchased);
  }

  @override
  Future<void> restore() async {
    emit('fixture_full_unlock', PurchaseResultStatus.restored);
  }

  void emit(String productId, PurchaseResultStatus status) {
    _results.add(
      PurchaseResult(
        eventId: 'fake-${sequence++}',
        productId: productId,
        status: status,
      ),
    );
  }

  @override
  Future<void> complete(PurchaseResult result) async {
    completed.add(result.eventId);
  }

  @override
  Future<void> dispose() => _results.close();
}

final class TestClock {
  DateTime value = DateTime.utc(2026, 1, 1);

  DateTime call() {
    final current = value;
    value = value.add(const Duration(seconds: 1));
    return current;
  }
}

final class FaultingSessionStore implements QualificationSessionStore {
  QualificationSessionV1? value;
  bool failNextSave = false;
  bool failNextClear = false;

  @override
  Future<QualificationSessionV1?> load() async => value;

  @override
  Future<void> save(QualificationSessionV1 session) async {
    if (failNextSave) {
      failNextSave = false;
      throw StateError('Simulated session save crash.');
    }
    value = session;
  }

  @override
  Future<void> clear() async {
    if (failNextClear) {
      failNextClear = false;
      throw StateError('Simulated session clear crash.');
    }
    value = null;
  }
}

Future<void> settleEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
