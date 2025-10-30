// lib/widgets/review_reminder_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/reminder_service.dart';

class ReviewReminderCard extends StatefulWidget {
  const ReviewReminderCard({super.key});

  @override
  State<ReviewReminderCard> createState() => _ReviewReminderCardState();
}

class _ReviewReminderCardState extends State<ReviewReminderCard> {
  /// 有効/無効
  bool enabled = false;

  /// 通知時刻
  TimeOfDay time = const TimeOfDay(hour: 20, minute: 0);

  /// 周期（UIの選択肢）
  static const List<String> _freqOptions = ['毎日', '3日ごと', '科学的スケジュール'];
  String frequency = _freqOptions.first;

  /// アンカー日（有効化/変更した日）— 周期計算の起点
  DateTime? _anchorDate;

  /// 次回通知日時（UI表示用）
  DateTime? nextDate;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  // ---------------- Prefs ----------------

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool('reminder_enabled') ?? false;
    final h = p.getInt('reminder_hour');
    final m = p.getInt('reminder_minute');
    if (h != null && m != null) {
      time = TimeOfDay(hour: h, minute: m);
    }
    frequency = p.getString('reminder_freq') ?? '毎日';
    final iso = p.getString('reminder_anchor');
    if (iso != null) _anchorDate = DateTime.tryParse(iso);

    // 表示更新
    nextDate = _calcNextDate(anchor: _anchorDate, frequency: frequency, time: time);
    if (mounted) setState(() {});
  }

  Future<void> _savePrefs() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('reminder_enabled', enabled);
    await p.setInt('reminder_hour', time.hour);
    await p.setInt('reminder_minute', time.minute);
    await p.setString('reminder_freq', frequency);
    if (_anchorDate != null) {
      await p.setString('reminder_anchor', _anchorDate!.toIso8601String());
    }
  }

  // ---------------- 次回日時計算 ----------------

  DateTime? _calcNextDate({
    required DateTime? anchor,
    required String frequency,
    required TimeOfDay time,
  }) {
    final now = DateTime.now();
    DateTime todayAt(TimeOfDay t) => DateTime(now.year, now.month, now.day, t.hour, t.minute);

    if (frequency == '毎日') {
      final today = todayAt(time);
      return (today.isAfter(now)) ? today : today.add(const Duration(days: 1));
    }

    // 起点が無ければ今日を起点に
    final base = anchor ?? now;

    if (frequency == '3日ごと') {
      var d = DateTime(base.year, base.month, base.day, time.hour, time.minute);
      while (!d.isAfter(now)) {
        d = d.add(const Duration(days: 3));
      }
      return d;
    }

    if (frequency == '科学的スケジュール') {
      const spaced = [1, 3, 7, 14, 30];
      for (final add in spaced) {
        final d = DateTime(base.year, base.month, base.day, time.hour, time.minute)
            .add(Duration(days: add));
        if (d.isAfter(now)) return d;
      }
      // サイクルを回し切ったら翌日の同時刻から再開
      final restart = todayAt(time).add(const Duration(days: 1));
      return restart.isAfter(now) ? restart : restart.add(const Duration(days: 1));
    }

    return null;
  }

  // ---------------- スケジュール実行 ----------------

  Future<void> _applySchedule() async {
    // いったん全削除してから再登録
    await ReminderService.instance.cancelAll();

    if (!enabled) return;

    final h = time.hour, m = time.minute;
    const payload = 'review_test';

    if (frequency == '毎日') {
      await ReminderService.instance.scheduleReviewDaily(
        hour: h,
        minute: m,
        payload: payload,
      );
    } else if (frequency == '3日ごと') {
      await ReminderService.instance.scheduleReviewPeriodic(
        daysInterval: 3,
        hour: h,
        minute: m,
        payload: payload,
      );
    } else if (frequency == '科学的スケジュール') {
      await ReminderService.instance.scheduleSpacedReview(
        hour: h,
        minute: m,
        payload: payload,
      );
    }
  }

  // ---------------- UIハンドラ ----------------

  Future<void> _onToggle(bool v) async {
    setState(() => enabled = v);
    if (enabled) {
      // 有効化のタイミングを起点に
      _anchorDate = DateTime.now();
      nextDate = _calcNextDate(anchor: _anchorDate, frequency: frequency, time: time);
      await _applySchedule();
    } else {
      nextDate = null;
      await ReminderService.instance.cancelAll();
    }
    await _savePrefs();
    if (mounted) setState(() {});
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: time);
    if (picked == null) return;

    setState(() => time = picked);
    // 時刻変更＝新しい起点にするのが自然
    _anchorDate = DateTime.now();
    nextDate = _calcNextDate(anchor: _anchorDate, frequency: frequency, time: time);
    await _applySchedule();
    await _savePrefs();
    if (mounted) setState(() {});
  }

  Future<void> _changeFreq(String v) async {
    setState(() => frequency = v);
    _anchorDate ??= DateTime.now();
    nextDate = _calcNextDate(anchor: _anchorDate, frequency: frequency, time: time);
    await _applySchedule();
    await _savePrefs();
    if (mounted) setState(() {});
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final df = DateFormat('M/d（E）', 'ja');

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.18), width: 1),
        boxShadow: const [
          BoxShadow(blurRadius: 12, offset: Offset(0, 2), color: Color(0x14000000)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // タイトル行
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.notifications_active_outlined,
                      color: theme.colorScheme.primary, size: 32),
                  const SizedBox(width: 12),
                  Text(
                    '復習リマインダー',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ],
              ),
              Switch(value: enabled, onChanged: _onToggle),
            ],
          ),

          const SizedBox(height: 10),
          Text(
            '毎日の決まった時間に通知を送り、復習の習慣化をサポートします。',
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.4,
              color: theme.colorScheme.onSurface.withOpacity(0.9),
            ),
          ),

          const SizedBox(height: 16),

          // 通知時刻
          Row(
            children: [
              Text('通知時刻: ${time.format(context)}', style: theme.textTheme.bodyLarge),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: enabled ? _pickTime : null,
                icon: const Icon(Icons.access_time),
                label: const Text('変更'),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 周期
          Row(
            children: [
              const Text('通知頻度:  '),
              DropdownButton<String>(
                value: frequency,
                items: _freqOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: enabled ? (v) => _changeFreq(v!) : null,
              ),
            ],
          ),

          // 次回の通知予定
          const SizedBox(height: 8),
          Text(
            enabled && nextDate != null ? '次回の通知予定: ${df.format(nextDate!)}' : '次回の通知予定: —',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
