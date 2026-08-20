import 'package:flutter/material.dart';

import '../domain/panel_route.dart';
import '../domain/validation_bundle.dart';
import '../session/session_models.dart';
import 'panel_runner_controller.dart';

class PanelRunnerShell extends StatelessWidget {
  const PanelRunnerShell({required this.controller, super.key});

  final PanelRunnerController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('二等無人航空機 V0 Panel')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Container(
              key: const Key('validation-only-banner'),
              width: double.infinity,
              color: Theme.of(context).colorScheme.errorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: const Text(
                'VALIDATION ONLY — NOT PRODUCTION',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) => _RunnerBody(controller: controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunnerBody extends StatelessWidget {
  const _RunnerBody({required this.controller});

  final PanelRunnerController controller;

  @override
  Widget build(BuildContext context) {
    final document = controller.document;
    Widget content;
    if (document == null) {
      content = ValidationSetupView(controller: controller);
    } else {
      content = switch (document.session.currentPhase) {
        PanelPhase.predictionGate => ResearcherPredictionGate(
            controller: controller,
          ),
        PanelPhase.explanation => ExplanationView(controller: controller),
        PanelPhase.complete => SessionCompleteView(controller: controller),
        _ when controller.visibleQuestion != null => PanelQuestionView(
            key: ValueKey<String>(controller.visibleQuestion!.questionId),
            controller: controller,
            question: controller.visibleQuestion!,
            document: document,
          ),
        _ => const Center(child: CircularProgressIndicator()),
      };
    }
    return Stack(
      children: <Widget>[
        Positioned.fill(child: content),
        if (controller.errorMessage != null)
          Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Persistence or validation failed. No advance occurred.\n'
                  '${controller.errorMessage}',
                  key: const Key('runner-error'),
                ),
              ),
            ),
          ),
        if (controller.busy)
          const Align(
            alignment: Alignment.topCenter,
            child: LinearProgressIndicator(key: Key('runner-busy')),
          ),
      ],
    );
  }
}

class ValidationSetupView extends StatefulWidget {
  const ValidationSetupView({required this.controller, super.key});

  final PanelRunnerController controller;

  @override
  State<ValidationSetupView> createState() => _ValidationSetupViewState();
}

class _ValidationSetupViewState extends State<ValidationSetupView> {
  late final TextEditingController _assignment = TextEditingController(
    text: referenceAssignmentJson.trim(),
  );

  @override
  void dispose() {
    _assignment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('validation-setup'),
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text('Validation setup',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text(
          'Paste an explicit PanelAssignmentV1. The runner does not sample, '
          'randomize, or complete participant assignments.',
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('assignment-json'),
          controller: _assignment,
          minLines: 12,
          maxLines: 24,
          autocorrect: false,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Explicit assignment JSON',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('start-panel'),
          onPressed: widget.controller.busy
              ? null
              : () => widget.controller.startFromJson(_assignment.text),
          child: const Text('Compile route and start'),
        ),
        if (widget.controller.canResume) ...<Widget>[
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('resume-panel'),
            onPressed: widget.controller.busy ? null : widget.controller.resume,
            child: const Text('Resume durable session'),
          ),
        ],
      ],
    );
  }
}

class PanelQuestionView extends StatefulWidget {
  const PanelQuestionView({
    required this.controller,
    required this.question,
    required this.document,
    super.key,
  });

  final PanelRunnerController controller;
  final ValidationQuestion question;
  final ValidationSessionDocument document;

  @override
  State<PanelQuestionView> createState() => _PanelQuestionViewState();
}

class _PanelQuestionViewState extends State<PanelQuestionView> {
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final index = widget.document.responses.length;
    return ListView(
      key: const Key('panel-question'),
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(
          'Panel question ${index + 1} / ${widget.document.route.entries.length}',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 16),
        Text(widget.question.prompt,
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 20),
        for (var choiceIndex = 0;
            choiceIndex < widget.question.choices.length;
            choiceIndex += 1)
          ListTile(
            key: Key('choice-$choiceIndex'),
            leading: Icon(
              _selectedIndex == choiceIndex
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
            ),
            onTap: widget.controller.busy
                ? null
                : () => setState(() => _selectedIndex = choiceIndex),
            title: Text(
              '${String.fromCharCode(65 + choiceIndex)}. '
              '${widget.question.choices[choiceIndex]}',
            ),
          ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('commit-answer'),
          onPressed: _selectedIndex == null || widget.controller.busy
              ? null
              : () => widget.controller.commitChoice(_selectedIndex!),
          child: const Text('回答を確定'),
        ),
      ],
    );
  }
}

