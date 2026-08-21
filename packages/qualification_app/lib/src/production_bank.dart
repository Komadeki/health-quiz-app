import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:quiz_engine/quiz_engine.dart';

abstract interface class QualificationBankLoader {
  Future<QualificationBank> load();
}

final class AssetQualificationBankLoader implements QualificationBankLoader {
  const AssetQualificationBankLoader({
    required this.definition,
    required AssetBundle assetBundle,
  }) : _assetBundle = assetBundle;

  final QualificationAppDefinition definition;
  final AssetBundle _assetBundle;

  @override
  Future<QualificationBank> load() async {
    return QualificationBank.decode(
      await _assetBundle.loadString(definition.questionBankAsset),
      definition,
    );
  }
}

final class QualificationBank {
  QualificationBank._({
    required this.appKey,
    required this.bankRevision,
    required this.examProfileVersion,
    required this.decks,
    required QuestionIdentityPolicy identityPolicy,
  })  : units = List.unmodifiable(decks.expand((deck) => deck.units)),
        cards = List.unmodifiable(decks.expand((deck) => deck.cards)),
        _identityPolicy = identityPolicy {
    cardsById = Map.unmodifiable({
      for (final card in cards) identityPolicy.stableIdFor(card): card,
    });
    deckIdByQuestionId = Map.unmodifiable({
      for (final deck in decks)
        for (final card in deck.cards)
          identityPolicy.stableIdFor(card): deck.id,
    });
  }

  factory QualificationBank.decode(
    String source,
    QualificationAppDefinition definition,
  ) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Question bank must be a JSON object.');
    }
    if (decoded['schemaVersion'] != 2) {
      throw const FormatException('Question bank schemaVersion must be 2.');
    }
    if (decoded['appKey'] != definition.appKey) {
      throw const FormatException(
        'Question bank appKey does not match app.yaml.',
      );
    }
    if (decoded['examProfileVersion'] !=
        definition.examProfile?.profileVersion) {
      throw const FormatException(
        'Question bank examProfileVersion does not match app.yaml.',
      );
    }
    final bankRevision = decoded['bankRevision'];
    final rawDecks = decoded['decks'];
    if (bankRevision is! String || bankRevision.trim().isEmpty) {
      throw const FormatException('Question bank bankRevision is required.');
    }
    if (rawDecks is! List) {
      throw const FormatException('Question bank decks must be a list.');
    }
    final decks = rawDecks
        .map((deck) => Deck.fromJson(Map<String, dynamic>.from(deck as Map)))
        .toList(growable: false);
    if (decks.isEmpty || decks.expand((deck) => deck.cards).isEmpty) {
      throw const FormatException('Question bank must not be empty.');
    }
    final stableIds = <String>{};
    for (final card in decks.expand((deck) => deck.cards)) {
      final id = definition.questionIdentityPolicy.stableIdFor(card);
      if (!stableIds.add(id)) {
        throw FormatException('Duplicate permanent question ID: $id');
      }
      if ((card.questionVersion ?? 0) < 1) {
        throw FormatException('Question $id must have a positive version.');
      }
    }
    return QualificationBank._(
      appKey: decoded['appKey'] as String,
      bankRevision: bankRevision,
      examProfileVersion: decoded['examProfileVersion'] as String?,
      decks: List.unmodifiable(decks),
      identityPolicy: definition.questionIdentityPolicy,
    );
  }

  final String appKey;
  final String bankRevision;
  final String? examProfileVersion;
  final List<Deck> decks;
  final List<Unit> units;
  final List<QuizCard> cards;
  final QuestionIdentityPolicy _identityPolicy;
  late final Map<String, QuizCard> cardsById;
  late final Map<String, String> deckIdByQuestionId;

  String stableId(QuizCard card) => _identityPolicy.stableIdFor(card);

  Unit? unitById(String unitId) {
    for (final unit in units) {
      if (unit.id == unitId) return unit;
    }
    return null;
  }

  List<QuestionCandidate> get candidates => List.unmodifiable([
        for (final card in cards)
          QuestionCandidate(
            questionId: stableId(card),
            unitId: card.unitId ?? '',
            isPremium: card.isPremium,
          ),
      ]);
}
