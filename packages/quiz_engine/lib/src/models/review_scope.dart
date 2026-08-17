// lib/models/review_scope.dart
class ScoreScope {
  final DateTime? from; // 含む
  final DateTime? to; // 含まない（null=now）
  final Set<String>? sessionTypes; // {'unit','mixed','review_test'} など
  final Set<String>? deckIds; // 絞り込み任意
  final Set<String>? unitIds; // 絞り込み任意
  final bool? onlyFinishedSessions; // trueなら完了セッションのみ
  final bool? onlyLatestAttemptsPerCard; // trueならstableIdごと最新1件だけ見る
  final bool? excludeWhenCorrectedLater; // 直近が正解のカードは誤答対象から除外

  const ScoreScope({
    this.from,
    this.to,
    this.sessionTypes,
    this.deckIds,
    this.unitIds,
    this.onlyFinishedSessions,
    this.onlyLatestAttemptsPerCard,
    this.excludeWhenCorrectedLater,
  });

  @override
  String toString() =>
      'ScoreScope('
      'from=$from,to=$to,types=$sessionTypes,deckIds=$deckIds,unitIds=$unitIds,'
      'onlyFinished=$onlyFinishedSessions,latestOnly=$onlyLatestAttemptsPerCard,'
      'excludeCorrected=$excludeWhenCorrectedLater)';
}

class WrongFreqMeta {
  final int totalAttempts; // 集計の母数（base件数）
  final int totalWrongAttempts; // 誤答の総数
  final int uniqueCards; // 誤答をもつstableId数
  final DateTime? oldest;
  final DateTime? newest;

  const WrongFreqMeta({
    required this.totalAttempts,
    required this.totalWrongAttempts,
    required this.uniqueCards,
    this.oldest,
    this.newest,
  });
}

class WrongFrequencyPayload {
  /// key: stableId, value: wrongCount
  final Map<String, int> freq;
  final WrongFreqMeta meta;

  const WrongFrequencyPayload({required this.freq, required this.meta});
}
