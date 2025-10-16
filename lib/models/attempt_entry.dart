// lib/models/attempt_entry.dart
import 'dart:convert';

/// 1問ごとの解答ログ
/// 重要: 復習用に stableId を保存します（今後はこれが集計キー）
class AttemptEntry {
  final String? attemptId;      // 重複判定・インポート用（任意）
  final String sessionId;       // 1回のクイズ実施単位のID
  final int questionNumber;     // そのセッション内での通し番号 (1-based)
  final String unitId;          // 出題ユニットID

  final String cardId;          // 教材側のカードID（任意のIDでもOK）
  final String question;        // 問題文（保存時点のスナップショット）
  final int selectedIndex;      // ユーザーの選択（1〜4など）
  final int correctIndex;       // 正答（1〜4など）
  final bool isCorrect;         // 正誤
  final int durationMs;         // 問題に要した時間(ms)
  final DateTime timestamp;     // 保存時刻（ISOで保存）

  /// ★追加: 復習・集計用の安定キー（必須ではないが今後はこれを使う）
  /// JSONでは "stableId" が基本。互換として "cardStableId" や "card_id" なども受け入れる。
  final String? stableId;

  const AttemptEntry({
    this.attemptId,
    required this.sessionId,
    required this.questionNumber,
    required this.unitId,
    required this.cardId,
    required this.question,
    required this.selectedIndex,
    required this.correctIndex,
    required this.isCorrect,
    required this.durationMs,
    required this.timestamp,
    this.stableId,
  });

  AttemptEntry copyWith({
    String? attemptId,
    String? sessionId,
    int? questionNumber,
    String? unitId,
    String? cardId,
    String? question,
    int? selectedIndex,
    int? correctIndex,
    bool? isCorrect,
    int? durationMs,
    DateTime? timestamp,
    String? stableId,
  }) {
    return AttemptEntry(
      attemptId: attemptId ?? this.attemptId,
      sessionId: sessionId ?? this.sessionId,
      questionNumber: questionNumber ?? this.questionNumber,
      unitId: unitId ?? this.unitId,
      cardId: cardId ?? this.cardId,
      question: question ?? this.question,
      selectedIndex: selectedIndex ?? this.selectedIndex,
      correctIndex: correctIndex ?? this.correctIndex,
      isCorrect: isCorrect ?? this.isCorrect,
      durationMs: durationMs ?? this.durationMs,
      timestamp: timestamp ?? this.timestamp,
      stableId: stableId ?? this.stableId,
    );
  }

  Map<String, dynamic> toMap() => {
        'attemptId': attemptId,
        'sessionId': sessionId,
        'questionNumber': questionNumber,
        'unitId': unitId,
        'cardId': cardId,
        'question': question,
        'selectedIndex': selectedIndex,
        'correctIndex': correctIndex,
        'isCorrect': isCorrect,
        'durationMs': durationMs,
        'timestamp': timestamp.toIso8601String(),
        // ★必ず含める（null可）
        'stableId': stableId,
      };

  factory AttemptEntry.fromMap(Map<String, dynamic> map) {
    // ---- timestamp は ISO文字列 or epoch(int/num[秒/ミリ秒]) を許容 ----
    DateTime _parseTs(dynamic v) {
      if (v is DateTime) return v;
      if (v is String) {
        final dt = DateTime.tryParse(v);
        if (dt != null) return dt;
      } else if (v is num) {
        // 10桁(秒) or 13桁(ミリ秒) に広めに対応
        final isMs = v > 2000000000; // ~2033年あたりを境に判定
        final ms = isMs ? v.toInt() : (v.toInt() * 1000);
        return DateTime.fromMillisecondsSinceEpoch(ms);
      }
      // フォールバック：現在時刻（壊れ値回避）
      return DateTime.now();
    }

    // ---- 後方互換: 各種キー名の取りこぼしを防ぐ ----
    int _asInt(dynamic x) => (x as num).toInt();
    String _asString(dynamic x) => (x ?? '').toString();

    final String unitId =
        (map['unitId'] ?? map['unit_id'] ?? map['unitID'] ?? '').toString();
    final String cardId =
        (map['cardId'] ?? map['card_id'] ?? map['cardID'] ?? '').toString();

    final String? stableId =
        (map['stableId'] as String?) ??
        (map['cardStableId'] as String?) ??
        (map['card_stable_id'] as String?) ??
        (map['card_id'] as String?); // 古いキー想定

    final dynamic qNoRaw =
        map['questionNumber'] ?? map['qNo'] ?? map['index'] ?? 1;

    final dynamic selRaw =
        map['selectedIndex'] ?? map['selected_index'] ?? map['answer'] ?? 0;
    final dynamic corRaw =
        map['correctIndex'] ?? map['correct_index'] ?? map['correct'] ?? 0;

    return AttemptEntry(
      attemptId: map['attemptId'] as String?,
      sessionId: _asString(map['sessionId']),
      questionNumber: _asInt(qNoRaw),
      unitId: unitId,
      cardId: cardId,
      question: _asString(map['question']),
      selectedIndex: _asInt(selRaw),
      correctIndex: _asInt(corRaw),
      isCorrect: map['isCorrect'] as bool? ?? false,
      durationMs: _asInt(map['durationMs'] ?? map['duration_ms'] ?? 0),
      timestamp: _parseTs(map['timestamp'] ?? map['answeredAt'] ?? map['createdAt']),
      stableId: (stableId != null && stableId.trim().isNotEmpty) ? stableId.trim() : null,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory AttemptEntry.fromJson(String source) =>
      AttemptEntry.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  String toString() =>
      'AttemptEntry(sessionId=$sessionId, q=$questionNumber, correct=$isCorrect, stableId=$stableId)';
}

/// ===== 復習向け 互換プロパティ拡張 =====
/// 既存データ/旧モデルからの読み取りに使う“緩い”ゲッター群
extension AttemptEntryCompat on AttemptEntry {
  /// セッション種別（unit / mixed / review_test など）
  String? get sessionType {
    try {
      return (this as dynamic).type ??
          (this as dynamic).sessionType ??
          (this as dynamic).session?.type;
    } catch (_) {
      return null;
    }
  }

  /// 旧スキーマ由来の作成時刻
  DateTime? get createdAt {
    try {
      final v = (this as dynamic).createdAt;
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    } catch (_) {}
    return null;
  }

  /// 旧スキーマ由来の回答時刻
  DateTime? get answeredAt {
    try {
      final v = (this as dynamic).answeredAt;
      if (v is DateTime) return v;
      if (v is String) return DateTime.tryParse(v);
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    } catch (_) {}
    return null;
  }
}
