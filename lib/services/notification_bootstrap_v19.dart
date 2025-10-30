// lib/services/notification_bootstrap_v19.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Flutter Local Notifications v19 対応版
/// macOS / Android 両対応。UILocalNotificationDateInterpretation 等は削除済み。
class NotificationBootstrapV19 {
  NotificationBootstrapV19._internal();
  static final NotificationBootstrapV19 instance = NotificationBootstrapV19._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  /// Android通知チャンネル（共通設定）
  static const AndroidNotificationChannel _defaultChannel = AndroidNotificationChannel(
    'review_reminder_channel',
    '復習リマインダー',
    description: '復習・見直しの通知を行います',
    importance: Importance.high,
  );

  bool _initialized = false;

  FlutterLocalNotificationsPlugin get plugin => _plugin;

  /// 初期化処理
  Future<void> initialize({
    void Function(String? payload)? onTap, // ← payload だけ渡す
    bool requestAlertPermission = true,
    bool requestSoundPermission = true,
    bool requestBadgePermission = true,
  }) async {
    if (_initialized) return;

    // Timezone 初期化
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.local);

    // Android
    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS/macOS 共通
    final DarwinInitializationSettings darwinInit = DarwinInitializationSettings(
      requestAlertPermission: requestAlertPermission,
      requestBadgePermission: requestBadgePermission,
      requestSoundPermission: requestSoundPermission,
    );

    final InitializationSettings initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        onTap?.call(resp.payload); // ← payloadを渡す
      },
      onDidReceiveBackgroundNotificationResponse: (resp) {
        onTap?.call(resp.payload);
      },
    );

    // Android通知チャンネルの作成
    if (!kIsWeb && Platform.isAndroid) {
      final androidImpl =
          _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidImpl?.createNotificationChannel(_defaultChannel);
    }

    _initialized = true;
  }

  /// 即時通知
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _defaultChannel.id,
        _defaultChannel.name,
        channelDescription: _defaultChannel.description,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
    );
    await _plugin.show(id, title, body, details, payload: payload);
  }

  /// 指定日時に単発通知（ローカル時刻）
  /// 指定日時に単発通知（ローカル時刻）
  /// macOS/iOSの上書き対策：短時間に複数登録しても全件有効
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime whenLocal,
    String? payload,
    AndroidScheduleMode androidScheduleMode = AndroidScheduleMode.exactAllowWhileIdle,
  }) async {
    final tzTime = tz.TZDateTime.from(whenLocal, tz.local);

    // 🔹 チャンネルを個別化（上書き回避）
    final channelId = 'review_reminder_channel_$id';

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        '復習リマインダー #$id',
        channelDescription: '復習・見直しの通知を行います（id=$id）',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
    );

    // 🔹 各スケジュールを少し遅延登録（OSに負荷をかけない）
    await Future.delayed(Duration(milliseconds: 150 * (id % 5)));

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tzTime,
      details,
      androidScheduleMode: androidScheduleMode,
      matchDateTimeComponents: null,
      payload: payload,
    );

    if (kDebugMode) {
      debugPrint('[NOTI] scheduled #$id → ${tzTime.toLocal()}');
    }
  }

  /// 毎日同時刻に通知
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
    AndroidScheduleMode androidScheduleMode = AndroidScheduleMode.exactAllowWhileIdle,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _defaultChannel.id,
        _defaultChannel.name,
        channelDescription: _defaultChannel.description,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
      macOS: const DarwinNotificationDetails(),
    );

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      details,
      androidScheduleMode: androidScheduleMode,
      matchDateTimeComponents: DateTimeComponents.time, // 毎日
      payload: payload,
    );
  }

  /// キャンセル
  Future<void> cancel(int id) => _plugin.cancel(id);
  Future<void> cancelAll() => _plugin.cancelAll();
}

/// バックグラウンド通知タップ処理（必要に応じて実装）
@pragma('vm:entry-point')
void _onBackgroundTap(NotificationResponse response) {
  // TODO: 必要ならpayloadを使ってルーティングを行う
}
