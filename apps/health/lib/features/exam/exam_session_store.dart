import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/score_saver.dart';
import 'exam_session.dart';

class ExamSessionStore {
  static const activeKey = 'health_term_exam_active_v1';
  static String sessionKey(String id) => 'health_term_exam_session_v1__$id';
  static Future<void>? _pending;

  /// Serialize checkpoints so quick typing/navigation cannot revert an answer.
  Future<void> save(ExamSession session) {
    final operation = (_pending ?? Future<void>.value()).then((_) async {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(session.toJson());
      if (!await prefs.setString(sessionKey(session.id), raw)) {
        throw StateError('Failed to save exam responses');
      }
      if (!await prefs.setString(activeKey, session.id)) {
        throw StateError('Failed to save active exam');
      }
    });
    final barrier = operation.then<void>((_) {}, onError: (Object _) {});
    _pending = barrier;
    barrier.whenComplete(() {
      if (identical(_pending, barrier)) _pending = null;
    });
    return operation;
  }

  Future<ExamSession?> load(String id) async {
    final pending = _pending;
    if (pending != null) await pending;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(sessionKey(id));
    if (raw == null) return null;
    final session =
        ExamSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    if (session.id != id) throw const FormatException('Exam identity mismatch');
    return session;
  }

  Future<ExamSession?> loadActive() async {
    final pending = _pending;
    if (pending != null) await pending;
    final prefs = await SharedPreferences.getInstance();
    final id = prefs.getString(activeKey);
    if (id == null) return null;
    final session = await load(id);
    if (session == null) throw const FormatException('Missing active exam');
    return session;
  }

  Future<void> clearActive(String expectedId) async {
    final pending = _pending;
    if (pending != null) await pending;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(activeKey) != expectedId) return;
    if (!await prefs.remove(activeKey)) {
      throw StateError('Failed to clear active exam');
    }
  }

  /// Preserve unreadable progress before allowing a new test.
  Future<void> archiveUnreadableActive() async {
    final pending = _pending;
    if (pending != null) await pending;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.get(activeKey);
    if (raw == null) return;
    final backup = jsonEncode({
      'active': raw,
      'snapshot': raw is String ? prefs.get(sessionKey(raw)) : null
    });
    final key =
        'health_term_exam_recovery_v1__${DateTime.now().microsecondsSinceEpoch}';
    if (!await prefs.setString(key, backup)) {
      throw StateError('Failed to preserve unreadable progress');
    }
    if (!await prefs.remove(activeKey)) {
      throw StateError('Failed to reset active exam');
    }
  }

  Future<void> deleteResult(String id) async {
    final session = await load(id);
    final prefs = await SharedPreferences.getInstance();
    if (session == null ||
        !session.submitted ||
        prefs.getString(activeKey) == id) {
      return;
    }
    if (!await prefs.remove(sessionKey(id))) {
      throw StateError('Failed to remove exam result');
    }
  }

  /// The submitted snapshot remains recoverable if score persistence fails.
  /// Retrying uses the same score ID and never creates another result.
  Future<void> finish(ExamSession session) async {
    if (!session.submitted) {
      throw StateError('Cannot save an unsubmitted result');
    }
    await save(session);
    await ScoreSaver.save(session.toScoreRecord());
    await clearActive(session.id);
  }
}
