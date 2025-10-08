import 'package:uuid/uuid.dart';
import 'models/score_record.dart';
import 'services/score_store.dart';
import 'utils/logger.dart';

Future<void> debugSmokeTestScoreStore() async {
  final rec = ScoreRecord(
    id: const Uuid().v4(),
    deckId: 'deck_demo',
    deckTitle: 'デモデッキ',
    score: 7,
    total: 10,
    durationSec: 111,
    timestamp: DateTime.now().millisecondsSinceEpoch,
    tags: {'喫煙': const ts.TagStat(correct: 2, wrong: 1)},
    selectedUnitIds: const ['u1', 'u2'],
  );
  await ScoreStore.instance.add(rec);
  final all = await ScoreStore.instance.listAll();
  // ignore: avoid_print
  AppLog.d('v2 count = ${all.length}, first = ${all.first.deckTitle}');
}
