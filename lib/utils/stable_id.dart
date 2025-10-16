// lib/utils/stable_id.dart
import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import '../models/card.dart';

String _norm(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// 出題前の「元の選択肢順」のカードから安定IDを作る（問題文＋選択肢）
/// ※ シャッフルした後のカードでは使わないこと！
String stableIdForOriginal(QuizCard c) {
  final q = _norm(c.question);
  final cs = c.choices.map(_norm).join('|');
  return crypto.md5.convert(utf8.encode('$q\n$cs')).toString();
}

/// 文字列から直接つくる版（必要なら）
String stableIdFromStrings(String question, List<String> choices) {
  final q = _norm(question);
  final cs = choices.map(_norm).join('|');
  return crypto.md5.convert(utf8.encode('$q\n$cs')).toString();
}
