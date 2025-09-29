#!/usr/bin/env python3
# tools/convert_csv_to_json.py
import argparse, csv, json, math, os, sys

def read_csv(path):
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        rows = []
        for r in reader:
            # すべて文字列化＆trim
            rows.append({k: ("" if v is None else str(v).strip()) for k, v in r.items()})
        return rows

def row_to_card(row):
    q = row.get("question", "").strip()
    choices = [row.get("choice1","").strip(), row.get("choice2","").strip(),
               row.get("choice3","").strip(), row.get("choice4","").strip()]
    choices = [c for c in choices if c]  # 空は除外
    # answer_index: CSVは1〜4想定 → 0-basedへ
    try:
        ans1 = int(row.get("answer_index","").strip() or "1")
    except ValueError:
        ans1 = 1
    # クランプして0-based化
    ans0 = max(0, min(len(choices)-1, ans1-1))
    exp = row.get("explanation", "").strip()
    exp = exp if exp else ""  # JSONでは空文字で持つ

    return {
        "question": q,
        "choices": choices,
        "answerIndex": ans0,
        "explanation": exp,
        # isPremium, unitTags は後で付与
    }

def convert(csv_path, outdir, deck_id, title, free_ratio=0.2):
    rows = read_csv(csv_path)
    cards = [row_to_card(r) for r in rows if (r.get("question","").strip())]

    if not cards:
        raise ValueError("有効な問題がありません（question が空か、CSV未読）")

    # 無料/有料の割当
    n = len(cards)
    free_count = max(1, int(round(n * float(free_ratio))))
    for i, c in enumerate(cards):
        c["isPremium"] = False if i < free_count else True
        c["unitTags"] = []

    deck = {
        "id": deck_id,
        "title": title,
        "cards": cards,
    }

    os.makedirs(outdir, exist_ok=True)
    out_path = os.path.join(outdir, f"{deck_id}.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(deck, f, ensure_ascii=False, indent=2)
    return out_path, len(cards), free_count

def main():
    ap = argparse.ArgumentParser(description="CSV → JSON(Deck) 変換")
    ap.add_argument("--input", required=True, help="入力CSV（単元ごと）")
    ap.add_argument("--outdir", required=True, help="出力JSONディレクトリ（assets/decks など）")
    ap.add_argument("--id", required=True, help="デッキID（例: unit_smoking）")
    ap.add_argument("--title", required=True, help="デッキタイトル（例: 喫煙と健康）")
    ap.add_argument("--free_ratio", type=float, default=0.2, help="無料割合（0.2=20%%）")
    args = ap.parse_args()

    try:
        out_path, total, free_count = convert(
            args.input, args.outdir, args.id, args.title, args.free_ratio
        )
        print(f"OK: {out_path} を出力しました。全{total}問中、無料{free_count}問・有料{total-free_count}問")
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
