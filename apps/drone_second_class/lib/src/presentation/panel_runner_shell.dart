import 'package:flutter/material.dart';

import '../domain/panel_assignment.dart';
import '../domain/panel_route.dart';
import '../domain/pilot_profile.dart';
import '../domain/validation_bundle.dart';
import '../session/pilot_prediction.dart';
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
              padding: const EdgeInsets.all(10),
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
    final preflight = controller.pilotPreflight;
    final content = document == null
        ? preflight == null
              ? PilotSetupView(controller: controller)
              : PilotPreflightView(controller: controller, preflight: preflight)
        : switch (document.session.currentPhase) {
            PanelPhase.predictionGate when controller.isPilotSession =>
              controller.researcherUnlocked
                  ? PilotResearcherPredictionView(controller: controller)
                  : ParticipantResearcherHandoff(controller: controller),
            PanelPhase.predictionGate => const Center(
              key: Key('prediction-gate'),
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

class PilotSetupView extends StatefulWidget {
  const PilotSetupView({required this.controller, super.key});

  final PanelRunnerController controller;

  @override
  State<PilotSetupView> createState() => _PilotSetupViewState();
}

class _PilotSetupViewState extends State<PilotSetupView> {
  String _slotId = DroneV0P3PilotProfile.slots.first.slotId;
  final _participantId = TextEditingController(text: 'V0P3-I001');

  @override
  void dispose() {
    _participantId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: const Key('pilot-setup'),
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(
          'V0P-3 Pilot setup',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'これは二等無人航空機操縦士の本試験そのものではなく、\n'
              '学習アプリの検証用セッションです。\n\n'
              '回答中は検索や教材の参照をせず、\n'
              'ご自身の判断だけで回答してください。\n\n'
              '正答や解説は途中では表示されません。\n\n'
              '途中で一度、画面の指示に従って担当者へ端末を渡してください。\n'
              'その間は操作しないでください。\n\n'
              '終盤で、それまでの問題の解説が表示されます。\n\n'
              'アプリが閉じたり止まった場合は、\n'
              '自分で最初からやり直さず担当者を呼んでください。',
            ),
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          key: const Key('assignment-slot'),
          initialValue: _slotId,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Fixed assignment slot',
          ),
          items: DroneV0P3PilotProfile.slots
              .map(
                (slot) => DropdownMenuItem<String>(
                  value: slot.slotId,
                  child: Text(slot.slotId),
                ),
              )
              .toList(growable: false),
          onChanged: widget.controller.busy
              ? null
              : (value) => setState(() => _slotId = value!),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('participant-id'),
          controller: _participantId,
          autocorrect: false,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Pseudonymous participant_id',
            helperText: 'V0P3-Ixxx or V0P3-Exxx',
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('compile-pilot'),
          onPressed: widget.controller.busy
              ? null
              : () => widget.controller.compilePilot(
                  assignmentSlotId: _slotId,
                  participantId: _participantId.text,
                ),
          child: const Text('Compile and open Pilot Preflight'),
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

class PilotPreflightView extends StatelessWidget {
  const PilotPreflightView({
    required this.controller,
    required this.preflight,
    super.key,
  });

  final PanelRunnerController controller;
  final PilotPreflight preflight;

  @override
  Widget build(BuildContext context) {
    final assignment = preflight.assignment;
    final form = switch (assignment.replicationForm) {
      ReplicationForm.a => 'Form A',
      ReplicationForm.b => 'Form B',
      null => 'none',
    };
    final rows = <String, String>{
      'participant_id': assignment.participantId,
      'assignment_slot_id': assignment.assignmentSlotId!,
      'assignment_id': assignment.assignmentId,
      'Group': assignment.assignmentGroup == AssignmentGroup.a ? 'A' : 'B',
      'Deep Targets': assignment.deepTargetIds.join(' / '),
      'Breadth Groups': assignment.breadthGroupIds.join(' / '),
      'Sentinel set': assignment.sentinelIds.join(' / '),
      'Coverage count': '${assignment.coverageIds.length}',
      'M3 Form': form,
      'route count': '${preflight.route.entries.length}',
      'route_hash': preflight.route.routeHash,
      'bank_revision': controller.bundle.provenance.bankRevision,
      'validation_protocol_version':
          controller.bundle.provenance.validationProtocolVersion,
      'validation_bundle_hash':
          controller.bundle.provenance.validationBundleHash,
    };
    return ListView(
      key: const Key('pilot-preflight'),
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(
          'Pilot Preflight',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        for (final row in rows.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SelectableText('${row.key}: ${row.value}'),
          ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('confirm-pilot'),
          onPressed: controller.busy ? null : controller.confirmPilotPreflight,
          child: const Text('Operator Confirm and start session'),
        ),
        TextButton(
          key: const Key('cancel-preflight'),
          onPressed: controller.busy ? null : controller.cancelPilotPreflight,
          child: const Text('Back'),
        ),
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
        Text(
          widget.question.prompt,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 20),
        for (
          var choiceIndex = 0;
          choiceIndex < widget.question.choices.length;
          choiceIndex += 1
        )
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

class ParticipantResearcherHandoff extends StatelessWidget {
  const ParticipantResearcherHandoff({required this.controller, super.key});

  final PanelRunnerController controller;

  Future<void> _showPinDialog(BuildContext context) async {
    final pin = await showDialog<String>(
      context: context,
      builder: (context) => const _ResearcherPinDialog(),
    );
    if (pin != null) controller.unlockResearcher(pin);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('participant-handoff'),
      behavior: HitTestBehavior.opaque,
      onLongPress: () => _showPinDialog(context),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'ここで端末を担当者へ渡してください。\n'
            '端末には触れず、そのままお待ちください。',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _ResearcherPinDialog extends StatefulWidget {
  const _ResearcherPinDialog();

  @override
  State<_ResearcherPinDialog> createState() => _ResearcherPinDialogState();
}

class _ResearcherPinDialogState extends State<_ResearcherPinDialog> {
  final _pin = TextEditingController();

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Researcher PIN'),
      content: TextField(
        key: const Key('researcher-pin'),
        controller: _pin,
        obscureText: true,
      ),
      actions: <Widget>[
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('unlock-researcher'),
          onPressed: () {
            final pin = _pin.text;
            Navigator.of(context).pop(pin);
          },
          child: const Text('Unlock'),
        ),
      ],
    );
  }
}

class PilotResearcherPredictionView extends StatefulWidget {
  const PilotResearcherPredictionView({required this.controller, super.key});

  final PanelRunnerController controller;

  @override
  State<PilotResearcherPredictionView> createState() =>
      _PilotResearcherPredictionViewState();
}

class _PilotResearcherPredictionViewState
    extends State<PilotResearcherPredictionView> {
  final _outcomes = <String, String?>{};
  final _confidences = <String, int?>{};

  @override
  Widget build(BuildContext context) {
    final document = widget.controller.document!;
    final plan = widget.controller.pilotPredictionPlan!;
    for (final target in plan.targets) {
      _outcomes.putIfAbsent(target.predictionKey, () => null);
      _confidences.putIfAbsent(target.predictionKey, () => null);
    }
    final complete = plan.targets.every(
      (target) =>
          _outcomes[target.predictionKey] != null &&
          _confidences[target.predictionKey] != null,
    );
    final responseById = <String, ValidationResponse>{
      for (final response in document.responses) response.responseId: response,
    };
    return ListView(
      key: const Key('pilot-researcher-prediction'),
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(
          'Researcher-only S1 evidence',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text('S1 snapshot identity: ${plan.s1SnapshotId}'),
        const SizedBox(height: 16),
        for (final target in plan.targets)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${target.predictionKey} · ${target.targetId}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  for (final responseId in target.evidenceResponseIds)
                    _ObservedEvidence(
                      response: responseById[responseId]!,
                      question: widget
                          .controller
                          .bundle
                          .questionsById[responseById[responseId]!.questionId]!,
                      targetId: target.targetId,
                    ),
                  DropdownButtonFormField<String>(
                    key: Key('outcome-${target.predictionKey}'),
                    initialValue: _outcomes[target.predictionKey],
                    decoration: const InputDecoration(
                      labelText: 'predicted_outcome',
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(
                        value: 'CORRECT',
                        child: Text('CORRECT'),
                      ),
                      DropdownMenuItem(
                        value: 'INCORRECT',
                        child: Text('INCORRECT'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _outcomes[target.predictionKey] = value),
                  ),
                  DropdownButtonFormField<int>(
                    key: Key('confidence-${target.predictionKey}'),
                    initialValue: _confidences[target.predictionKey],
                    decoration: const InputDecoration(
                      labelText: 'confidence (ordinal 1–3)',
                    ),
                    items: const <DropdownMenuItem<int>>[
                      DropdownMenuItem(value: 1, child: Text('1')),
                      DropdownMenuItem(value: 2, child: Text('2')),
                      DropdownMenuItem(value: 3, child: Text('3')),
                    ],
                    onChanged: (value) => setState(
                      () => _confidences[target.predictionKey] = value,
                    ),
                  ),
                ],
              ),
            ),
          ),
        FilledButton(
          key: const Key('commit-pilot-prediction'),
          onPressed: !complete || widget.controller.busy
              ? null
              : () => widget.controller.commitPilotPrediction(<String, Object?>{
                  'schema_version': 1,
                  'method_version': pilotPredictionMethodVersion,
                  's1_snapshot_id': plan.s1SnapshotId,
                  'predictions': plan.targets
                      .map(
                        (target) => <String, Object?>{
                          'prediction_key': target.predictionKey,
                          'target_id': target.targetId,
                          'predicted_outcome': _outcomes[target.predictionKey],
                          'confidence': _confidences[target.predictionKey],
                          'evidence_response_ids': target.evidenceResponseIds,
                        },
                      )
                      .toList(growable: false),
                }),
          child: const Text('Commit immutable structured prediction'),
        ),
      ],
    );
  }
}

class _ObservedEvidence extends StatelessWidget {
  const _ObservedEvidence({
    required this.response,
    required this.question,
    required this.targetId,
  });

  final ValidationResponse response;
  final ValidationQuestion question;
  final String targetId;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Observed measurement target: $targetId'),
          Text('Observed question prompt: ${question.prompt}'),
          const Text('Observed choices:'),
          for (var index = 0; index < question.choices.length; index += 1)
            Text(
              '${String.fromCharCode(65 + index)}. ${question.choices[index]}',
            ),
          Text('participant selected choice: ${response.selectedChoice}'),
          Text(response.isCorrect ? 'correct' : 'incorrect'),
          Text('response duration: ${response.durationMs} ms'),
          Text('Observed response ID: ${response.responseId}'),
        ],
      ),
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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    controller
                        .bundle
                        .questionsById[response.questionId]!
                        .prompt,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text('回答: ${response.selectedChoice}'),
                  Text(
                    '正解: ${String.fromCharCode(65 + controller.bundle.questionsById[response.questionId]!.correctIndex)}',
                  ),
                  Text(
                    controller
                        .bundle
                        .questionsById[response.questionId]!
                        .explanation,
                  ),
                ],
              ),
            ),
          ),
        FilledButton(
          key: const Key('continue-to-coverage'),
          onPressed: controller.busy
              ? null
              : controller.continueAfterExplanation,
          child: const Text('Continue to remaining coverage'),
        ),
      ],
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
  final _legacyExport = TextEditingController();
  final _shareButtonKey = GlobalKey();

  Future<void> _shareSavedExport() async {
    final renderObject = _shareButtonKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      throw StateError('Share button position is unavailable.');
    }
    await widget.controller.shareSavedPilotExport(
      renderObject.localToGlobal(Offset.zero) & renderObject.size,
    );
  }

  @override
  void dispose() {
    _legacyExport.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.controller.document!;
    final artifact = widget.controller.exportArtifact;
    return ListView(
      key: const Key('session-complete'),
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Text(
          'Session complete',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text('session_id: ${document.session.sessionId}'),
        Text('route_hash: ${document.route.routeHash}'),
        Text('responses: ${document.responses.length}'),
        const SizedBox(height: 16),
        if (widget.controller.isPilotSession) ...<Widget>[
          FilledButton.icon(
            key: const Key('save-export'),
            onPressed: widget.controller.busy
                ? null
                : widget.controller.savePilotExport,
            icon: const Icon(Icons.save_alt),
            label: const Text('Save JSON file'),
          ),
          if (artifact != null) ...<Widget>[
            const SizedBox(height: 12),
            SelectableText(
              'filename: ${artifact.filename}',
              key: const Key('export-filename'),
            ),
            SelectableText(
              'SHA-256: ${artifact.sha256Digest}',
              key: const Key('export-sha256'),
            ),
            const SizedBox(height: 12),
            KeyedSubtree(
              key: const Key('share-export'),
              child: OutlinedButton.icon(
                key: _shareButtonKey,
                onPressed: widget.controller.busy ? null : _shareSavedExport,
                icon: const Icon(Icons.share),
                label: const Text('Share saved JSON file'),
              ),
            ),
            FilledButton.tonal(
              key: const Key('archive-session'),
              onPressed: widget.controller.busy
                  ? null
                  : widget.controller.archiveAndClose,
              child: const Text('Archive / Close session'),
            ),
          ],
        ] else ...<Widget>[
          FilledButton(
            key: const Key('generate-export'),
            onPressed: () => setState(
              () => _legacyExport.text = widget.controller.exportJson(),
            ),
            child: const Text('Generate one JSON export'),
          ),
          if (_legacyExport.text.isNotEmpty)
            TextField(
              key: const Key('export-json'),
              controller: _legacyExport,
              readOnly: true,
              minLines: 4,
              maxLines: 8,
            ),
        ],
      ],
    );
  }
}
