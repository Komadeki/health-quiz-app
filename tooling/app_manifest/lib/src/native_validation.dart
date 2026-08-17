import 'dart:io';

import 'package:path/path.dart' as p;

import 'manifest.dart';
import 'validation_result.dart';

void validateNativeWiring(
  Directory repositoryRoot,
  AppManifest manifest,
  ManifestValidationResult result,
) {
  final appRoot = Directory(
    p.join(repositoryRoot.path, manifest.appDirectory),
  );
  final infoPlist = File(p.join(appRoot.path, 'ios/Runner/Info.plist'));
  final project = File(
    p.join(appRoot.path, 'ios/Runner.xcodeproj/project.pbxproj'),
  );
  if (!infoPlist.existsSync() ||
      !infoPlist
          .readAsStringSync()
          .contains(r'<string>$(APP_DISPLAY_NAME)</string>')) {
    result.error(
      'ios_display_name_not_wired',
      'Info.plist must read APP_DISPLAY_NAME.',
      manifest.appPath('ios/Runner/Info.plist'),
    );
  }
  if (!project.existsSync() ||
      RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = "?\$\(APP_BUNDLE_ID\)"?;')
              .allMatches(project.readAsStringSync())
              .length <
          3) {
    result.error(
      'ios_bundle_id_not_wired',
      'All Runner build configurations must read APP_BUNDLE_ID.',
      manifest.appPath('ios/Runner.xcodeproj/project.pbxproj'),
    );
  }
  for (final configuration in ['Debug', 'Release']) {
    final xcconfig = File(
      p.join(appRoot.path, 'ios/Flutter/$configuration.xcconfig'),
    );
    if (!xcconfig.existsSync() ||
        !xcconfig.readAsStringSync().contains('AppManifest.xcconfig')) {
      result.error(
        'ios_manifest_xcconfig_not_included',
        '$configuration.xcconfig must include AppManifest.xcconfig.',
        manifest.appPath('ios/Flutter/$configuration.xcconfig'),
      );
    }
  }

  final gradle = File(p.join(appRoot.path, 'android/app/build.gradle.kts'));
  final gradleSource = gradle.existsSync() ? gradle.readAsStringSync() : '';
  if (!gradleSource.contains('app-manifest.properties') ||
      !gradleSource.contains('APP_APPLICATION_ID') ||
      !gradleSource.contains('applicationId = manifestApplicationId')) {
    result.error(
      'android_application_id_not_wired',
      'Android Gradle must read generated APP_APPLICATION_ID.',
      manifest.appPath('android/app/build.gradle.kts'),
    );
  }
  final androidManifest = File(
    p.join(appRoot.path, 'android/app/src/main/AndroidManifest.xml'),
  );
  if (!androidManifest.existsSync() ||
      !androidManifest
          .readAsStringSync()
          .contains('android:label="@string/app_name"')) {
    result.error(
      'android_display_name_not_wired',
      'AndroidManifest.xml must use @string/app_name.',
      manifest.appPath('android/app/src/main/AndroidManifest.xml'),
    );
  }

  for (final entry in {
    'prod': manifest.android.displayName,
    'dev': manifest.devDisplayName,
    'qa': manifest.qaDisplayName,
  }.entries) {
    final stringsPath = 'android/app/src/${entry.key}/res/values/strings.xml';
    final strings = File(p.join(appRoot.path, stringsPath));
    if (strings.existsSync() &&
        !strings.readAsStringSync().contains(
              '<string name="app_name">${entry.value}</string>',
            )) {
      result.error(
        'android_${entry.key}_display_name_mismatch',
        'The ${entry.key} app_name must match its app manifest display name.',
        manifest.appPath(stringsPath),
      );
    }
  }
}
