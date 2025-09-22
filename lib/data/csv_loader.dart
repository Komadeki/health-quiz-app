import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import '../models/card.dart';
import '../models/deck.dart';

Future<Deck> loadDeckFromCsv(String assetPath, String title) async {
  final text = await rootBundle.loadString(assetPath);

  final rows = const CsvToListConverter(
    eol: '\n',
    shouldParseNumbers: false, // 文字列として扱う
  ).convert(text);

  if (rows.isEmpty) {
    throw Exception('CSVに行がありません: $assetPath');
  }

  // 1行目はヘッダー想定
  final header = rows.first.map((e) => e.toString().trim().toLowerCase()).toList();
  final indexOf = <String, int>{};
  for (var i = 0; i < header.length; i++) {
    indexOf[header[i]] = i;
  }

  // 必須ヘッダー確認
  const required = ['question', 'choice1', 'choice2', 'choice3', 'choice4', 'answer_index'];
  for (final k in required) {
    if (!indexOf.containsKey(k)) {
      throw Exception('CSVに必須カラム "$k" がありません');
    }
  }

  final cards = <QuizCard>[];
  for (var i = 1; i < rows.length; i++) {
    final row = rows[i];
    // 空行ガード
    if (row.isEmpty ||
        row.every((v) => v == null || v.toString().trim().isEmpty)) continue;

    try {
      cards.add(QuizCard.fromRowWithHeader(indexOf, row));
    } catch (e) {
      // 1行だけ壊れていても他は読む
      // 必要なら print('Row $i error: $e');
    }
  }

  if (cards.isEmpty) {
    throw Exception('問題が1件も読み込めませんでした（フォーマット要確認）');
  }

  return Deck(title: title, cards: cards);
}
