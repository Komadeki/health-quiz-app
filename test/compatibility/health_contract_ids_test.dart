import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_quiz_app/quiz_app_definition.dart';
import 'package:health_quiz_app/services/iap_service.dart';

void main() {
  final fixture = jsonDecode(
    File('test/fixtures/health_contract_ids.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final expectedDeckIds = List<String>.from(fixture['deckIds'] as List);
  final expectedProductIds = List<String>.from(fixture['productIds'] as List);

  test('published deck IDs and product IDs remain unchanged', () {
    expect(ProductCatalog.deckIds, expectedDeckIds);
    expect(ProductCatalog.allProductIds(), unorderedEquals(expectedProductIds));
    expect(currentQuizApp.deckIds, expectedDeckIds);
    expect(currentQuizApp.productIds, unorderedEquals(expectedProductIds));
    expect(
      currentQuizApp.purchaseArchitecture,
      PurchaseArchitecture.legacyDeckBundles,
    );
    expect(currentQuizApp.fullUnlockProductId, isEmpty);
  });

  test('purchase UI still references every published product ID', () {
    final files = List<String>.from(
      fixture['productIdConsumerFiles'] as List,
    );

    for (final path in files) {
      final source = File(path).readAsStringSync();
      for (final productId in expectedProductIds) {
        expect(source, contains(productId), reason: '$path: $productId');
      }
    }
  });

  test('published SharedPreferences key literals remain unchanged', () {
    final contracts = Map<String, dynamic>.from(
      fixture['storageLiteralsByFile'] as Map,
    );

    for (final entry in contracts.entries) {
      final source = File(entry.key).readAsStringSync();
      final literals = List<String>.from(entry.value as List);
      for (final literal in literals) {
        final singleQuoted = source.contains("'$literal'");
        final doubleQuoted = source.contains('"$literal"');
        expect(
          singleQuoted || doubleQuoted,
          isTrue,
          reason: '${entry.key}: $literal',
        );
      }
    }
  });
}
