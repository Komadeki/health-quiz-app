import 'dart:convert';
// Retain Flutter 3.47 compatibility while Flutter 3.50 deprecates this import.
// ignore: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../models/deck.dart';
import '../../services/gate.dart';
import '../../services/purchase_store.dart';
import '../../screens/purchase_screen.dart';
import 'exam_question.dart';
import 'exam_range_selector.dart';
import 'exam_runner_screen.dart';
import 'exam_session.dart';
import 'exam_session_store.dart';
import 'exam_access.dart';

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
  bool _packOwned = false;
  bool _usePack = false;
  bool _invalidActive = false;
  ExamSession? _active;
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
      final raw =
          await rootBundle.loadString('assets/exam/exam_questions_v1.json');
      final parsed = jsonDecode(raw) as Map<String, dynamic>;
      if (parsed['schemaVersion'] != 1 && parsed['schemaVersion'] != 2) {
        throw const FormatException('Unsupported exam question bank');
      }
      final packRaw = jsonDecode(
              await rootBundle.loadString('assets/exam/exam_pack_v1.json'))
          as Map<String, dynamic>;
      if (packRaw['schemaVersion'] != 2) {
        throw const FormatException('Unsupported exam pack');
      }
      final packOwned = await PurchaseStore.isExamPackOwned();
      final entries = [
        ...(parsed['questions'] as List<dynamic>),
        ...(packRaw['questions'] as List<dynamic>)
      ];
      final authored = entries
          .map(
            (raw) =>
                ExamQuestion.fromJson(Map<String, dynamic>.from(raw as Map)),
          )
          .toList(growable: false);
      final access = <String, bool>{};
      for (final deck in widget.decks) {
        access[deck.id.toLowerCase()] = await Gate.canAccessDeck(deck.id);
      }
      ExamSession? active;
      var invalidActive = false;
      try {
        active = await ExamSessionStore().loadActive();
      } catch (_) {
        invalidActive = true;
      }
      if (!mounted) return;
      setState(() {
        _active = active;
        _invalidActive = invalidActive;
        _authored = authored;
        if (!_packOwned && packOwned) _usePack = true;
        if (!packOwned) _usePack = false;
        _packOwned = packOwned;
        _access
          ..clear()
          ..addAll(access);
        _loading = false;
        _error = invalidActive ? '途中経過を読み込めませんでした。' : null;
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

  List<ExamQuestion> _accessibleQuestions(Map<String, bool> owned,
      {bool? packOwned}) {
    final questions = <ExamQuestion>[];
    final usePack = _usePack && (packOwned ?? _packOwned);
    final unitToDeck = <String, String>{};
    for (final deck in widget.decks) {
      final unlocked = owned[deck.id.toLowerCase()] == true;
      for (final unit in deck.units) {
        unitToDeck[unit.id] = deck.id.toLowerCase();
        if (!_selectedUnits.contains(unit.id)) continue;
        if (usePack) continue;
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
      if (question.requiresExamPack != usePack) continue;
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
    if (_starting || _selectedUnits.isEmpty || _active != null) return;
    setState(() => _starting = true);
    try {
      // Check actual purchase rights again when composing an exam.
      final currentAccess = <String, bool>{};
      for (final deck in widget.decks) {
        currentAccess[deck.id.toLowerCase()] =
            await Gate.canAccessDeck(deck.id);
      }
      final currentPackOwned = await PurchaseStore.isExamPackOwned();
      if (_usePack && !currentPackOwned) {
        throw StateError('追加パックの購入を復元してください。');
      }
      final questions = _selector
          .select(
            accessibleQuestions: _accessibleQuestions(currentAccess,
                packOwned: currentPackOwned),
            selectedUnitIds: _selectedUnits,
            questionCount: _requested,
          )
          .map((q) => q.shuffledChoices())
          .toList(growable: false);
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
        const SnackBar(content: Text('テストの準備に失敗しました。もう一度お試しください。')),
      );
    } finally {
      if (mounted) {
        setState(() => _starting = false);
        _loadQuestionsAndAccess();
      }
    }
  }

  Future<void> _resume() async {
    if (_starting || _active == null) return;
    setState(() => _starting = true);
    try {
      final session = _active!;
      await ensureExamAccess(session.questions);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ExamRunnerScreen(
              questions: session.questions,
              unitTitles: session.unitTitles,
              session: session)));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('再開できませんでした。購入状態や保存データを確認してください。')));
      }
    } finally {
      if (mounted) {
        setState(() => _starting = false);
        _loadQuestionsAndAccess();
      }
    }
  }

  Future<void> _discard() async {
    final session = _active;
    if (session == null || _starting || session.submitted) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('別のテストを始めますか？'),
                content: const Text('現在のテストを途中から再開することはできなくなります。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('キャンセル')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('新しく始める'))
                ]));
    if (confirmed != true || !mounted) return;
    try {
      await ExamSessionStore().clearActive(session.id);
      if (mounted) setState(() => _active = null);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('途中データを更新できませんでした。もう一度お試しください。')));
      }
    }
  }

  Future<void> _recover() async {
    if (_starting) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('途中経過を退避しますか？'),
                content: const Text(
                    '読み込めない途中経過を端末内に退避し、新しいテストを始められるようにします。既存の成績と購入状態は保持されます。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('キャンセル')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('退避して続ける'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => _starting = true);
    try {
      await ExamSessionStore().archiveUnreadableActive();
      await _loadQuestionsAndAccess();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('途中経過を退避できませんでした。保存データは保持しています。')));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = _available;
    final effective = available < _requested ? available : _requested;
    final canStart = _error == null &&
        !_loading &&
        !_starting &&
        _active == null &&
        _selectedUnits.isNotEmpty &&
        available > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('定期テスト対策')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text('問題または途中経過を読み込めませんでした。保存データは保持しています。'),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _error = null;
                          });
                          _loadQuestionsAndAccess();
                        },
                        child: const Text('再試行'),
                      ),
                      if (_invalidActive)
                        TextButton(
                            onPressed: _starting ? null : _recover,
                            child: const Text('途中経過を退避して新しく始める')),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    const Text('穴埋め・正誤判断・短答記述・4択（意味理解・活用）を、使える形式の間で均等に出題します。'),
                    Card(
                        child: ListTile(
                      title: Text(_packOwned ? 'テスト対策パック：購入済み' : '全46単元の追加問題'),
                      subtitle: Text(_packOwned
                          ? '各単元の4形式を利用できます。'
                          : '無料40問はそのまま。追加パックは買い切り。価格は購入画面で確認できます。通常の単元購入・Proとは別です。'),
                      trailing:
                          _packOwned ? null : const Icon(Icons.chevron_right),
                      onTap: _packOwned
                          ? null
                          : () async {
                              await Navigator.of(context).push(
                                  MaterialPageRoute<bool>(
                                      builder: (_) => const PurchaseScreen()));
                              if (mounted) await _loadQuestionsAndAccess();
                            },
                    )),
                    if (_packOwned)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('追加パックから出題'),
                        subtitle: Text(_usePack
                            ? '全46単元・736問。各形式4問ずつの追加問題から出題します。'
                            : '従来の4択と無料40問から出題します。'),
                        value: _usePack,
                        onChanged: _active != null
                            ? null
                            : (value) => setState(() => _usePack = value),
                      ),
                    const SizedBox(height: 12),
                    if (_active != null)
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(_active!.submitted
                                        ? '保存待ちの結果があります'
                                        : '途中のテストがあります'),
                                    Text(
                                        '${_active!.responses.values.where((s) => s.trim().isNotEmpty).length} / ${_active!.questions.length}問に回答済み'),
                                    FilledButton(
                                        onPressed: _starting ? null : _resume,
                                        child: Text(_active!.submitted
                                            ? '結果の保存を再開'
                                            : '途中から再開')),
                                    if (!_active!.submitted)
                                      TextButton(
                                          onPressed:
                                              _starting ? null : _discard,
                                          child: const Text('別のテストを始める')),
                                  ]))),
                    Text('試験範囲を選択',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 6),
                    const Text('学校の試験範囲に合わせて単元を選択してください。'
                        '選択した範囲だけから問題を自動で選びます。形式ごとの問題不足時は、偏りを抑えて出題数を減らします。'),
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
                            '${deck.units.where((unit) => _selectedUnits.contains(unit.id)).length} / ${deck.units.length}単元を選択',
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
                    Text('問題数', style: Theme.of(context).textTheme.titleMedium),
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
