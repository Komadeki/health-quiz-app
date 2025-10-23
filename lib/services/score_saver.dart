// lib/services/score_saver.dart
import '../models/score_record.dart';
import 'score_store.dart' as score_store;
import '../utils/logger.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 先頭でimport
import '../models/quiz_session.dart'; // ★追加

/// スコア保存の単一入口。
/// - 表示側（Scores）は ScoreStore を参照しているため、必ず ScoreStore に保存する。
/// - 復習テスト（deckId == 'review'）のときは、deckTitle を「復習テスト」に正規化する。
class ScoreSaver {
  /// 保存（失敗時は例外を投げる）
  static Future<void> save(ScoreRecord raw) async {
    final normalized = _normalizeForReview(raw);
    try {
      // ScoreStore の API は add(ScoreRecord)（提示ファイルに準拠）
      await score_store.ScoreStore.instance.add(normalized);
      AppLog.d(
        '[SCORE_SAVER] saved: id=${normalized.id}, deckId=${normalized.deckId}, title=${normalized.deckTitle}',
      );
    } catch (e, st) {
      AppLog.e('[SCORE_SAVER] failed to save score: $e\n$st');
      rethrow;
    }
  }

  /// 復習テストの表示名を保証する。
  /// copyWith が無い前提で、新しい ScoreRecord を組み直す。
  static ScoreRecord _normalizeForReview(ScoreRecord r) {
    if (r.deckId == 'review' && r.deckTitle != '復習テスト') {
      return ScoreRecord(
        id: r.id,
        deckId: r.deckId,
        deckTitle: '復習テスト', // ← 正規化
        score: r.score,
        total: r.total,
        timestamp: r.timestamp,
        durationSec: r.durationSec,
        tags: r.tags,
        selectedUnitIds: r.selectedUnitIds,
        sessionId: r.sessionId,
        unitBreakdown: r.unitBreakdown,
      );
    }
    return r;
  }
  // ============================================
  // Active Quiz Session（途中再開用）— typeでキー分離
  // ============================================

  static String _activeKey(String type) => 'active_quiz_session_v1__$type';

  /// 途中セッションを保存（例: type = 'normal' | 'mix' | 'review_test'）
  static Future<void> saveActive(QuizSession session) async {
    final prefs = await SharedPreferences.getInstance(); // ←これにする
    final ok = await prefs.setString(
      _activeKey(session.type),
      session.encode(),
    );
    if (!ok)
      throw Exception('Failed to persist active session (${session.type})');
    AppLog.d(
      '[SCORE_SAVER] active saved: type=${session.type}, deckId=${session.deckId}',
    );
  }

  /// 途中セッションの読込
  static Future<QuizSession?> loadActive(String type) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_activeKey(type));
    final s = QuizSession.decode(raw);
    AppLog.d('[SCORE_SAVER] active loaded: type=$type, exists=${s != null}');
    return s;
  }

  /// 途中セッションの削除
  static Future<void> clearActive(String type) async {
    final prefs = await SharedPreferences.getInstance();
  }
}
