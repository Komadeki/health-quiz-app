import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

final class ManifestFormatException implements Exception {
  const ManifestFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class NativePlatformManifest {
  const NativePlatformManifest(
      {required this.identifier, required this.displayName});

  final String identifier;
  final String displayName;
}

final class AppUrls {
  const AppUrls({
    required this.support,
    required this.privacy,
    required this.marketing,
  });

  final String support;
  final String privacy;
  final String? marketing;
}

final class QuestionBankManifest {
  const QuestionBankManifest({
    required this.format,
    required this.runtimePath,
    required this.manifestPath,
    required this.assetOutput,
  });

  final String format;
  final String runtimePath;
  final String manifestPath;
  final String? assetOutput;
}

final class DeckProductManifest {
  const DeckProductManifest({required this.deckId, required this.productId});

  final String deckId;
  final String productId;
}

final class ProductManifest {
  const ProductManifest({
    required this.decks,
    required this.bundle5ProductId,
    required this.bundleAllProductId,
    required this.proProductId,
    required this.fullUnlockProductId,
  });

  final List<DeckProductManifest> decks;
  final String? bundle5ProductId;
  final String? bundleAllProductId;
  final String? proProductId;
  final String? fullUnlockProductId;

  Iterable<String> get productIds sync* {
    yield* decks.map((product) => product.productId);
    for (final value in [
      bundle5ProductId,
      bundleAllProductId,
      proProductId,
      fullUnlockProductId,
    ]) {
      if (value != null && value.isNotEmpty) yield value;
    }
  }
}

final class MonetizationManifest {
  const MonetizationManifest(
      {required this.architecture, required this.products});

  final String architecture;
  final ProductManifest products;
}

final class ExamManifest {
  const ExamManifest({
    required this.profileVersion,
    required this.questionCount,
    required this.timeLimitMinutes,
    required this.overallPassPercent,
  });

  final String? profileVersion;
  final int? questionCount;
  final int? timeLimitMinutes;
  final int? overallPassPercent;
}

final class BrandingManifest {
  const BrandingManifest({required this.themeKey, required this.seedColor});

  final String themeKey;
  final String seedColor;
}

final class AppManifest {
  const AppManifest({
    required this.sourcePath,
    required this.appDirectory,
    required this.schemaVersion,
    required this.appKey,
    required this.displayName,
    required this.devDisplayName,
    required this.qaDisplayName,
    required this.publisher,
    required this.brandName,
    required this.legalese,
    required this.ios,
    required this.android,
    required this.urls,
    required this.questionIdentityPolicy,
    required this.questionBank,
    required this.monetization,
    required this.exam,
    required this.branding,
  });

