# Pre-merge Checklist (Flutter / Android)

対象ブランチを main に統合する前の検証手順書です。  
この手順書は **ソース変更を一切行いません**（読み取り・ビルド・実行・ログ確認のみ）。

- 対象: Android（将来 iOS 追加予定）
- 参考スクリプト: `tools/pre_merge_check.sh`

---

## 0. 前提
- Android 実機 or エミュレータが起動済み（`flutter devices` で確認）
- `pubspec.yaml` がリポジトリ直下にあること
- ネットワーク接続（依存取得のため）

---

## 1. リポジトリ状態チェック（差分確認のみ）
```bash
git status
git diff --name-only main...
git log --oneline -n 10
