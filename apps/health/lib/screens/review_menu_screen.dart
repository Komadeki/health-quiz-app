import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/reminder_service.dart';
import 'review_cards_screen.dart';
import 'review_test_setup_screen.dart';
import '../widgets/review_reminder_card.dart';

class ReviewMenuScreen extends StatefulWidget {
  const ReviewMenuScreen({super.key});

  @override
  State<ReviewMenuScreen> createState() => _ReviewMenuScreenState();
}

class _ReviewMenuScreenState extends State<ReviewMenuScreen> {
  bool _reminderEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 19, minute: 0);
  String _reminderFrequency = 'daily'; // "daily", "3days", "spaced"

  @override
  void initState() {
    super.initState();
    _loadReminderSettings();
  }

  Future<void> _loadReminderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _reminderEnabled = prefs.getBool('reminderEnabled') ?? false;
      final h = prefs.getInt('reminderHour');
      final m = prefs.getInt('reminderMinute');
      if (h != null && m != null) {
        _reminderTime = TimeOfDay(hour: h, minute: m);
      }
      _reminderFrequency = prefs.getString('reminderFrequency') ?? 'daily';
    });
  }

  Future<void> _saveReminderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('reminderEnabled', _reminderEnabled);
    await prefs.setInt('reminderHour', _reminderTime.hour);
    await prefs.setInt('reminderMinute', _reminderTime.minute);
    await prefs.setString('reminderFrequency', _reminderFrequency);
  }

  Future<void> _toggleReminder(bool value) async {
    setState(() => _reminderEnabled = value);
    await _saveReminderSettings();

    if (value) {
      await _scheduleCurrentReminder();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('復習リマインダーを設定しました')),
        );
      }
    } else {
      await ReminderService.instance.cancelAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('復習リマインダーを停止しました')),
        );
      }
    }
  }

  Future<void> _scheduleCurrentReminder() async {
    final hour = _reminderTime.hour;
    final minute = _reminderTime.minute;

    switch (_reminderFrequency) {
      case 'daily':
        await ReminderService.instance.scheduleReviewPeriodic(
          daysInterval: 1,
          hour: hour,
          minute: minute,
          payload: 'review_test',
        );
        break;
      case '3days':
        await ReminderService.instance.scheduleReviewPeriodic(
          daysInterval: 3,
          hour: hour,
          minute: minute,
          payload: 'review_test',
        );
        break;
      case 'spaced':
        await ReminderService.instance.scheduleSpacedReview(
          hour: hour,
          minute: minute,
          payload: 'review_test',
        );
        break;
    }
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
    );
    if (t != null) {
      setState(() => _reminderTime = t);
      await _saveReminderSettings();
      if (_reminderEnabled) {
        await _scheduleCurrentReminder();
      }
    }
  }

  BoxDecoration _cardDecoration(BuildContext context) {
    final theme = Theme.of(context);
    return BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: theme.colorScheme.outline.withOpacity(0.15)),
      boxShadow: const [
        BoxShadow(
          blurRadius: 10,
          offset: Offset(0, 3),
          color: Color(0x1A000000),
        ),
      ],
    );
  }

  Widget _buildReminderCard(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: _cardDecoration(context),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_active_outlined, size: 36, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                '復習リマインダー',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Switch(
                value: _reminderEnabled,
                onChanged: _toggleReminder,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '毎日の決まった時間に通知を送り、復習の習慣化をサポートします。',
            style: theme.textTheme.bodyLarge?.copyWith(
              height: 1.4,
              color: theme.colorScheme.onSurface.withOpacity(0.85),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                '通知時刻: ${_reminderTime.format(context)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule_outlined, size: 18),
                label: const Text('変更'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '通知頻度:',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _reminderFrequency,
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() => _reminderFrequency = v);
                  await _saveReminderSettings();
                  if (_reminderEnabled) await _scheduleCurrentReminder();
                },
                items: const [
                  DropdownMenuItem(
                    value: 'daily',
                    child: Text('毎日'),
                  ),
                  DropdownMenuItem(
                    value: '3days',
                    child: Text('3日ごと'),
                  ),
                  DropdownMenuItem(
                    value: 'spaced',
                    child: Text('科学的スケジュール'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard({
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        decoration: _cardDecoration(context),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Row(
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.primary),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    description,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: 1.4,
                      color: theme.colorScheme.onSurface.withOpacity(0.85),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('復習')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            '間違いを学びに変える — あなたのペースで復習しよう。',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.8),
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _buildModeCard(
            icon: Icons.style_outlined,
            title: '見直しモード',
            description: 'これまでに間違えた問題カードを1枚ずつめくりながら復習します。',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReviewCardsScreen()),
            ),
          ),
          const SizedBox(height: 18),
          _buildModeCard(
            icon: Icons.quiz_outlined,
            title: '復習テストモード',
            description: '誤答の多い問題を自動で選び、苦手を集中的に確認します。',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReviewTestSetupScreen()),
            ),
          ),
          const SizedBox(height: 18),
          // 🟢 新規追加
          const ReviewReminderCard(),
        ],
      ),
    );
  }
}
