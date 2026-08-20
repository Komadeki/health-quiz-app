import 'package:flutter/material.dart';

import 'domain/validation_bundle.dart';
import 'presentation/panel_runner_controller.dart';
import 'presentation/panel_runner_shell.dart';
import 'session/session_repository.dart';
import 'session/session_storage.dart';

class DroneV0PanelBootstrap extends StatefulWidget {
  const DroneV0PanelBootstrap({super.key});

  @override
  State<DroneV0PanelBootstrap> createState() => _DroneV0PanelBootstrapState();
}

class _DroneV0PanelBootstrapState extends State<DroneV0PanelBootstrap> {
  late final Future<PanelRunnerController> _controller = _createController();

  Future<PanelRunnerController> _createController() async {
    final bundle = await ValidationBundleLoader().load();
    final controller = PanelRunnerController(
      bundle: bundle,
      repository: ValidationSessionRepository(
        store: FileValidationSessionStore(),
      ),
    );
    await controller.initialize();
    return controller;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PanelRunnerController>(
      future: _controller,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _BootstrapFailure(error: snapshot.error!);
        }
        if (!snapshot.hasData) {
          return const MaterialApp(
            home: Scaffold(body: Center(child: CircularProgressIndicator())),
          );
        }
        return DroneV0PanelApp(controller: snapshot.data!);
      },
    );
  }
}

class DroneV0PanelApp extends StatelessWidget {
  const DroneV0PanelApp({required this.controller, super.key});

  final PanelRunnerController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '二等無人航空機 V0 Panel',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF8A4B00),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: PanelRunnerShell(controller: controller),
    );
  }
}

class _BootstrapFailure extends StatelessWidget {
  const _BootstrapFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('VALIDATION ONLY — NOT PRODUCTION')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Panel start rejected.\n$error'),
        ),
      ),
    );
  }
}
