import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/attempt_entry.dart';
import '../utils/logger.dart';

class AttemptStore {
  static const String kAttempts = 'attempts_v1'; // JSON 1本保存
  static const int defaultRetention = 5000;

  AttemptStore._();
  static final AttemptStore _i = AttemptStore._();
  factory AttemptStore() => _i;

  // ---- private helpers ----

  Future<List<AttemptEntry>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kAttempts);
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      final items = <AttemptEntry>[];
      for (final e in list) {
        try {
          final map = (e as Map).cast<String, dynamic>();
          var a = AttemptEntry.fromMap(map);

          // attemptId が無い古いデータに対しては補完
          if ((a.attemptId == null) || (a.attemptId!.isEmpty)) {
            a = a.copyWith(attemptId: const Uuid().v4());
          }
          items.add(a);
        } catch (err) {
          AppLog.w('[AttemptStore] skip broken item: $err');
        }
      }
      return items;
    } catch (e) {
      AppLog.w('[AttemptStore] decode failed: $e');
      return [];
    }
  }

  Future<void> _saveAll(List<AttemptEntry> items) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      // 念のため attemptId が空のものがあれば付与
      final normalized = items
          .map((a) => (a.attemptId == null || a.attemptId!.isEmpty)
              ? a.copyWith(attemptId: const Uuid().v4())
              : a)
          .toList();

      final ok = await prefs.setString(
        kAttempts,
        jsonEncode(normalized.map((e) => e.toMap()).toList()),
      );
      if (!ok) {
        AppLog.w('[AttemptStore] persist failed');
      }
    } catch (e) {
      AppLog.w('[AttemptStore] saveAll failed: $e');
    }
  }

  // ---- public API ----

  Future<void> add(AttemptEntry entry, {int? retention}) async {
    final all = await _loadAll();

    // attemptId の自動付与（モデル側で未設定の場合）
    final withId = (entry.attemptId == null || entry.attemptId!.isEmpty)
        ? entry.copyWith(attemptId: const Uuid().v4())
        : entry;

    all.add(withId);

    final cap = retention ?? defaultRetention;
    if (all.length > cap) {
      all.removeRange(0, all.length - cap); // 古い方から間引く
    }
    await _saveAll(all);
  }

  /// 新しいものから最大 limit 件
  Future<List<AttemptEntry>> recent({int limit = 100}) async {
    final all = await _loadAll();
    return all.reversed.take(limit).toList();
  }

  /// 指定セッションの履歴（新→古）
  Future<List<AttemptEntry>> bySession(String sessionId) async {
    final all = await _loadAll();
    return all.where((e) => e.sessionId == sessionId).toList().reversed.toList();
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kAttempts);
  }

  /// バックアップ用。軽量で扱いやすいシェイプに
  Future<String> exportJson() async {
    final all = await _loadAll();
    return jsonEncode({
      'version': 1,
      'items': all.map((e) => e.toMap()).toList(),
      'count': all.length,
      'exportedAt': DateTime.now().toIso8601String(),
    });
  }

  /// 既存にマージ。attemptId 重複はスキップ
  Future<int> importJson(String json) async {
    try {
      final data = jsonDecode(json) as Map<String, dynamic>;
      final rawItems = (data['items'] as List<dynamic>? ?? const <dynamic>[]);

      final items = <AttemptEntry>[];
      for (final e in rawItems) {
        try {
          final map = (e as Map).cast<String, dynamic>();
          var a = AttemptEntry.fromMap(map);
          if ((a.attemptId == null) || a.attemptId!.isEmpty) {
            a = a.copyWith(attemptId: const Uuid().v4());
          }
          items.add(a);
        } catch (err) {
          AppLog.w('[AttemptStore] import skip broken item: $err');
        }
      }

      final existing = await _loadAll();
      final ids = existing
          .map((e) => e.attemptId ?? '')
          .where((s) => s.isNotEmpty)
          .toSet();

      final toAdd = items.where((e) {
        final id = e.attemptId ?? '';
        return id.isNotEmpty && !ids.contains(id);
      }).toList();

      existing.addAll(toAdd);
      await _saveAll(existing);
      return toAdd.length;
    } catch (e) {
      AppLog.w('[AttemptStore] import failed: $e');
      return 0;
    }
  }

  /// 総件数（デバッグ用）
  Future<int> count() async {
    final all = await _loadAll();
    return all.length;
  }
}
