import 'package:flutter/material.dart';
import 'package:qualification_app/qualification_app.dart';

import 'generated/app_manifest.g.dart';

/// First-class composition of the shared qualification learning product.
final class Eisei1App extends StatelessWidget {
  const Eisei1App({super.key});

  @override
  Widget build(BuildContext context) {
    return QualificationProductionBootstrap(
      definition: GeneratedAppManifest.definition,
    );
  }
}
