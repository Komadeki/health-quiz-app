// lib/data/quiz_session_local_repository.dart
import 'package:shared_preferences/shared_preferences.dart';
import '../models/quiz_session.dart';

class QuizSessionLocalRepository {
  QuizSessionLocalRepository(this.prefs);

  final SharedPreferences prefs;

  // キーは v1 で固定（Home/QuizScreen と一致）
  static const String _key = 'active_quiz_session_v1';

  Future<void> save(QuizSession s) async {
    await prefs.setString(_key, QuizSession.encode(s));
  }

  Future<QuizSession?> loadActive() async {
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final s = QuizSession.decode(raw);
      // 必要ならここでバリデーション
      return s;
    } catch (_) {
      // 破損時は読めなかったことにする
      return null;
    }
  }

  Future<void> clear() async {
    await prefs.remove(_key);
  }
}
