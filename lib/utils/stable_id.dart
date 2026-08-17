// lib/utils/stable_id.dart
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../models/card.dart';
import '../quiz_app_definition.dart';

String _norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

String _legacyContentHash(QuizCard c) {
  final q = _norm(c.question);
  final cs = c.choices.map(_norm).join('|');
  return crypto.md5.convert(utf8.encode('$q\n$cs')).toString();
}

/// 出題前の「元の選択肢順」のカードから安定IDを返す。
///
/// 現行の高校保健は preferExplicitStableIds=false のため従来ハッシュを維持し、
/// 保存済み履歴・途中セッションとの互換性を壊さない。
/// 新規資格アプリでは true にして、JSON/CSVの永久IDを優先する。
String stableIdForOriginal(QuizCard c) {
  if (currentQuizApp.preferExplicitStableIds) {
    final explicit = c.stableId?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
  }
  return _legacyContentHash(c);
}

/// 旧方式の内容ハッシュ。互換確認・移行用途で利用する。
String legacyStableIdForOriginal(QuizCard c) => _legacyContentHash(c);

String stableIdFromStrings(String question, List<String> choices) {
  final q = _norm(question);
  final cs = choices.map(_norm).join('|');
  return crypto.md5.convert(utf8.encode('$q\n$cs')).toString();
}
