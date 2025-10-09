// lib/data/quiz_session_local_repository.dart
import 'package:shared_preferences/shared_preferences.dart';
import '../models/quiz_session.dart';

class QuizSessionLocalRepository {
  QuizSessionLocalRepository(this.prefs);

  final SharedPreferences prefs;

  /// セッション保存キー（固定）
  static const String _key = 'active_quiz_session_v1';

  /// 安定IDバージョン管理キー
  static const String _stableVerKey = 'stable_id_version';

  /// 現行の安定ID式バージョン
  static const String _currentStableVer = '2';

  // ──────────────────────────────
  // 移行チェック：初回起動時 or 式変更時に古いセッションを破棄
  // ──────────────────────────────
  Future<void> migrateIfNeeded() async {
    final ver = prefs.getString(_stableVerKey);
    if (ver != _currentStableVer) {
      await clear();
      await prefs.setString(_stableVerKey, _currentStableVer);
      // print('[SESSION] migrate: cleared old sessions (ver=$ver→$_currentStableVer)');
    }
  }

  // ──────────────────────────────
  // 保存
  // ──────────────────────────────
  Future<void> save(QuizSession s) async {
    final encoded = s.encode();
    await prefs.setString(_key, encoded);
    // print('[SESSION] saved deck=${s.deckId} index=${s.currentIndex} len=${s.itemIds.length}');
  }

  // ──────────────────────────────
  // 読込（破損時は自動削除して null を返す）
  // ──────────────────────────────
  Future<QuizSession?> loadActive() async {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;

    final s = QuizSession.decode(raw);
    if (s == null) {
      await clear();
      // print('[SESSION] decode failed → cleared');
      return null;
    }
    return s;
  }

  // ──────────────────────────────
  // クリア
  // ──────────────────────────────
  Future<void> clear() async {
    await prefs.remove(_key);
    // print('[SESSION] cleared');
  }
}
