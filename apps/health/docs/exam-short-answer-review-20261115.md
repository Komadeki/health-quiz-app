# 短答記述 10問の照合（2026-11-15）

ユーザー確認: 用語・数語を入力して自動採点する形式。穴埋め15問、正誤判断15問、既存4択は保持し、独立した `short_answer` を10問追加する。学年は固定せず、実際の試験範囲から抽出する。

各問の正答、許容する漢字・かな・略称表記、一次資料を登録した。空欄のない問いに対して名称を自分で入力する。入力は空白、英字の大小・全半角を正規化し、登録済みの解答・許容表記と完全一致で採点する。

- 受動喫煙は「間接喫煙」「不随意喫煙」「二次喫煙」も許容する。公的資料の同義語を誤答にしない。[厚生労働省掲載のWHOガイドライン](https://www.mhlw.go.jp/topics/tobacco/dl/fctc8_guideline.pdf)で照合。
- 「HIV」は英字3文字と明記し、AIDSとの混同を採点で区別する。
- レム睡眠は「〜睡眠」の形での回答を求め、ノンレム睡眠との混同を区別する。
- 糖質と糖類、健康寿命と平均寿命、薬物の耐性と依存は別の概念として扱う。
- 労災保険は正式名称と「制度」を付けた表記も許容する。労災そのものを制度名とは扱わない。
- 「正答ではない」「正答または別の答え」などの文字列を、正答語を含むだけで加点しない。
- 旧3形式のスナップショット、既存問題ID・購入条件は維持する。

| ID | 正答 | 照合資料 |
| --- | --- | --- |
| h1-s01 | 糖質 | [厚生労働省 e-ヘルスネット](https://kennet.mhlw.go.jp/information/information/food/e-02-004.html) |
| h1-s02 | レム睡眠 | [厚生労働省 e-ヘルスネット](https://kennet.mhlw.go.jp/information/information/dictionary/heart/yk-069.html) |
| h1-s03 | 受動喫煙 | [厚生労働省 e-ヘルスネット](https://kennet.mhlw.go.jp/information/information/tobacco/t-05-004.html) |
| h1-s04 | 急性アルコール中毒 | [厚生労働省 e-ヘルスネット](https://kennet.mhlw.go.jp/information/information/dictionary/alcohol/ya-014.html) |
| h1-s05 | 耐性 | [厚生労働省 薬物乱用防止資料](https://www.mhlw.go.jp/bunya/iyakuhin/dl/dame_kenkou30.pdf) |
| h2-s01 | HIV | [厚生労働省 HIV検査・相談マップ](https://www.mhlw.go.jp/hivkensa/knowledge/whatis/) |
| h2-s02 | 健康寿命 | [厚生労働省 e-ヘルスネット](https://kennet.mhlw.go.jp/information/information/hale/h-01-001.html) |
| h2-s03 | 労働安全衛生法 | [厚生労働省 労働条件・職場環境に関するルール](https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/koyou_roudou/roudouseisaku/chushoukigyou/joken_kankyou_rule.html) |
| h2-s04 | 労災保険 | [厚生労働省 労働条件・職場環境に関するルール](https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/koyou_roudou/roudouseisaku/chushoukigyou/joken_kankyou_rule.html) |
| h2-s05 | ストレス | [東京都保健医療局 こころの健康](https://www.hokeniryo1.metro.tokyo.lg.jp/kensui/kokoro/tamotsu.html) |
