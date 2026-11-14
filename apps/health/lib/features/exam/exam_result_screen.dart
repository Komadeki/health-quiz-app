// Retain Flutter 3.47 compatibility while Flutter 3.50 deprecates this import.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'exam_access.dart';
import 'exam_question.dart';
import 'exam_result_question_card.dart';
import 'exam_runner_screen.dart';
import 'exam_session.dart';
import 'exam_session_store.dart';

class ExamResultScreen extends StatefulWidget {
  const ExamResultScreen({super.key, required this.session});
  final ExamSession session;

  @override
  State<ExamResultScreen> createState() => _ExamResultScreenState();
}

class _ExamResultScreenState extends State<ExamResultScreen> {
  bool _retrying = false;
  ExamSession get session => widget.session;
  Future<void> _retry(
      BuildContext context, List<ExamQuestion> questions) async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await ensureExamAccess(questions);
      final active = await ExamSessionStore().loadActive();
      if (!context.mounted) return;
      if (active != null) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('途中のテストがあります。定期テスト対策から再開してください。')));
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ExamRunnerScreen(
              questions: questions, unitTitles: session.unitTitles)));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('再挑戦の準備ができませんでした。購入状態や途中のテストを確認してください。')));
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final questions = session.questions;
    final incorrect =
        questions.where((q) => !q.isCorrect(session.responses[q.id])).toList();
    final total = questions.length;
    final score = session.score;
    final units = {for (final q in questions) q.unitId};
    String summary(Iterable<ExamQuestion> items) {
      final list = items.toList();
      final correct =
          list.where((q) => q.isCorrect(session.responses[q.id])).length;
      return '$correct / ${list.length}問（${(correct * 100 / list.length).round()}%）';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('テスト結果')),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('正解: $score / $total問  (${(score * 100 / total).round()}%)',
            style: Theme.of(context).textTheme.headlineSmall),
        const Text('成績を保存しました'),
        const SizedBox(height: 20),
        Text('単元別', style: Theme.of(context).textTheme.titleLarge),
        for (final unit in units)
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(session.unitTitles[unit] ?? unit),
              subtitle:
                  Text(summary(questions.where((q) => q.unitId == unit)))),
        Text('形式別', style: Theme.of(context).textTheme.titleLarge),
        for (final type in ExamQuestionType.values)
          if (questions.any((q) => q.type == type))
            ListTile(
                contentPadding: EdgeInsets.zero,
                title:
                    Text(questions.firstWhere((q) => q.type == type).typeLabel),
                subtitle:
                    Text(summary(questions.where((q) => q.type == type)))),
        const SizedBox(height: 20),
        Text('問題ごとの結果', style: Theme.of(context).textTheme.titleLarge),
        for (var i = 0; i < total; i++)
          ResultQuestionCard(
              index: i + 1,
              question: questions[i],
              response: session.responses[questions[i].id]),
        const SizedBox(height: 16),
        if (incorrect.isNotEmpty)
          FilledButton.icon(
              onPressed: _retrying ? null : () => _retry(context, incorrect),
              icon: const Icon(Icons.refresh),
              label: Text('間違い・未回答の${incorrect.length}問をもう一度')),
        const SizedBox(height: 12),
        OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('戻る')),
      ])),
    );
  }
}

/// Open a durable submitted snapshot from the existing score history.
class ExamHistoryScreen extends StatefulWidget {
  const ExamHistoryScreen({super.key, required this.sessionId});
  final String sessionId;
  @override
  State<ExamHistoryScreen> createState() => _ExamHistoryScreenState();
}

class _ExamHistoryScreenState extends State<ExamHistoryScreen> {
  late final Future<ExamSession> _session = _load();
  Future<ExamSession> _load() async {
    final session = await ExamSessionStore().load(widget.sessionId);
    if (session == null || !session.submitted) {
      throw StateError('この結果の回答記録が見つかりません。');
    }
    await ensureExamAccess(session.questions);
    return session;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<ExamSession>(
      future: _session,
      builder: (context, snapshot) {
        if (snapshot.hasData) return ExamResultScreen(session: snapshot.data!);
        return Scaffold(
            appBar: AppBar(title: const Text('テスト結果')),
            body: Center(
                child: snapshot.hasError
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('回答記録を開けません。購入状態や保存データを確認してください。'))
                    : const CircularProgressIndicator()));
      });
}