  factory AppManifest.fromFile(File file, Directory repositoryRoot) {
    final Object? yaml;
    try {
      yaml = loadYaml(file.readAsStringSync());
    } on YamlException catch (error) {
      throw ManifestFormatException('Invalid YAML: ${error.message}');
    }
    if (yaml is! YamlMap) {
      throw const ManifestFormatException('app.yaml must contain a map.');
    }

    final map = _stringMap(yaml, 'app.yaml');
    final platforms = _requiredMap(map, 'platforms');
    final ios = _requiredMap(platforms, 'ios');
    final android = _requiredMap(platforms, 'android');
    final urls = _requiredMap(map, 'urls');
    final questionIdentity = _requiredMap(map, 'question_identity');
    final questionBank = _requiredMap(map, 'question_bank');
    final monetization = _requiredMap(map, 'monetization');
    final products = _requiredMap(monetization, 'products');
    final exam = _requiredMap(map, 'exam');
    final branding = _requiredMap(map, 'branding');

    _rejectUnknownKeys(
        map,
        const {
          'schema_version',
          'app_key',
          'display_name',
          'dev_display_name',
          'qa_display_name',
          'publisher',
          'brand_name',
          'legalese',
          'platforms',
          'urls',
          'question_identity',
          'question_bank',
          'monetization',
          'exam',
          'branding',
        },
        'app.yaml');
    _rejectUnknownKeys(platforms, const {'ios', 'android'}, 'platforms');
    _rejectUnknownKeys(
        ios, const {'bundle_id', 'display_name'}, 'platforms.ios');
    _rejectUnknownKeys(
      android,
      const {'application_id', 'display_name'},
      'platforms.android',
    );
    _rejectUnknownKeys(
      urls,
      const {'support', 'privacy', 'marketing'},
      'urls',
    );
    _rejectUnknownKeys(questionIdentity, const {'policy'}, 'question_identity');
    _rejectUnknownKeys(
      questionBank,
      const {'format', 'runtime_path', 'manifest_path', 'asset_output'},
      'question_bank',
    );
    _rejectUnknownKeys(
      monetization,
      const {'architecture', 'products'},
      'monetization',
    );
    _rejectUnknownKeys(
        products,
        const {
          'decks',
          'bundle5_product_id',
          'bundle_all_product_id',
          'pro_product_id',
          'full_unlock_product_id',
        },
        'monetization.products');
    _rejectUnknownKeys(
        exam,
        const {
          'profile_version',
          'question_count',
          'time_limit_minutes',
          'overall_pass_percent',
        },
        'exam');
    _rejectUnknownKeys(
      branding,
      const {'theme_key', 'seed_color'},
      'branding',
    );

    final deckProducts = <DeckProductManifest>[];
    final rawDecks = products['decks'];
    if (rawDecks != null) {
      if (rawDecks is! YamlList && rawDecks is! List<Object?>) {
        throw const ManifestFormatException('products.decks must be a list.');
      }
      for (final rawDeck in rawDecks as Iterable<Object?>) {
        if (rawDeck is! Map) {
          throw const ManifestFormatException(
              'Each deck product must be a map.');
        }
        final deck = _stringMap(rawDeck, 'products.decks');
        _rejectUnknownKeys(
          deck,
          const {'deck_id', 'product_id'},
          'products.decks',
        );
        deckProducts.add(
          DeckProductManifest(
            deckId: _requiredString(deck, 'deck_id'),
            productId: _requiredString(deck, 'product_id'),
          ),
        );
      }
    }

    final relativeSource = p.relative(file.path, from: repositoryRoot.path);
    final relativeAppDirectory = p.dirname(relativeSource);
    return AppManifest(
      sourcePath: relativeSource,
      appDirectory: relativeAppDirectory == '.' ? '.' : relativeAppDirectory,
      schemaVersion: _requiredInt(map, 'schema_version'),
      appKey: _requiredString(map, 'app_key'),
      displayName: _requiredString(map, 'display_name'),
      devDisplayName: _requiredString(map, 'dev_display_name'),
      qaDisplayName: _requiredString(map, 'qa_display_name'),
      publisher: _requiredString(map, 'publisher'),
      brandName: _requiredString(map, 'brand_name'),
      legalese: _requiredString(map, 'legalese'),
      ios: NativePlatformManifest(
        identifier: _requiredString(ios, 'bundle_id'),
        displayName: _requiredString(ios, 'display_name'),
      ),
      android: NativePlatformManifest(
        identifier: _requiredString(android, 'application_id'),
        displayName: _requiredString(android, 'display_name'),
      ),
      urls: AppUrls(
        support: _requiredString(urls, 'support'),
        privacy: _requiredString(urls, 'privacy'),
        marketing: _nullableString(urls, 'marketing'),
      ),
      questionIdentityPolicy: _requiredString(questionIdentity, 'policy'),
      questionBank: QuestionBankManifest(
        format: _requiredString(questionBank, 'format'),
        runtimePath: _requiredString(questionBank, 'runtime_path'),
        manifestPath: _requiredString(questionBank, 'manifest_path'),
        assetOutput: _nullableString(questionBank, 'asset_output'),
      ),
      monetization: MonetizationManifest(
        architecture: _requiredString(monetization, 'architecture'),
        products: ProductManifest(
          decks: List.unmodifiable(deckProducts),
          bundle5ProductId: _optionalString(products, 'bundle5_product_id'),
          bundleAllProductId:
              _optionalString(products, 'bundle_all_product_id'),
          proProductId: _optionalString(products, 'pro_product_id'),
          fullUnlockProductId: _optionalString(
            products,
            'full_unlock_product_id',
          ),
        ),
      ),
      exam: ExamManifest(
        profileVersion: _nullableString(exam, 'profile_version'),
        questionCount: _nullableInt(exam, 'question_count'),
        timeLimitMinutes: _nullableInt(exam, 'time_limit_minutes'),
        overallPassPercent: _nullableInt(exam, 'overall_pass_percent'),
      ),
      branding: BrandingManifest(
        themeKey: _requiredString(branding, 'theme_key'),
        seedColor: _requiredString(branding, 'seed_color'),
      ),
    );
  }

  final String sourcePath;
  final String appDirectory;
  final int schemaVersion;
  final String appKey;
  final String displayName;
  final String devDisplayName;
  final String qaDisplayName;
  final String publisher;
  final String brandName;
  final String legalese;
  final NativePlatformManifest ios;
  final NativePlatformManifest android;
  final AppUrls urls;
  final String questionIdentityPolicy;
  final QuestionBankManifest questionBank;
  final MonetizationManifest monetization;
  final ExamManifest exam;
  final BrandingManifest branding;

  String appPath(String relativePath) =>
      appDirectory == '.' ? relativePath : p.join(appDirectory, relativePath);
}

Map<String, Object?> _stringMap(Map<Object?, Object?> value, String field) {
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw ManifestFormatException('$field contains a non-string key.');
    }
    result[key] = entry.value;
  }
  return result;
}

Map<String, Object?> _requiredMap(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! Map) {
    throw ManifestFormatException('$key must be a map.');
  }
  return _stringMap(value, key);
}

String _requiredString(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw ManifestFormatException('$key must be a non-empty string.');
  }
  return value.trim();
}

String? _optionalString(Map<String, Object?> map, String key) {
  if (!map.containsKey(key)) return null;
  return _nullableString(map, key);
}

String? _nullableString(Map<String, Object?> map, String key) {
  if (!map.containsKey(key)) {
    throw ManifestFormatException('$key must be present (null is allowed).');
  }
  final value = map[key];
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty) {
    throw ManifestFormatException('$key must be a string or null.');
  }
  return value.trim();
}

int _requiredInt(Map<String, Object?> map, String key) {
  final value = map[key];
  if (value is! int) {
    throw ManifestFormatException('$key must be an integer.');
  }
  return value;
}

int? _nullableInt(Map<String, Object?> map, String key) {
  if (!map.containsKey(key)) {
    throw ManifestFormatException('$key must be present (null is allowed).');
  }
  final value = map[key];
  if (value == null) return null;
  if (value is! int) {
    throw ManifestFormatException('$key must be an integer or null.');
  }
  return value;
}

void _rejectUnknownKeys(
  Map<String, Object?> map,
  Set<String> allowed,
  String field,
) {
  final unknown = map.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw ManifestFormatException(
      '$field contains unsupported field(s): ${unknown.join(', ')}.',
    );
  }
}
