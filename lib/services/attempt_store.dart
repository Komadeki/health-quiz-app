import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/attempt_entry.dart';

class AttemptStore {
  static const String kAttempts = 'attempts_v1';
  static const int defaultRetention = 5000;

  AttemptStore._();
  static final AttemptStore _i = AttemptStore._();
  factory AttemptStore() => _i;

  Future<List<AttemptEntry>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kAttempts);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => AttemptEntry.fromMap(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveAll(List<AttemptEntry> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kAttempts,
      jsonEncode(items.map((e) => e.toMap()).toList()),
    );
  }

  Future<void> add(AttemptEntry entry, {int? retention}) async {
    final all = await _loadAll();
    all.add(entry);
    final cap = retention ?? defaultRetention;
    if (all.length > cap) {
      all.removeRange(0, all.length - cap);
    }
    await _saveAll(all);
  }

  Future<List<AttemptEntry>> recent({int limit = 100}) async {
    final all = await _loadAll();
    return all.reversed.take(limit).toList();
  }

  Future<List<AttemptEntry>> bySession(String sessionId) async {
    final all = await _loadAll();
    return all
        .where((e) => e.sessionId == sessionId)
        .toList()
        .reversed
        .toList();
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kAttempts);
  }

  Future<String> exportJson() async {
    final all = await _loadAll();
    return jsonEncode({
      'version': 1,
      'items': all.map((e) => e.toMap()).toList(),
    });
  }

  Future<int> importJson(String json) async {
    final data = jsonDecode(json) as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>)
        .map((e) => AttemptEntry.fromMap(e as Map<String, dynamic>))
        .toList();

    final existing = await _loadAll();
    final ids = existing.map((e) => e.attemptId).toSet();
    final toAdd = items.where((e) => !ids.contains(e.attemptId)).toList();
    existing.addAll(toAdd);
    await _saveAll(existing);
    return toAdd.length;
  }
}
