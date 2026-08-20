import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:quiz_engine/quiz_engine.dart';

import '../generated/app_manifest.g.dart';

abstract interface class DroneBankLoader {
  Future<DroneProductionBank> load();
}

final class AssetDroneBankLoader implements DroneBankLoader {
  const AssetDroneBankLoader({required AssetBundle assetBundle})
      : _assetBundle = assetBundle;

  final AssetBundle _assetBundle;

  @override
  Future<DroneProductionBank> load() async {
    final path = GeneratedAppManifest.questionBankAssetPath;
    if (path == null) {
      throw StateError('Production question-bank asset is not configured.');
    }
    return DroneProductionBank.decode(await _assetBundle.loadString(path));
  }
}

final class DroneProductionBank {
  DroneProductionBank._({
    required this.appKey,
    required this.bankRevision,
    required this.examProfileVersion,
    required this.decks,
  })  : units = List.unmodifiable(decks.expand((deck) => deck.units)),
        cards = List.unmodifiable(decks.expand((deck) => deck.cards));

  factory DroneProductionBank.decode(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Question bank must be a JSON object.');
    }
    if (decoded['schemaVersion'] != 2) {
      throw const FormatException('Question bank schemaVersion must be 2.');
    }
    if (decoded['appKey'] != GeneratedAppManifest.appKey) {
      throw const FormatException(
          'Question bank appKey does not match app.yaml.');
    }
    if (decoded['examProfileVersion'] !=
        GeneratedAppManifest.examProfileVersion) {
      throw const FormatException(
        'Question bank examProfileVersion does not match app.yaml.',
      );
    }
    final bankRevision = decoded['bankRevision'];
    if (bankRevision is! String || bankRevision.trim().isEmpty) {
      throw const FormatException('Question bank bankRevision is required.');
    }
    final rawDecks = decoded['decks'];
    if (rawDecks is! List<dynamic>) {
      throw const FormatException('Question bank decks must be a list.');
    }
    final decks = rawDecks
        .map((deck) => Deck.fromJson(Map<String, dynamic>.from(deck as Map)))
        .toList(growable: false);
    final units = decks.expand((deck) => deck.units).toList(growable: false);
    const expectedUnits = {
      'drone_rules',
      'drone_systems',
      'drone_operations',
      'drone_risk_management',
    };
    if (units
            .map((unit) => unit.id)
            .toSet()
            .difference(expectedUnits)
            .isNotEmpty ||
        expectedUnits
            .difference(units.map((unit) => unit.id).toSet())
            .isNotEmpty ||
        units.length != expectedUnits.length) {
      throw const FormatException(
          'Question bank must contain the four production units.');
    }

    final cards = decks.expand((deck) => deck.cards).toList(growable: false);
    final stableIds = <String>{};
    for (final card in cards) {
      final stableId =
          GeneratedAppManifest.questionIdentityPolicy.stableIdFor(card);
      if (!stableIds.add(stableId)) {
        throw FormatException('Duplicate question stable ID: $stableId');
      }
    }
    if (cards.length != 100) {
      throw FormatException(
          'Question bank must contain 100 questions, found ${cards.length}.');
    }
    final freeCount = cards.where((card) => !card.isPremium).length;
    if (freeCount != 20) {
      throw FormatException(
          'Question bank must contain 20 free questions, found $freeCount.');
    }
    for (final unit in units) {
      if (unit.cards.where((card) => !card.isPremium).length != 5) {
        throw FormatException(
            '${unit.id} must contain exactly five free questions.');
      }
    }

    return DroneProductionBank._(
      appKey: decoded['appKey'] as String,
      bankRevision: bankRevision,
      examProfileVersion: decoded['examProfileVersion'] as String,
      decks: List.unmodifiable(decks),
    );
  }

  final String appKey;
  final String bankRevision;
  final String examProfileVersion;
  final List<Deck> decks;
  final List<Unit> units;
  final List<QuizCard> cards;

  Map<String, QuizCard> get cardsById => {
        for (final card in cards)
          GeneratedAppManifest.questionIdentityPolicy.stableIdFor(card): card,
      };

  Unit? unitById(String unitId) {
    for (final unit in units) {
      if (unit.id == unitId) return unit;
    }
    return null;
  }
}
