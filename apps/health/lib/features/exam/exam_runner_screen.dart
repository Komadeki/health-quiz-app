import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../../models/score_record.dart';
import '../../services/attempt_store.dart';
import 'exam_question.dart';

/// Answer the test first; show correctness only after submission.
class ExamRunnerScreen extends StatefulWidget {
  const ExamRunnerScreen({
    super.key,
    required this.questions,
    required this.unitTitles,
  });
  final List<ExamQuestion> questions;
  final Map<String, String> unitTitles;

  @override
  State<ExamRunnerScreen> createState() => _ExamRunnerScreenState();
}

class _ExamRunnerScreenState extends State<ExamRunnerScreen> {
  final _responses = <String, String>{};
  final _text = TextEditingController();
  final _watch = Stopwatch()..start();
  int _index = 0;
  bool _finishing = false;

  ExamQuestion get _question => widget.questions[_index];

  @override
  void dispose() {
    _watch.stop();
    _text.dispose();
    super.dispose();
  }

  void _answer(String value) {
    setState(() => _responses[_question.id] = value);
  }

  void _back() {
    if (_index == 0) return;
    setState(() => _index--);
    _text.text = _responses[_question.id] ?? '';
  }

  void _next() {
    if (_finishing) return;
    if (_index + 1 == widget.questions.length) {
      _finish();
    } else {
      setState(() => _index++);
      _text.text = _responses[_question.id] ?? '';
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    final empty = widget.questions.where(
      (q) => (_responses[q.id] ?? '').trim().isEmpty,
    ).length;
    if (empty > 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('採点の確認'),
          content: Text('未回答が$empty問あります。不正解として採点しますか？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('戻る'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('採点する'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _finishing = true);
    _watch.stop();
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ExamResultScreen(
          questions: widget.questions,
          responses: Map.unmodifiable(_responses),
          unitTitles: widget.unitTitles,
          durationSeconds: _watch.elapsed.inSeconds,
          sessionId: const Uuid().v4(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _question;
    final selected = _responses[q.id];
    return Scaffold(
      appBar: AppBar(
        title: Text('テスト ' + (_index + 1).toString() +
            '/' + widget.questions.length.toString()),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: (_index + 1) / widget.questions.length,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text(widget.unitTitles[q.unitId] ?? q.unitId,
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 14),
                  Text(q.question,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 24),
                  if (q.type == ExamQuestionType.choice)
                    for (var i = 0; i < q.choices.length; i++)
                      Card(
                        child: ListTile(
                          leading: Icon(selected == i.toString()
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked),
                          title: Text(q.choices[i]),
                          onTap: () => _answer(i.toString()),
                        ),
                      ),
                  if (q.type == ExamQuestionType.trueFalse)
                    Row(
                      children: [
                        for (final response in const ['○', '×'])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(6),
                              child: OutlinedButton(
                                onPressed: () => _answer(response),
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: selected == response
                                      ? Theme.of(context)
                                          .colorScheme.primaryContainer
                                      : null,
                                  minimumSize: const Size(60, 68),
                                ),
                                child: Text(response,
                                    style: const TextStyle(fontSize: 28)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  if (q.type == ExamQuestionType.fill)
                    TextField(
                      controller: _text,
                      onChanged: _answer,
                      decoration: const InputDecoration(
                        labelText: '空欄に入る言葉',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  const SizedBox(height: 12),
                  const Text('正解と解説はテスト終了後に表示します。'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_index > 0) ...[
                    OutlinedButton(
                      onPressed: _finishing ? null : _back,
                      child: const Text('前の問題'),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: _finishing ? null : _next,
                      child: Text(_index + 1 == widget.questions.length
                          ? '採点する'
                          : '次の問題へ'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ExamResultScreen extends StatefulWidget {
  const ExamResultScreen({
    super.key,
    required this.questions,
    required this.responses,
    required this.unitTitles,
    required this.durationSeconds,
    required this.sessionId,
  });
  final List<ExamQuestion> questions;
  final Map<String, String> responses;
  final Map<String, String> unitTitles;
  final int durationSeconds;
  final String sessionId;

  @override
  State<ExamResultScreen> createState() => _ExamResultScreenState();
}

class _ExamResultScreenState extends State<ExamResultScreen> {
  bool _saving = false;
  bool _saved = false;
  String? _saveError;

  int get _score => widget.questions.where(
    (q) => q.isCorrect(widget.responses[q.id]),
  ).length;

  @override
  void initState() {
    super.initState();
    _saveScore();
  }

  Future<void> _saveScore() async {
    if (_saving || _saved) return;
    setState(() { _saving = true; _saveError = null; });
    final counts = <String, int>{};
    for (final q in widget.questions) {
      counts.update(q.unitId, (v) => v + 1, ifAbsent: () => 1);
    }
    try {
      final store = AttemptStore();
      await store.addScore(
        ScoreRecord(
          id: widget.sessionId,
          deckId: 'exam',
          deckTitle: '定期テスト対策',
          score: _score,
          total: widget.questions.length,
          timestamp: DateTime.now().millisecondsSinceEpoch,
          durationSec: widget.durationSeconds,
          sessionId: widget.sessionId,
          selectedUnitIds: counts.keys.toList(growable: false),
          unitBreakdown: counts,
          examProfileVersion: 'health-term-exam-v1',
        ),
      );
      // This repository's storage layer swallows write failures; verify that
      // the session is actually readable before showing "saved".
      final exists = (await store.loadScores())
          .any((record) => record.sessionId == widget.sessionId);
      if (!exists) throw StateError('保存結果を読み戻せませんでした');
      if (mounted) setState(() => _saved = true);
    } catch (error) {
      if (mounted) setState(() => _saveError = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final incorrect = widget.questions.where(
      (q) => !q.isCorrect(widget.responses[q.id]),
    ).toList(growable: false);
    final total = widget.questions.length;
    final percent = total == 0 ? 0 : (_score * 100 / total).round();
    return Scaffold(
      appBar: AppBar(title: const Text('テスト結果')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('正解: $_score / $total問  ($percent%)',
                style: Theme.of(context).textTheme.headlineSmall),
            if (_saving) const Text('成績を保存中…'),
            if (_saved) const Text('成績を保存しました'),
            if (_saveError != null) ...[
              const Text('成績の保存に失敗しました。'),
              TextButton(
                onPressed: _saving ? null : _saveScore,
                child: const Text('再保存する'),
              ),
            ],
            const SizedBox(height: 20),
            Text('問題ごとの結果',
                style: Theme.of(context).textTheme.titleLarge),
            for (var i = 0; i < widget.questions.length; i++)
              _ResultQuestionCard(
                index: i + 1,
                question: widget.questions[i],
                response: widget.responses[widget.questions[i].id],
              ),
            const SizedBox(height: 16),
            if (incorrect.isNotEmpty)
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => ExamRunnerScreen(
                      questions: incorrect,
                      unitTitles: widget.unitTitles,
                    ),
                  ),
                ),
                icon: const Icon(Icons.refresh),
                label: Text('間違えた' + incorrect.length.toString() +
                    '問をもう一度'),
              ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('試験範囲の選択へ戻る'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultQuestionCard extends StatelessWidget {
  const _ResultQuestionCard({
    required this.index,
    required this.question,
    required this.response,
  });
  final int index;
  final ExamQuestion question;
  final String? response;

  String get _responseLabel {
    if (response == null || response!.isEmpty) return '未回答';
    if (question.type == ExamQuestionType.choice) {
      final value = int.tryParse(response!);
      if (value == null || value < 0 || value >= question.choices.length) {
        return '不明な回答';
      }
      return question.choices[value];
    }
    return response!;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (question.isCorrect(response) ? '正解' : '不正解') +
                  '  問題 ' + index.toString(),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(question.question),
            const SizedBox(height: 8),
            Text('あなたの回答: $_responseLabel'),
            Text('正解: ' + question.answerLabel),
            Text(question.explanation),
          ],
        ),
      ),
    );
  }
}
