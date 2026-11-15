import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A convenience setting, never a purchase entitlement or exam checkpoint.
class ExamStudySettings {
  ExamStudySettings(
      {required Set<String> unitIds,
      required this.questionCount,
      required this.usePack})
      : unitIds = Set.unmodifiable(unitIds) {
    if (unitIds.isEmpty ||
        unitIds.any((id) => id.trim().isEmpty) ||
        ![10, 20, 30].contains(questionCount)) {
      throw const FormatException('Invalid study settings');
    }
  }
  static const storageKey = 'health_term_exam_study_settings_v1';
  final Set<String> unitIds;
  final int questionCount;
  final bool usePack;

  bool matches(Set<String> selected, int count, bool pack) =>
      unitIds.length == selected.length &&
      unitIds.containsAll(selected) &&
      questionCount == count &&
      usePack == pack;

  static Future<ExamStudySettings?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey);
    if (raw == null) return null;
    final data = jsonDecode(raw);
    if (data is! Map ||
        data['schemaVersion'] != 1 ||
        data['unitIds'] is! List ||
        data['questionCount'] is! int ||
        data['usePack'] is! bool ||
        !(data['unitIds'] as List).every((id) => id is String)) {
      throw const FormatException('Invalid study settings');
    }
    return ExamStudySettings(
        unitIds: Set<String>.from(data['unitIds'] as List),
        questionCount: data['questionCount'] as int,
        usePack: data['usePack'] as bool);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(storageKey)) {
      throw StateError('Study settings could not be cleared');
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = unitIds.toList()..sort();
    final written = await prefs.setString(
        storageKey,
        jsonEncode({
          'schemaVersion': 1,
          'unitIds': ids,
          'questionCount': questionCount,
          'usePack': usePack,
        }));
    if (!written) throw StateError('Study settings could not be saved');
  }
}
