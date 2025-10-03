import 'package:shared_preferences/shared_preferences.dart';
import '../models/score_record.dart';

class ScoreStore {
  static const String _kKeyV2 = 'scores.v2';
  static const String _kKeyV1 = 'scores.v1'; // 旧の互換読み取り用（必要に応じて変更）

  ScoreStore._();
  static final ScoreStore instance = ScoreStore._();

  /// 先頭に追加（新しい順）
  Future<void> add(ScoreRecord rec) async {
    final prefs = await SharedPreferences.getInstance();
    final list = await listAll();
    final updated = [rec, ...list];
    await prefs.setString(_kKeyV2, ScoreRecord.encodeList(updated));
  }

  /// v2（あれば）→ なければ v1 を後方互換で読み、新しい順で返す
  Future<List<ScoreRecord>> listAll() async {
    final prefs = await SharedPreferences.getInstance();
    final rawV2 = prefs.getString(_kKeyV2);
    if (rawV2 != null && rawV2.isNotEmpty) {
      final list = ScoreRecord.decodeList(rawV2);
      list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return list;
    }

    // v1 互換読み（旧の保存形式が JSON配列 / QuizResult 互換だと仮定）
    final rawV1 = prefs.getString(_kKeyV1);
    if (rawV1 != null && rawV1.isNotEmpty) {
      try {
        final list = ScoreRecord.decodeList(rawV1)
            .map(
              (e) => ScoreRecord(
                id: e.id,
                deckId: e.deckId,
                deckTitle: e.deckTitle,
                score: e.score,
                total: e.total,
                durationSec: e.durationSec,
                timestamp: e.timestamp,
                tags: null,
                selectedUnitIds: e.selectedUnitIds,
              ),
            )
            .toList();
        list.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return list;
      } catch (_) {
        // 旧形式が全く別構造だった場合は安全側で空配列に
        return <ScoreRecord>[];
      }
    }

    return <ScoreRecord>[];
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kKeyV2);
    await prefs.remove(_kKeyV1);
  }
}
