// Retain Flutter 3.47 compatibility while Flutter 3.50 deprecates this import.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'exam_question.dart';
import 'exam_session.dart';
import 'exam_session_store.dart';
import 'exam_access.dart';
import 'exam_result_screen.dart';

/// Answers are checkpointed in their displayed order; grading is deferred.
class ExamRunnerScreen extends StatefulWidget {
  const ExamRunnerScreen(
      {super.key,
      required this.questions,
      required this.unitTitles,
      this.session});
  final List<ExamQuestion> questions;
  final Map<String, String> unitTitles;
  final ExamSession? session;
  @override
  State<ExamRunnerScreen> createState() => _ExamRunnerScreenState();
}

class _ExamRunnerScreenState extends State<ExamRunnerScreen>
    with WidgetsBindingObserver {
  final _responses = <String, String>{};
  final _text = TextEditingController();
  final _watch = Stopwatch()..start();
  final _store = ExamSessionStore();
  late ExamSession _session;
  int _index = 0;
  bool _busy = false;
  bool _allowPop = false;
  String? _saveError;
  ExamQuestion get _question => widget.questions[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = widget.session ??
        ExamSession(
            id: 'exam-${const Uuid().v4()}',
            questions: widget.questions,
            unitTitles: widget.unitTitles,
            startedAt: DateTime.now());
    _responses.addAll(_session.responses);
    _index = _session.index;
    _text.text = _responses[_question.id] ?? '';
    if (_session.submitted) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _finish());
    } else {
      _persist();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && !_session.submitted) _persist();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watch.stop();
    _text.dispose();
    super.dispose();
  }

  Future<bool> _persist() async {
    final snapshot = _session.progress(
        responses: Map.of(_responses),
        index: _index,
        elapsedSeconds: _session.elapsedSeconds + _watch.elapsed.inSeconds);
    try {
      await _store.save(snapshot);
      if (mounted) setState(() => _saveError = null);
      return true;
    } catch (error) {
      if (mounted) setState(() => _saveError = error.toString());
      return false;
    }
  }

  void _answer(String value) {
    if (_busy || _session.submitted) return;
    setState(() => _responses[_question.id] = value);
    _persist();
  }

  Future<void> _move(int index) async {
    if (_busy || _session.submitted) return;
    setState(() {
      _busy = true;
      _index = index;
    });
    _text.text = _responses[_question.id] ?? '';
    await _persist();
    if (mounted) setState(() => _busy = false);
  }

  void _back() => _move(_index - 1);
  void _next() {
    if (_busy) return;
    if (_index + 1 == widget.questions.length) {
      _finish();
    } else {
      _move(_index + 1);
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    setState(() => _busy = true);
    final saved = _session.submitted ? true : await _persist();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _allowPop = saved;
    });
    if (saved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> _finish() async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      if (!_session.submitted) {
        final empty = widget.questions
            .where((q) => (_responses[q.id] ?? '').trim().isEmpty)
            .length;
        if (empty > 0) {
          final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                      title: const Text('採点の確認'),
                      content: Text('未回答が$empty問あります。不正解として採点しますか？'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('戻る')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('採点する'))
                      ]));
          if (confirmed != true || !mounted) return;
        }
        _session = _session.progress(
            responses: Map.of(_responses),
            index: _index,
            elapsedSeconds: _session.elapsedSeconds + _watch.elapsed.inSeconds,
            submittedAt: DateTime.now());
        _watch.stop();
        _watch.reset();
      }
      await ensureExamAccess(_session.questions);
      await _store.finish(_session);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => ExamResultScreen(session: _session)));
    } catch (error) {
      if (mounted) {
        setState(() => _saveError = error.toString());
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('結果を保存できませんでした。再試行できます。')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _question;
    final selected = _responses[q.id];
    return PopScope(
        canPop: _allowPop,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _leave();
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text('テスト ${_index + 1}/${widget.questions.length}'),
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
                if (_saveError != null)
                  MaterialBanner(
                      content: const Text('途中経過を保存できませんでした。'),
                      actions: [
                        TextButton(
                            onPressed: () => _persist(),
                            child: const Text('再試行'))
                      ]),
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
                              onTap: _busy ? null : () => _answer(i.toString()),
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
                                    onPressed:
                                        _busy ? null : () => _answer(response),
                                    style: OutlinedButton.styleFrom(
                                      backgroundColor: selected == response
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primaryContainer
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
                          enabled: !_busy,
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
                          onPressed: _busy ? null : _back,
                          child: const Text('前の問題'),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy ? null : _next,
                          child: Text(_index + 1 == widget.questions.length
                              ? (_session.submitted ? '結果の保存を再試行' : '採点する')
                              : '次の問題へ'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ));
  }
}
