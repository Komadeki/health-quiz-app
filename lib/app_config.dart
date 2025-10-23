// lib/app_config.dart
enum AppEnv { dev, qa, prod }

class AppConfig {
  static const _envStr = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
  static const env = _envStr == 'prod'
      ? AppEnv.prod
      : _envStr == 'qa'
      ? AppEnv.qa
      : AppEnv.dev;

  // デバッグUI（購入切替ボタンなど）を出すか
  static bool get purchaseDebug => env == AppEnv.dev;

  // ログの詳細度
  static bool get verboseLog => env != AppEnv.prod;

  // 課金のソフトゲート挙動例（devは何でも解放OK 等）
  static bool get allowSoftGateOverride => env == AppEnv.dev;

  // 🔰 追加: 表示用アプリタイトル（AppBarなどで利用）
  static String get appTitle {
    switch (env) {
      case AppEnv.dev:
        return '健康クイズ（DEV）';
      case AppEnv.qa:
        return '健康クイズ（QA）';
      case AppEnv.prod:
      default:
        return '高校保健一問一答';
    }
  }
}
