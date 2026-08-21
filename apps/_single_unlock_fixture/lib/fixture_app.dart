import 'package:flutter/widgets.dart';
import 'package:qualification_app/qualification_app.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'fixture_purchase.dart';
import 'generated/app_manifest.g.dart';

/// Technical non-production fixture using the same Factory shell as Drone.
final class FixtureApp extends StatelessWidget {
  const FixtureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return QualificationProductionBootstrap(
      definition: GeneratedAppManifest.definition,
      purchaseGateway: FixturePurchaseGateway(),
      entitlementCache: MemoryEntitlementCache(),
      learningRepository: InMemoryLearningRepository(),
      sessionStore: MemoryQualificationSessionStore(),
      randomizer: const IdentityQuestionRandomizer(),
    );
  }
}
