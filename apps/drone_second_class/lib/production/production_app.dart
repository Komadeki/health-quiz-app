import 'package:flutter/widgets.dart';
import 'package:qualification_app/qualification_app.dart';

import '../generated/app_manifest.g.dart';

/// Drone is a Reference Product composition, not a separate learning runtime.
final class DroneProductionBootstrap extends StatelessWidget {
  const DroneProductionBootstrap({super.key});

  @override
  Widget build(BuildContext context) {
    return QualificationProductionBootstrap(
      definition: GeneratedAppManifest.definition,
    );
  }
}
