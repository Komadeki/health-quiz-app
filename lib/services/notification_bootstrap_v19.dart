// lib/services/notification_bootstrap_v19.dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter/services.dart';

/// Flutter Local Notifications v19 対応版（安定化済み）
/// - Android/iOS/macOS共通
/// - 背景タップ/初期化失敗対策を追加
class NotificationBootstrapV19 {
  NotificationBootstrapV19._internal();
  static final NotificationBootstrapV19 instance = NotificationBootstrapV19._internal();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

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
    void Function(String? payload)? onTap,
    bool requestAlertPermission = true,
    bool requestSoundPermission = true,
    bool requestBadgePermission = true,
  }) async {
    if (_initialized) return;

    try {
      // 🔹 TimeZone 初期化
      tz.initializeTimeZones();
      tz.setLocalLocation(tz.local);

      // 🔹 Android / iOS 初期設定
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      final darwinInit = DarwinInitializationSettings(
        requestAlertPermission: requestAlertPermission,
        requestBadgePermission: requestBadgePermission,
        requestSoundPermission: requestSoundPermission,
      );
      final initSettings = InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
        macOS: darwinInit,
      );

      await _plugin.initialize(
        initSettings,
        // フォアグラウンドタップ
        onDidReceiveNotificationResponse: (resp) {
          onTap?.call(resp.payload);
        },
        // バックグラウンド/終了時タップ
        onDidReceiveBackgroundNotificationResponse: _onBackgroundTap,
      );

      // Android通知チャンネル作成
      if (!kIsWeb && Platform.isAndroid) {
        final androidImpl =
            _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await androidImpl?.createNotificationChannel(_defaultChannel);

        // 🔸 Android 13+ の通知パーミッション
        // v19 では requestNotificationsPermission() に名称変更
        final enabled = await androidImpl?.areNotificationsEnabled() ?? true;
        if (!enabled) {
          await androidImpl?.requestNotificationsPermission();
        }
      }

      _initialized = true;
      debugPrint('[NOTI] initialized successfully');
    } catch (e, st) {
      debugPrint('[NOTI] initialization failed: $e\n$st');
      _initialized = true; // 起動阻害を避けるためtrue扱い
    }
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

  /// 指定日時に単発通知
  /// 指定日時に単発通知（ローカル時刻）
  /// exact が許可されていない端末では inexact にフォールバック
  Future<void> scheduleOnce({
    required int id,
    required String title,
    required String body,
    required DateTime whenLocal,
    String? payload,
    AndroidScheduleMode androidScheduleMode = AndroidScheduleMode.exactAllowWhileIdle,
  }) async {
    final tzTime = tz.TZDateTime.from(whenLocal, tz.local);

    // 🔹 上書き回避のため id ごとにチャンネル分離
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

    // 🔹 短い遅延で連続登録時の負荷を軽減
    await Future.delayed(Duration(milliseconds: 150 * (id % 5)));

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzTime,
        details,
        androidScheduleMode: androidScheduleMode, // exactAllowWhileIdle / inexact フォールバック可
        // uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,  // ← 削除
        matchDateTimeComponents: null,
        payload: payload,
      );
    } on PlatformException catch (e) {
      if (e.code == 'exact_alarms_not_permitted') {
        // ✅ フォールバック（近似アラーム）
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          tzTime,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: null,
          payload: payload,
        );
        if (kDebugMode) {
          debugPrint('[NOTI] fallback→inexactAllowWhileIdle (once) id=$id');
        }
      } else {
        rethrow;
      }
    }

    if (kDebugMode) {
      debugPrint('[NOTI] scheduled #$id → ${tzTime.toLocal()}');
    }
  }

  /// 毎日同時刻通知（Exact単発の連鎖：Doze/OEM対策）
  /// 呼び出し元はそのままでOK。内部で N 日分を単発 Exact で先取り予約します。
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    String? payload,
    AndroidScheduleMode androidScheduleMode =
        AndroidScheduleMode.exactAllowWhileIdle, // 互換のため残すが未使用
    int daysAhead = 7, // 先取り予約する日数。必要に応じて14などに増やせます
  }) async {
    // “繰り返し（matchDateTimeComponents）”は使わず、単発Exactを連続で入れる
    final now = DateTime.now();

    DateTime dayAt(int addDays) =>
        DateTime(now.year, now.month, now.day, hour, minute).add(Duration(days: addDays));

    // 直近の次回（今日のその時刻が過ぎていたら翌日）
    var first = dayAt(0);
    if (!first.isAfter(now)) first = dayAt(1);

    for (int i = 0; i < daysAhead; i++) {
      final when = first.add(Duration(days: i));

      // 既存の単発APIを利用（内部で tz 変換＆ exactAllowWhileIdle を使う実装）
      await scheduleOnce(
        id: id + i, // 連番で衝突回避（例：1002,1003,...）
        title: title,
        body: body,
        whenLocal: when, // ローカルDateTimeを渡す
        payload: payload,
      );

      // logcat で確認しやすいログ
      // ignore: avoid_print
      print('[NOTI19] scheduleDaily as exact: id=${id + i} at=$when');
    }
  }

  /// キャンセル
  Future<void> cancel(int id) => _plugin.cancel(id);
  Future<void> cancelAll() => _plugin.cancelAll();
}

/// 🔹 バックグラウンド通知タップ時のハンドラ（Null防止用）
@pragma('vm:entry-point')
void _onBackgroundTap(NotificationResponse response) {
  try {
    debugPrint('[NOTI] background tap: ${response.payload}');
  } catch (_) {
    // no-op
  }
}
