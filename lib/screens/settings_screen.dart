import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_settings.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, this.feedbackUrl});
  final String? feedbackUrl;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          _head('表示設定'),
          SwitchListTile(
            secondary: const Icon(Icons.brightness_6),
            title: const Text('テーマ切り替え（ライト／ダーク）'),
            value: s.isDark,
            onChanged: s.setDark,
          ),
          ListTile(
            leading: const Icon(Icons.text_fields),
            title: const Text('文字サイズ'),
            subtitle: Text(_labelTextSize(s.textSize)),
            trailing: DropdownButton<TextSize>(
              value: s.textSize,
              onChanged: (v) { if (v != null) s.setTextSize(v); },
              items: const [
                DropdownMenuItem(value: TextSize.small, child: Text('小')),
                DropdownMenuItem(value: TextSize.medium, child: Text('中')),
                DropdownMenuItem(value: TextSize.large, child: Text('大')),
              ],
            ),
          ),
          const Divider(),
          _head('クイズ動作'),
          ListTile(
            leading: const Icon(Icons.touch_app),
            title: const Text('回答確定方法'),
            subtitle: Text(s.tapMode == TapAdvanceMode.oneTap ? '1タップで進む' : '2タップで進む（選択→確定）'),
            trailing: DropdownButton<TapAdvanceMode>(
              value: s.tapMode,
              onChanged: (v) { if (v != null) s.setTapMode(v); },
              items: const [
                DropdownMenuItem(value: TapAdvanceMode.oneTap, child: Text('1タップ')),
                DropdownMenuItem(value: TapAdvanceMode.twoTap, child: Text('2タップ')),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.restore_page),
            title: const Text('前回の選択状況を保存'),
            value: s.savePrevSelection,
            onChanged: s.setSavePrevSelection,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.shuffle),
            title: const Text('ランダム出題'),
            value: s.randomize,
            onChanged: s.setRandomize,
          ),
          const Divider(),
          _head('サポート'),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('ライセンス／クレジット'),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'Health Quiz',
              applicationVersion: '',
              applicationLegalese: 'Flutter / OpenAI / 教材制作チーム',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.forum_outlined),
            title: const Text('お問い合わせ・フィードバック'),
            subtitle: const Text('問題修正依頼や意見・感想はこちら'),
            onTap: () async {
              final url = feedbackUrl ?? 'https://example.com/feedback';
              final uri = Uri.parse(url);
              if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('リンクを開けませんでした')),
                  );
                }
              }
            },
          ),
          const Divider(),
          _head('アプリ情報'),
          FutureBuilder(
            future: PackageInfo.fromPlatform(),
            builder: (context, snap) {
              final v = (snap.data?.version ?? '—');
              final b = (snap.data?.buildNumber ?? '—');
              return ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('アプリ情報'),
                subtitle: Text('バージョン v$v ($b)\n開発：もけけapps'),
              );
            },
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.restore),
              label: const Text('デフォルトに戻す'),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('設定をデフォルトに戻しますか？'),
                    content: const Text('すべての設定が初期値にリセットされます。'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('キャンセル')),
                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('リセット')),
                    ],
                  ),
                );
                if (ok == true) {
                  await context.read<AppSettings>().resetToDefaults();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('デフォルトに戻しました')));
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _head(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(t, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black54)),
  );

  String _labelTextSize(TextSize s) => switch (s) {
    TextSize.small => '小',
    TextSize.medium => '中',
    TextSize.large => '大',
  };
}
