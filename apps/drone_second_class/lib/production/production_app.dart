import 'package:flutter/material.dart';
import 'package:qualification_app/qualification_app.dart';

import '../generated/app_manifest.g.dart';

/// Drone is a Reference Product composition, not a separate learning runtime.
final class DroneProductionBootstrap extends StatelessWidget {
  const DroneProductionBootstrap({super.key});

  @override
  Widget build(BuildContext context) {
    return QualificationProductionBootstrap(
      definition: GeneratedAppManifest.definition,
      homeSupplementBuilder: buildDroneHomeSupplement,
    );
  }
}

Widget buildDroneHomeSupplement(
  BuildContext context,
  QualificationProductionController controller,
) {
  return DroneHomeSupplement(controller: controller);
}

final class DroneHomeSupplement extends StatelessWidget {
  const DroneHomeSupplement({
    required this.controller,
    super.key,
  });

  final QualificationProductionController controller;

  @override
  Widget build(BuildContext context) {
    final definition = controller.definition;
    final profile = definition.examProfile;
    late final String examSummary;
    if (profile == null) {
      examSummary = '単元別・復習で理解を固めます。';
    } else if (profile.timeLimitMinutes == null) {
      examSummary =
          '単元別・復習で確認した後、このアプリの模擬試験（${profile.questionCount}問）で仕上げます。';
    } else {
      examSummary =
          '単元別・復習で確認した後、このアプリの模擬試験（${profile.questionCount}問・${profile.timeLimitMinutes}分）で仕上げます。';
    }

    return Card(
      key: const Key('drone-study-guide'),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const Key('drone-study-guide-toggle'),
        initiallyExpanded: false,
        leading: const Icon(Icons.menu_book_outlined),
        title: const Text('二等学科の学習ガイド'),
        subtitle: const Text('必要なときに開いて確認'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '基準資料: ${definition.learningProduct.sourceLabel}',
            key: const Key('drone-study-guide-source'),
          ),
          const SizedBox(height: 8),
          Text(
            examSummary,
            key: const Key('drone-study-guide-path'),
          ),
        ],
      ),
    );
  }
}
