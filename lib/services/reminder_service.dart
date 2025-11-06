// lib/services/reminder_service.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // kDebugMode
import 'package:health_quiz_app/services/notification_bootstrap_v19.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/nav_service.dart';
import '../services/review_test_builder.dart';
import '../services/attempt_store.dart';
import '../services/deck_loader.dart';
import '../models/review_scope.dart';
import '../screens/quiz_screen.dart';
import '../utils/logger.dart';

/// 復習リマインダー管理クラス
class ReminderService {
  ReminderService._internal();
  static final ReminderService instance = ReminderService._internal();

  /// 起動時にNavigatorがまだ無い場合、payloadを一時保存
  String? pendingPayload;

  /// アプリ起動時などに一度だけ初期化
  Future<void> init() async {
    try {
      await NotificationBootstrapV19.instance.initialize(
        onTap: (payload) async {
          AppLog.i('[REMINDER] onTap payload=$payload ctx=${NavService.I.ctx != null}');
          if (payload == null) return;

          final ctx = NavService.I.ctx;
          if (ctx == null) {
            pendingPayload = payload; // UIツリー未準備 → 後で処理
            AppLog.w('[REMINDER] Navigator not ready — payload stored.');
            return;
          }

          if (payload == 'review_test') {
            WidgetsBinding.instance.addPostFrameCallback((_) => _openReviewTest());
          }
        },
      );
      AppLog.i('[REMINDER] initialized successfully');
    } catch (e, st) {
      AppLog.e('[REMINDER] init failed: $e\n$st'); // 握ってクラッシュ防止
    }
  }

