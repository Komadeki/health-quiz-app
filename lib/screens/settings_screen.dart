import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmReset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('デフォルトへリセット'),
        content: const Text('すべての設定を初期値に戻します。よろしいですか？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('キャンセル')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('リセット')),
        ],
      ),
    );
    if (ok == true) {
      await context.read<AppSettings>().resetToDefaults();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('設定をデフォルトに戻しました')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          // ── 表示設定 ─────────────────────────────────────
          _SectionHeader('表示設定'),
          SwitchListTile(
            title: const Text('テーマ切り替え（ライト／ダーク）'),
            value: s.isDark,
            onChanged: s.setDark,
          ),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('文字サイズ'),
            subtitle: Text(switch (s.textSize) {
              TextSize.small => '小',
              TextSize.medium => '中',
              TextSize.large => '大',
            }),
            trailing: DropdownButton<TextSize>(
              value: s.textSize,
              onChanged: (v) => s.setTextSize(v!),
              items: const [
                DropdownMenuItem(value: TextSize.small, child: Text('小')),
                DropdownMenuItem(value: TextSize.medium, child: Text('中')),
                DropdownMenuItem(value: TextSize.large, child: Text('大')),
              ],
            ),
          ),
          const Divider(height: 24),

          // ── クイズ動作 ──────────────────────────────────
          _SectionHeader('クイズ動作'),
          ListTile(
            leading: const Icon(Icons.touch_app_outlined),
            title: const Text('回答確定方法'),
            subtitle: Text(
              s.tapMode == TapAdvanceMode.oneTap ? '1タップで進む' : '2タップで進む',
            ),
            trailing: DropdownButton<TapAdvanceMode>(
              value: s.tapMode,
              onChanged: (v) => s.setTapMode(v!),
              items: const [
                DropdownMenuItem(value: TapAdvanceMode.oneTap, child: Text('1タップ')),
                DropdownMenuItem(value: TapAdvanceMode.twoTap, child: Text('2タップ')),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('出題単元の選択状況を保存'),
            subtitle: const Text('OFFにすると毎回、未選択から開始します（単元・ミックスともに）'),
            value: s.saveUnitSelection,
            onChanged: s.setSaveUnitSelection,
          ),
          SwitchListTile(
            title: const Text('ランダム出題'),
            subtitle: const Text('ONにすると問題の順番をランダムにします'),
            value: s.randomize,
            onChanged: s.setRandomize,
          ),
          const Divider(height: 24),

          // ── サポート ───────────────────────────────────
          _SectionHeader('サポート'),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('ライセンス／クレジット'),
            onTap: () {
              // TODO: 画面遷移 or ダイアログ
            },
          ),
          ListTile(
            leading: const Icon(Icons.chat_outlined),
            title: const Text('お問い合わせ・フィードバック'),
            subtitle: const Text('問題修正依頼や意見・感想はこちら'),
            onTap: () {
              // TODO: 画面遷移 or メール
            },
          ),
          const Divider(height: 24),

          // ── アプリ情報 ─────────────────────────────────
          _SectionHeader('アプリ情報'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('バージョン v1.0.0（例）'),
            subtitle: const Text('開発：もけけapps'),
          ),

          // デフォルトへ
          SafeArea(
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.restore),
                label: const Text('デフォルトに戻す'),
                onPressed: () => _confirmReset(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.secondary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
