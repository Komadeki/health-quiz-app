import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart'; // ← クリップボード用
import '../services/app_settings.dart';
import '../services/attempt_store.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  // ──────────────────────────────
  // 設定をデフォルトへリセット
  // ──────────────────────────────
  Future<void> _confirmReset(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context); // ← 追加
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('デフォルトへリセット'),
        content: const Text('すべての設定を初期値に戻します。よろしいですか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('リセット'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await context.read<AppSettings>().resetToDefaults();
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('設定をデフォルトに戻しました')));
    }
  }

  // ──────────────────────────────
  // 試行履歴クリア（AttemptStore）
  // ──────────────────────────────
  Future<void> _confirmClearAttempts(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context); // ← 追加
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('履歴を削除しますか？'),
        content: const Text('この操作は取り消せません。保存された試行履歴がすべて削除されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('削除する'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AttemptStore().clearAll();
    if (!context.mounted) return;
    messenger.showSnackBar(const SnackBar(content: Text('試行履歴を削除しました')));
  }

  // ──────────────────────────────
  // エクスポート（クリップボードへコピー）
  // ──────────────────────────────
  Future<void> _exportAttempts(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context); // ← 追加
    try {
      final json = await AttemptStore().exportJson();
      await Clipboard.setData(ClipboardData(text: json));
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('試行履歴をクリップボードへコピーしました')),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('エクスポートに失敗しました：$e')));
    }
  }

  // ──────────────────────────────
  // インポート（貼り付け→検証→マージ）
  // ──────────────────────────────
  Future<void> _importAttempts(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context); // ← 追加
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('試行履歴をインポート'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('エクスポートしたJSONを貼り付けてください。'),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 10,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '{ "version": 1, "items": [ ... ] }',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('インポート'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    final text = controller.text.trim();
    if (text.isEmpty) {
      if (!context.mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('JSONが空です')));
      return;
    }

    try {
      final added = await AttemptStore().importJson(text);
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('インポート完了：$added 件を追加しました')),
      );
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('インポートに失敗しました：$e')));
    }
  }

  // ──────────────────────────────
  // build()
  // ──────────────────────────────
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppSettings>();

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          // ── 表示設定 ──────────────────────────────
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

          // ── クイズ動作 ──────────────────────────────
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
                DropdownMenuItem(
                  value: TapAdvanceMode.oneTap,
                  child: Text('1タップ'),
                ),
                DropdownMenuItem(
                  value: TapAdvanceMode.twoTap,
                  child: Text('2タップ'),
                ),
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

          // ── データ管理 ──────────────────────────────
          _SectionHeader('データ管理'),
          ListTile(
            leading: Icon(
              Icons.delete_forever,
              color: Theme.of(context).colorScheme.error,
            ),
            title: const Text('試行履歴をクリア'),
            subtitle: const Text('保存された全ての試行履歴（Attempt）を削除します'),
            onTap: () => _confirmClearAttempts(context),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('試行履歴をエクスポート'),
            subtitle: const Text('JSONをクリップボードへコピーします'),
            onTap: () => _exportAttempts(context),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('試行履歴をインポート'),
            subtitle: const Text('JSONを貼り付けてマージします（重複は自動スキップ）'),
            onTap: () => _importAttempts(context),
          ),
          const Divider(height: 24),

          // ── サポート ──────────────────────────────
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
              // TODO: 画面遷移 or メールリンク
            },
          ),
          const Divider(height: 24),

          // ── アプリ情報 ──────────────────────────────
          _SectionHeader('アプリ情報'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('バージョン v1.0.0'),
            subtitle: const Text('開発：もけけapps'),
          ),

          // ── デフォルトへ ──────────────────────────────
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

// ──────────────────────────────
// 小見出しウィジェット
// ──────────────────────────────
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
