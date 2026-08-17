// lib/models/attempt_entry.dart
import 'dart:convert';

/// 1問ごとの解答ログ
/// 重要: 復習用に stableId を保存します（今後はこれが集計キー）
class AttemptEntry {
  final String? attemptId; // 重複判定・インポート用（任意）
  final String sessionId; // 1回のクイズ実施単位ID（必須）
  final int questionNumber; // セッション内通し番号 (1-based 想定だが厳密には保存値を尊重)
  final String unitId; // 出題ユニットID

  final String cardId; // 教材側のカードID（任意のIDでもOK）
  final String question; // 問題文（保存時点のスナップショット）
  final int selectedIndex; // ユーザーの選択（1〜4など。旧データ0ベースも許容）
  final int correctIndex; // 正答（1〜4など。旧データ0ベースも許容）
  final bool isCorrect; // 正誤
  final int durationMs; // 問題に要した時間(ms)
  final DateTime timestamp; // 保存時刻

  /// 復習・集計用の安定キー（null可）
  /// JSONでは "stableId" を基本とし、互換として "cardStableId" / "card_stable_id" / "card_id" なども受け入れる。
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

  // ====== Robust parsers ======
  static int _asInt(dynamic v, {int defaultValue = 0}) {
    if (v == null) return defaultValue;
    if (v is int) return v;
    if (v is double) return v.round();
    if (v is bool) return v ? 1 : 0;
    if (v is String) {
      final t = v.trim();
      final n = int.tryParse(t);
      if (n != null) return n;
      // "12.0" など
      final d = double.tryParse(t);
      if (d != null) return d.round();
    }
    return defaultValue;
  }

  static bool _asBool(dynamic v, {bool defaultValue = false}) {
    if (v == null) return defaultValue;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final t = v.trim().toLowerCase();
      return t == 'true' || t == '1' || t == 'yes';
    }
    return defaultValue;
  }

  static String _asString(dynamic v, {String defaultValue = ''}) {
    if (v == null) return defaultValue;
    final s = v.toString().trim();
    return s.isEmpty ? defaultValue : s;
  }

  static DateTime _asDateTime(dynamic v) {
    if (v is DateTime) return v;
    if (v is String) {
      final t = DateTime.tryParse(v.trim());
      if (t != null) return t;
      // ISOでない文字列は現在時刻にフォールバック
      return DateTime.now();
    }
    if (v is num) {
      final n = v.toInt();
      final ms = (n > 2000000000) ? n : n * 1000; // 秒/ミリ秒の素朴判定
      return DateTime.fromMillisecondsSinceEpoch(ms);
    }
    return DateTime.now();
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
    'stableId': stableId,
  };

  factory AttemptEntry.fromMap(Map<String, dynamic> map) {
    // 互換: key名の揺れを吸収
    final unitId = _asString(map['unitId'] ?? map['unit_id'] ?? map['unitID']);
    final cardId = _asString(map['cardId'] ?? map['card_id'] ?? map['cardID']);
    final rawStable =
        (map['stableId'] ??
        map['cardStableId'] ??
        map['card_stable_id'] ??
        map['card_id']);
    final stableId = _asString(rawStable, defaultValue: '').trim();
    final qNoRaw = map['questionNumber'] ?? map['qNo'] ?? map['index'] ?? 1;
    final selRaw =
        map['selectedIndex'] ?? map['selected_index'] ?? map['answer'] ?? 0;
    final corRaw =
        map['correctIndex'] ?? map['correct_index'] ?? map['correct'] ?? 0;

    return AttemptEntry(
      attemptId: map['attemptId'] == null ? null : _asString(map['attemptId']),
      sessionId: _asString(map['sessionId']),
      questionNumber: _asInt(qNoRaw, defaultValue: 1),
      unitId: unitId,
      cardId: cardId,
      question: _asString(map['question']),
      selectedIndex: _asInt(selRaw),
      correctIndex: _asInt(corRaw),
      isCorrect: _asBool(map['isCorrect']),
      durationMs: _asInt(map['durationMs'] ?? map['duration_ms']),
      timestamp: _asDateTime(
        map['timestamp'] ?? map['answeredAt'] ?? map['createdAt'],
      ),
      stableId: stableId.isEmpty ? null : stableId,
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