  /// アプリ起動後に保留された通知を処理する
  void handlePendingPayloadIfNeeded() {
    if (pendingPayload == 'review_test') {
      AppLog.i('[REMINDER] handling pending payload');
      pendingPayload = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _openReviewTest());
    }
  }

  // =========================================================
  // ✅ テスト用：即時通知 / 30秒後通知
  // =========================================================

  /// 即時通知（表示系テスト）
  /// - NotificationBootstrapV19 側に showNow がある前提。
  /// - 無い場合は、Bootstrapに実装を追加してください（同じシグネチャでOK）。
  Future<void> showNow({
    String title = 'テスト通知（即時）',
    String body = 'show() による即時表示の確認',
    String? payload,
  }) async {
    try {
      await NotificationBootstrapV19.instance.showNow(
        id: 900001, // テスト用ID帯
        title: title,
        body: body,
        payload: payload,
      );
      AppLog.i('[REMINDER] showNow() dispatched');
    } catch (e, st) {
      AppLog.e('[REMINDER] showNow() failed: $e\n$st');
      rethrow;
    }
  }

  // =========================================================
  // 起動時の再登録（Prefsから復元）
  // =========================================================
  Future<void> ensureScheduledFromPrefsOnLaunch() async {
    final p = await SharedPreferences.getInstance();
    final isEnabled = p.getBool('reminder_enabled') ?? false;
    if (!isEnabled) return;

    final hour = p.getInt('reminder_hour') ?? 20;
    final minute = p.getInt('reminder_minute') ?? 0;
    final freq = p.getString('reminder_freq') ?? '毎日';
    final anchorIso = p.getString('reminder_anchor');
    final anchor = anchorIso != null ? DateTime.tryParse(anchorIso) : null;

    const payload = 'review_test';

    // 念のため重複防止
    await cancelAll();

    if (freq == '毎日') {
      await scheduleReviewDaily(hour: hour, minute: minute, payload: payload);
    } else if (freq == '3日ごと' && anchor != null) {
      await scheduleReviewPeriodicFrom(
        anchorLocal: anchor,
        daysInterval: 3,
        hour: hour,
        minute: minute,
        payload: payload,
      );
    } else if (freq == '科学的スケジュール') {
      await scheduleSpacedReview(hour: hour, minute: minute, payload: payload);
    }
  }

  /// 30秒後に一回だけ通知（スケジュール経路テスト）
  Future<void> scheduleOnce30sec({String? payload}) async {
    final when = DateTime.now().add(const Duration(seconds: 30));
    try {
      await NotificationBootstrapV19.instance.scheduleOnce(
        id: 910001, // 30秒テスト用ID帯
        title: 'テスト通知（30秒後）',
        body: 'zonedSchedule + exactAllowWhileIdle 経路の確認',
        whenLocal: when,
        payload: payload,
      );
      AppLog.i('[REMINDER] scheduleOnce30sec() scheduled at $when');
    } catch (e, st) {
      AppLog.e('[REMINDER] scheduleOnce30sec() failed: $e\n$st');
      rethrow;
    }
  }

  // （任意）開発向けのワンタップ関数
  Future<void> debugShowNowTest() => showNow(payload: 'review_test');
  Future<void> debugScheduleOnce30secTest() => scheduleOnce30sec(payload: 'review_test');

  // =========================================================
  // 本番系スケジューラ
  // =========================================================

  /// 単発リマインダー（例：10秒後に1回通知）
  Future<void> scheduleReviewOnce({
    required DateTime whenLocal,
    String? payload,
  }) async {
    await NotificationBootstrapV19.instance.scheduleOnce(
      id: 1001,
      title: '復習の時間です',
      body: '間違えた問題をサクッと見直しましょう！',
      whenLocal: whenLocal,
      payload: payload,
    );
  }

  /// 毎日同時刻のリマインダー
  Future<void> scheduleReviewDaily({
    required int hour,
    required int minute,
    String? payload,
  }) async {
    await NotificationBootstrapV19.instance.scheduleDaily(
      id: 1002,
      title: '今日の復習リマインダー',
      body: '昨日の誤答からトップ10を再テスト！',
      hour: hour,
      minute: minute,
      payload: payload,
    );
  }

  /// （汎用/デバッグ用）等間隔で複数回スケジュール
  /// 本番はアンカー起点の `scheduleReviewPeriodicFrom` を使う想定
  Future<void> scheduleReviewPeriodic({
    required int daysInterval,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    if (kDebugMode) {
      for (int i = 0; i < 5; i++) {
        final date = DateTime.now().add(Duration(seconds: (i + 1) * 5));
        await NotificationBootstrapV19.instance.scheduleOnce(
          id: 2000 + i,
          title: '復習リマインダー（デバッグ）',
          body: 'これはデバッグ用の${i + 1}回目の通知です',
          whenLocal: date,
          payload: payload,
        );
      }
      debugPrint('✅ [DEBUG] 5秒おきのデバッグ通知を5回スケジュールしました');
    } else {
      for (int i = 0; i < 5; i++) {
        final d = DateTime.now().add(Duration(days: i * daysInterval));
        await NotificationBootstrapV19.instance.scheduleOnce(
          id: 2000 + i,
          title: '復習リマインダー',
          body: '${daysInterval}日ごとの復習日です！',
          whenLocal: DateTime(d.year, d.month, d.day, hour, minute),
          payload: payload,
        );
      }
      debugPrint('✅ [PROD] ${daysInterval}日ごとの復習通知を5回スケジュールしました');
    }
  }

  /// ★ アンカー（有効化/変更した日）から “必ず +interval 日後” を起点に登録（B案）
  Future<void> scheduleReviewPeriodicFrom({
    required DateTime anchorLocal,
    required int daysInterval,
    required int hour,
    required int minute,
    String? payload,
  }) async {
    // 1回目：アンカー日の指定時刻 + interval 日
    var first = DateTime(anchorLocal.year, anchorLocal.month, anchorLocal.day, hour, minute)
        .add(Duration(days: daysInterval));

    // 過去になっていたら先へ送る
    while (first.isBefore(DateTime.now())) {
      first = first.add(Duration(days: daysInterval));
    }

    // 以後、何回か先まで等間隔で予約（必要に応じて回数は調整）
    for (int i = 0; i < 5; i++) {
      final when = first.add(Duration(days: daysInterval * i));
      await NotificationBootstrapV19.instance.scheduleOnce(
        id: 2100 + i, // 2000系とID帯を分けて衝突回避
        title: '復習リマインダー',
        body: '${daysInterval}日ごとの復習日です！',
        whenLocal: when,
        payload: payload,
      );
    }
    debugPrint('✅ [PROD] anchor=$anchorLocal → ${daysInterval}日ごとに5件予約しました（起点=$first）');
  }

  /// 科学的スケジュール（忘却曲線ベース）
  Future<void> scheduleSpacedReview({
    required int hour,
    required int minute,
    String? payload,
  }) async {
    final spacedDays = [1, 3, 7, 14, 30];
    for (int i = 0; i < spacedDays.length; i++) {
      final d = DateTime.now().add(Duration(days: spacedDays[i]));
      await NotificationBootstrapV19.instance.scheduleOnce(
        id: 3000 + i,
        title: '復習のタイミングです',
        body: '学んだ内容を再確認しましょう（${spacedDays[i]}日目）',
        whenLocal: DateTime(d.year, d.month, d.day, hour, minute),
        payload: payload,
      );
    }
  }

  /// 全リマインダー削除
  Future<void> cancelAll() => NotificationBootstrapV19.instance.cancelAll();

  /// 通知タップ時：復習テストへ遷移
  Future<void> _openReviewTest() async {
    final ctx = NavService.I.ctx;
    if (ctx == null) {
      AppLog.w('[REMINDER] ctx is null — cannot navigate');
      return;
    }

    final scope = ScoreScope(); // fallback: 全期間
    final builder = ReviewTestBuilder(
      attempts: AttemptStore(),
      loader: await DeckLoader.instance(),
    );

    final cards = await builder.buildTopNWithScope(topN: 20, scope: scope);
    AppLog.i('[REMINDER] navigating to QuizScreen (cards=${cards.length})');

    if (cards.isEmpty) {
      AppLog.w('[REMINDER] No cards available for review.');
      return;
    }

    final decks = await (await DeckLoader.instance()).loadAll();
    final deck = decks.first;

    if (!ctx.mounted) return;
    Navigator.of(ctx, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => QuizScreen(
          deck: deck,
          overrideCards: cards,
        ),
      ),
    );
  }
}
