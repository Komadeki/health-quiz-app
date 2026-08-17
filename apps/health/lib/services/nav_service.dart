// lib/services/nav_service.dart
import 'package:flutter/material.dart';

/// グローバルにNavigatorへアクセスするためのサービス
class NavService {
  NavService._internal();
  static final I = NavService._internal();

  /// どの画面からでもナビゲーションできるようにするキー
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  /// 現在のcontextを取得（nullの場合もある）
  BuildContext? get ctx => navigatorKey.currentContext;
}
