import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:quiz_engine/quiz_engine.dart';

import 'generated/app_manifest.g.dart';

final class FixtureBank {
  FixtureBank({
    required this.appKey,
    required this.bankRevision,
    required this.examProfileVersion,
    required this.decks,
  });

  factory FixtureBank.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Fixture bank must be a JSON object.');
    }
    if (decoded['schemaVersion'] != 2) {
      throw const FormatException('Fixture bank schemaVersion must be 2.');
    }
    if (decoded['appKey'] != GeneratedAppManifest.appKey) {
      throw const FormatException(
          'Fixture bank appKey does not match app.yaml.');
    }
    if (decoded['examProfileVersion'] !=
        GeneratedAppManifest.examProfileVersion) {
      throw const FormatException(
        'Fixture bank examProfileVersion does not match app.yaml.',
      );
    }

    final rawDecks = decoded['decks'];
    if (rawDecks is! List<dynamic>) {
      throw const FormatException('Fixture bank decks must be a list.');
    }
    final decks = rawDecks
        .map(
          (deck) => Deck.fromJson(Map<String, dynamic>.from(deck as Map)),
        )
        .toList(growable: false);
    for (final card in decks.expand((deck) => deck.cards)) {
      GeneratedAppManifest.questionIdentityPolicy.stableIdFor(card);
    }

    return FixtureBank(
      appKey: decoded['appKey'] as String,
      bankRevision: decoded['bankRevision'] as String,
      examProfileVersion: decoded['examProfileVersion'] as String,
      decks: decks,
    );
  }

  final String appKey;
  final String bankRevision;
  final String examProfileVersion;
  final List<Deck> decks;

  List<QuizCard> get cards =>
      decks.expand((deck) => deck.cards).toList(growable: false);
}

final class FixtureBankLoader {
  const FixtureBankLoader({required AssetBundle assetBundle})
      : _assetBundle = assetBundle;

  final AssetBundle _assetBundle;

  Future<FixtureBank> load() async {
    final assetPath = GeneratedAppManifest.questionBankAssetPath;
    if (assetPath == null) {
      throw StateError('Fixture app requires a generated question-bank asset.');
    }
    return FixtureBank.decode(await _assetBundle.loadString(assetPath));
  }
}
