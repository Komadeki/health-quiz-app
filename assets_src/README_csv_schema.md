# デッキデータ作成フロー

本アプリの問題データ（デッキ）は **CSVで作成 → JSONに変換** して `assets/decks` に配置します。  
この仕組みにより、問題の追加・修正が簡単に行えます。

---

## 1. ディレクトリ構成

assets_src/
csv/ # 各単元ごとのCSVファイル
unit_smoking.csv
unit_alcohol.csv
...
README.md # ← この説明書
tools/
convert_csv_to_json.py # CSV → JSON変換スクリプト
assets/
decks/ # アプリで読み込む完成済みJSONファイル
unit_smoking.json
unit_alcohol.json

markdown
コードをコピーする

---

## 2. CSV フォーマット

CSVは以下のカラムを持ちます。

| カラム名        | 説明 |
|-----------------|------|
| `id`            | 問題の連番（任意、なくてもよい） |
| `deck_id`       | 所属するデッキのID（例: `unit_smoking`） |
| `question`      | 問題文 |
| `choice1..4`    | 選択肢（最大4択、空欄は無視される） |
| `answer_index`  | 正解番号（1〜4の整数、1-based。JSONでは0-basedに変換される） |
| `explanation`   | 解説文（任意、空欄可） |
| `tags`          | カード単位のタグ。複数指定する場合はカンマ区切り（例: `喫煙, 健康被害`） |
| `difficulty`    | 難易度（任意。例: `1=基礎`, `2=応用`, `3=発展`） |

### ✅ CSVサンプル

```csv
id,deck_id,question,choice1,choice2,choice3,choice4,answer_index,explanation,tags,difficulty
1,unit_health,WHO憲章が採択された年は？,1946年,1950年,1960年,1975年,1,WHO憲章は1946年に採択された,健康,1
2,unit_health,QOLの意味は？,Quantity of Life,Quality of Life,Quest of Life,Queue of Life,2,QOLはQuality of Lifeの略,基礎,1
3,unit_smoking,喫煙による健康影響は？,肺がんリスク増加,骨粗鬆症改善,視力回復,虫歯予防,1,喫煙は肺がんの大きなリスク要因,喫煙,2
3. JSON出力例
変換後は以下のような形式で assets/decks/*.json に保存されます。

json
コードをコピーする
{
  "id": "unit_smoking",
  "title": "喫煙と健康",
  "cards": [
    {
      "question": "喫煙による健康影響は？",
      "choices": ["肺がんリスク増加", "骨粗鬆症改善", "視力回復", "虫歯予防"],
      "answerIndex": 0,
      "explanation": "喫煙は肺がんの大きなリスク要因",
      "tags": ["喫煙"],
      "difficulty": "2",
      "isPremium": false
    }
  ]
}
4. 変換方法
以下のスクリプトを利用してCSVをJSONに変換します。

bash
コードをコピーする
# 例: 喫煙単元を変換
python3 tools/convert_csv_to_json.py \
  --input assets_src/csv/unit_smoking.csv \
  --outdir assets/decks \
  --id unit_smoking \
  --title "喫煙と健康" \
  --free_ratio 0.2
--id: デッキID（ファイル名にもなる）

--title: アプリ内で表示するタイトル

--free_ratio: 無料で遊べる割合（0.2 = 20%）

実行結果の例:

bash
コードをコピーする
OK: assets/decks/unit_smoking.json を出力しました。全20問中、無料4問・有料16問
5. 運用ルール
1単元 = 1CSV として管理

各カードに tagsを必ず付与（弱点集計や成績分析で利用）

unitTags（デッキ全体のタグ）は使わない

JSONはGitに含める（ビルド時に assets/decks/*.json を読み込むため）

CSVは人間が編集する一次データ。Git管理して、再変換すればJSONが再生成される

6. 今後の拡張候補
difficulty の活用（基礎〜発展での出題比率調整）

タグごとの出題制御（例: 「喫煙だけで10問」モード）

問題文に画像を埋め込むサポート（image カラム追加予定）