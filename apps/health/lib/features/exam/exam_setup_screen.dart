import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../models/deck.dart';
import '../../services/gate.dart';
import 'exam_question.dart';
import 'exam_range_selector.dart';
import 'exam_runner_screen.dart';

/// Learners choose their school's real exam scope, regardless of grade.
class ExamSetupScreen extends StatefulWidget {
  const ExamSetupScreen({super.key, required this.decks});
  final List<Deck> decks;

  @override
  State<ExamSetupScreen> createState() => _ExamSetupScreenState();
}

class _ExamSetupScreenState extends State<ExamSetupScreen> {
  final _selectedUnits = <String>{};
  final _selector = const ExamRangeSelector();
  final _access = <String, bool>{};
  List<ExamQuestion> _authored = [];
  int _requested = 10;
  bool _loading = true;
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadQuestionsAndAccess();
  }

  Future<void> _loadQuestionsAndAccess() async {
    try {
      final raw = await rootBundle.loadString('assets/exam/exam_questions_v1.json');
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      final entries = parsed['questions'] as List<dynamic>;
      final authored = entries.map((raw) =>
        ExamQuestion.fromJson(Map<String, dynamic>.from(raw as Map)),
      ).toList(growable: false);
      final access = <String, bool>{};
      for (final deck in widget.decks) {
        access[deck.id.toLowerCase()] = await Gate.canAccessDeck(deck.id);
      }
      if (!mounted) return;
      setState(() {
        _authored = authored;
        _access..clear()..addAll(access);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Map<String, String> get _unitTitles => {
    for (final deck in widget.decks)
      for (final unit in deck.units) unit.id: unit.title,
  };

  List<ExamQuestion> _accessibleQuestions(Map<String, bool> owned) {
    final questions = <ExamQuestion>[];
    final unitToDeck = <String, String>{};
    for (final deck in widget.decks) {
      final unlocked = owned[deck.id.toLowerCase()] == true;
      for (final unit in deck.units) {
        unitToDeck[unit.id] = deck.id.toLowerCase();
        if (!_selectedUnits.contains(unit.id)) continue;
        for (final card in unit.cards) {
          if (!card.isPremium || unlocked) {
            try {
              questions.add(ExamQuestion.fromLegacy(card));
            } on FormatException catch (error) {
              debugPrint('[EXAM] Invalid legacy item: $error');
            }
          }
        }
      }
    }
    for (final question in _authored) {
      if (!_selectedUnits.contains(question.unitId)) continue;
      final deckId = unitToDeck[question.unitId];
      if (deckId == null) continue;
      if (!question.isPremium || owned[deckId] == true) {
        questions.add(question);
      }
    }
    return questions;
  }

  int get _available {
    if (_loading || _selectedUnits.isEmpty) return 0;
    return _selector.availableCount(
      accessibleQuestions: _accessibleQuestions(_access),
      selectedUnitIds: _selectedUnits,
    );
  }

  Future<void> _start() async {
    if (_starting || _selectedUnits.isEmpty) return;
    setState(() => _starting = true);
    try {
      // Check actual purchase rights again when composing an exam.
      final currentAccess = <String, bool>{};
      for (final deck in widget.decks) {
        currentAccess[deck.id.toLowerCase()] =
            await Gate.canAccessDeck(deck.id);
      }
      final questions = _selector.select(
        accessibleQuestions: _accessibleQuestions(currentAccess),
        selectedUnitIds: _selectedUnits,
        questionCount: _requested,
      );
      if (!mounted) return;
      if (questions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('この範囲で出題できる問題はありません。')),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ExamRunnerScreen(
            questions: questions,
            unitTitles: _unitTitles,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('テストの準備に失敗しました: $error')),
      );
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = _available;
    final effective = available < _requested ? available : _requested;
    final canStart = !_loading && !_starting &&
        _selectedUnits.isNotEmpty && available > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('定期テスト対策')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('問題を読み込めませんでした: $_error'),
                      TextButton(
                        onPressed: () {
                          setState(() { _loading = true; _error = null; });
                          _loadQuestionsAndAccess();
                        },
                        child: const Text('再試行'),
                      ),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    Text('試験範囲を選択',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    const Text('学校の試験範囲に合わせて単元を選択してください。'
                        '選択した範囲だけから問題を自動で選びます。'),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => setState(() {
                            _selectedUnits
                              ..clear()
                              ..addAll(widget.decks.expand(
                                (deck) => deck.units.map((unit) => unit.id),
                              ));
                          }),
                          child: const Text('すべて選択'),
                        ),
                        TextButton(
                          onPressed: () => setState(_selectedUnits.clear),
                          child: const Text('選択を解除'),
                        ),
                      ],
                    ),
                    for (final deck in widget.decks)
                      Card(
                        child: ExpansionTile(
                          title: Text(deck.title),
                          subtitle: Text(
                            deck.units.where(
                              (unit) => _selectedUnits.contains(unit.id),
                            ).length.toString() +
                            ' / ' + deck.units.length.toString() + '単元を選択',
                          ),
                          children: [
                            for (final unit in deck.units)
                              CheckboxListTile(
                                dense: true,
                                title: Text(unit.title),
                                value: _selectedUnits.contains(unit.id),
                                onChanged: (checked) => setState(() {
                                  if (checked == true) {
                                    _selectedUnits.add(unit.id);
                                  } else {
                                    _selectedUnits.remove(unit.id);
                                  }
                                }),
                              ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text('問題数',
                        style: Theme.of(context).textTheme.titleMedium),
                    Wrap(
                      spacing: 10,
                      children: [
                        for (final count in const [10, 20, 30])
                          ChoiceChip(
                            label: Text('$count問'),
                            selected: _requested == count,
                            onSelected: (_) =>
                                setState(() => _requested = count),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(_selectedUnits.isEmpty
                        ? 'まず単元を選んでください'
                        : '出題可能: $available問 / 今回のテスト: $effective問'),
                    if (_selectedUnits.isNotEmpty && available < _requested)
                      const Text('不足時は問題を重複させず、出題できる数で実施します。'),
                    const SizedBox(height: 32),
                  ],
                ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton.icon(
          onPressed: canStart ? _start : null,
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(_starting
              ? '作成中…'
              : effective > 0
                  ? 'この範囲から$effective問を自動作成'
                  : '単元を選択してください'),
        ),
      ),
    );
  }
}