class ResearcherPredictionGate extends StatefulWidget {
  const ResearcherPredictionGate({required this.controller, super.key});

  final PanelRunnerController controller;

  @override
  State<ResearcherPredictionGate> createState() =>
      _ResearcherPredictionGateState();
}

class _ResearcherPredictionGateState extends State<ResearcherPredictionGate> {
  final _version = TextEditingController();
  final _payload =
      TextEditingController(text: '{\n  "researcher_input": true\n}');

  @override
  void dispose() {
    _version.dispose();
    _payload.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('prediction-gate'),
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(
          'Researcher Prediction Commit Gate',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Researcher-only boundary. Commit an externally supplied prediction. '
          'The runner does not compute or interpret it for the participant.',
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('prediction-version'),
          controller: _version,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'prediction_algorithm_version',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('prediction-payload'),
          controller: _payload,
          minLines: 5,
          maxLines: 12,
          style: const TextStyle(fontFamily: 'monospace'),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'prediction_payload JSON',
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('commit-prediction'),
          onPressed: widget.controller.busy
              ? null
              : () => widget.controller.commitPrediction(
                    algorithmVersion: _version.text,
                    payloadSource: _payload.text,
                  ),
          child: const Text('Commit immutable prediction'),
        ),
      ],
    );
  }
}

class ExplanationView extends StatelessWidget {
  const ExplanationView({required this.controller, super.key});

  final PanelRunnerController controller;

  @override
  Widget build(BuildContext context) {
    final document = controller.document!;
    final unlock = document.events.firstWhere(
      (event) => event.eventType == 'explanation_unlocked',
    );
    final answeredBeforeCoverage = document.responses
        .where((response) => response.phase != PanelPhase.remainingCoverage)
        .toList(growable: false);
    return ListView(
      key: const Key('explanation-screen'),
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text('Explanation', style: Theme.of(context).textTheme.headlineSmall),
        Text('Durably unlocked at event_seq ${unlock.eventSeq}'),
        const SizedBox(height: 16),
        for (final response in answeredBeforeCoverage)
          _ExplanationCard(
            response: response,
            question: controller.bundle.questionsById[response.questionId]!,
          ),
        FilledButton(
          key: const Key('continue-to-coverage'),
          onPressed:
              controller.busy ? null : controller.continueAfterExplanation,
          child: const Text('Continue to remaining coverage'),
        ),
      ],
    );
  }
}

class _ExplanationCard extends StatelessWidget {
  const _ExplanationCard({required this.response, required this.question});

  final ValidationResponse response;
  final ValidationQuestion question;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(question.prompt,
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('回答: ${response.selectedChoice}'),
            Text('正解: ${String.fromCharCode(65 + question.correctIndex)}'),
            const SizedBox(height: 8),
            Text(question.explanation),
          ],
        ),
      ),
    );
  }
}

class SessionCompleteView extends StatefulWidget {
  const SessionCompleteView({required this.controller, super.key});

  final PanelRunnerController controller;

  @override
  State<SessionCompleteView> createState() => _SessionCompleteViewState();
}

class _SessionCompleteViewState extends State<SessionCompleteView> {
  final _exportController = TextEditingController();
  bool _hasExport = false;

  @override
  void dispose() {
    _exportController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.controller.document!;
    return ListView(
      key: const Key('session-complete'),
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text('Session complete',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('session_id: ${document.session.sessionId}'),
        Text('route_hash: ${document.route.routeHash}'),
        Text('responses: ${document.responses.length}'),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('generate-export'),
          onPressed: () {
            _exportController.text = widget.controller.exportJson();
            setState(() => _hasExport = true);
          },
          icon: const Icon(Icons.data_object),
          label: const Text('Generate one JSON export'),
        ),
        if (_hasExport) ...<Widget>[
          const SizedBox(height: 12),
          TextField(
            key: const Key('export-json'),
            controller: _exportController,
            readOnly: true,
            minLines: 12,
            maxLines: 24,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Local validation export',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ],
    );
  }
}
