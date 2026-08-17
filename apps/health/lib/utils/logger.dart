import 'package:flutter/foundation.dart';

/// アプリ内の開発ログ。既定はOFF。
class AppLog {
  static bool enabled = false; // ← 必要時に true に

  /// 汎用ログ（Object? を受け取り安全に toString）
  static void d(Object? message) {
    if (kDebugMode && enabled) {
      debugPrint(message?.toString());
    }
  }

  static void i(Object? message) => d(message); // infoエイリアス
  static void w(Object? message) => d('⚠️ $message'); // warn
  static void e(Object? message) => d('❌ $message'); // error
}
