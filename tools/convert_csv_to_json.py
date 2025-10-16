#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
CSV → JSON 変換（deck → units → cards 対応）

▼ 使い方（ユニットを直接指定するモード）
python3 tools/convert_csv_to_json.py \
  --deck_id deck_health01 \
  --deck_title "現代社会と健康（前半）" \
  --units "unit_health_concepts:健康の考え方と成り立ち:assets_src/csv/unit_health_concepts.csv,unit_health_status:私たちの健康の考え方:assets_src/csv/unit_health_status.csv" \
  --outdir assets/decks \
  --free_ratio 0.2

▼ 使い方（マスターCSVから自動収集するモード）
python3 tools/convert_csv_to_json.py \
  --master /path/to/deck_unit_master.csv \
  --deck_id deck_health01 \
  --outdir assets/decks \
  --free_ratio 0.2

※ マスターCSVは列構成：
deck_id, deck_title, unit_no, unit_id, unit_title, assets_deck_path, assets_src_csv, status
"""

import argparse
import csv
import json
import os
import sys
from typing import List, Dict, Any


# ---------- CSV 読み込みユーティリティ ----------

def read_csv_rows(path: str) -> List[Dict[str, str]]:
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        rows = []
        for r in reader:
            rows.append({k.strip(): ("" if v is None else str(v).strip()) for k, v in r.items()})
        return rows


def parse_int(value: str, default: int) -> int:
    try:
        return int((value or "").strip())
    except Exception:
        return default


def split_tags(value: str) -> List[str]:
    if not value:
        return []
    return [t.strip() for t in value.split(",") if t.strip()]


# ---------- unit CSV（1単元分） → cards 変換 ----------

def card_from_row(row: Dict[str, str]) -> Dict[str, Any]:
    """
    1行（1問）を JSON カードへ変換
    期待カラム：
      id, deck_id, unit_id, question, choice1..4, answer_index(1-4), explanation, tags, importance(1/2/3)
      ※ 互換対応: importance が無い場合は difficulty(1/2/3) を読み取る
    """

    # ---- stableId の決定（CSVに stable_id があれば優先。無ければ deck_id:unit_id:id で生成）----
    def _gen_stable_id(r: Dict[str, str]) -> str:
        explicit = (r.get("stable_id") or "").strip()
        if explicit:
            return explicit
        deck = (r.get("deck_id") or "").strip()
        unit = (r.get("unit_id") or "").strip()
        cid  = (r.get("id") or "").strip()
        parts = [p for p in (deck, unit, cid) if p]
        return ":".join(parts) if parts else ""

    stable_id = _gen_stable_id(row)

    q = row.get("question", "")
    if not q:
        return {}

    # 選択肢（空は除外：3択でもOK）
    choices = [row.get("choice1", ""), row.get("choice2", ""), row.get("choice3", ""), row.get("choice4", "")]
    choices = [c for c in choices if c]
    if len(choices) < 2:
        return {}

    # answer_index: CSVは 1〜4 → 0-based & 範囲クランプ
    ans1 = parse_int(row.get("answer_index", ""), 1)
    ans0 = max(0, min(len(choices) - 1, ans1 - 1))

    # explanation / tags
    exp = row.get("explanation", "") or ""
    tags = split_tags(row.get("tags", ""))

    # ★ importance を採用（無ければ difficulty をフォールバック）
    importance = parse_int(row.get("importance", row.get("difficulty", "")), 2)
    if importance not in (1, 2, 3):
        importance = 2

    return {
        # ★ 追加：JSON に stableId を出力
        **({"stableId": stable_id} if stable_id else {}),
        "question": q,
        "choices": choices,
        "answerIndex": ans0,
        "explanation": exp,
        "tags": tags,
        "importance": importance,
        # isPremium は build_unit で付与
    }

def build_unit(unit_id: str, unit_title: str, csv_path: str, free_ratio: float) -> Dict[str, Any]:
    rows = read_csv_rows(csv_path)
    cards: List[Dict[str, Any]] = []
    for r in rows:
        c = card_from_row(r)
        if c:
            cards.append(c)

    if not cards:
        raise ValueError(f"[{unit_id}] {csv_path} に有効な問題がありません。")

    # 無料/有料フラグ付与（先頭から free_ratio を無料に）
    n = len(cards)
    free_count = max(1, int(round(n * float(free_ratio)))) if free_ratio > 0 else 0
    for i, c in enumerate(cards):
        c["isPremium"] = False if i < free_count else True

    return {
        "id": unit_id,
        "title": unit_title,
        "cards": cards,
    }


# ---------- 変換パイプライン ----------

def convert_with_units_list(deck_id: str, deck_title: str, raw_units: List[str],
                            outdir: str, out_path: str, free_ratio: float) -> str:
    """
    --units で与えられた unit_id:title:csv_path の配列を処理して deck JSON を出力
    """
    units_json = []
    for spec in raw_units:
        if not spec.strip():
            continue
        try:
            unit_id, title, path = spec.split(":", 2)
        except ValueError:
            raise ValueError(f"--units の指定が不正です: {spec}")
        units_json.append(build_unit(unit_id.strip(), title.strip(), path.strip(), free_ratio))

    if not units_json:
        raise ValueError("units が空です。")

    deck_json = {
        "id": deck_id,
        "title": deck_title,
        "isPurchased": False,  # UI 側のロック表示互換
        "units": units_json,
    }

    if not out_path:
        os.makedirs(outdir, exist_ok=True)
        out_path = os.path.join(outdir, f"{deck_id}.json")

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(deck_json, f, ensure_ascii=False, indent=2)

    total_cards = sum(len(u["cards"]) for u in units_json)
    print(f"OK: {out_path} を出力しました。units={len(units_json)} / cards={total_cards}")
    return out_path


def convert_with_master(master_csv: str, deck_id: str,
                        outdir: str, out_path: str, free_ratio: float) -> str:
    """
    マスターCSV（deck_unit_master.csv）から deck_id の行を収集して deck JSON を出力
    期待カラム：
      deck_id, deck_title, unit_no, unit_id, unit_title, assets_deck_path, assets_src_csv, status
    """
    rows = read_csv_rows(master_csv)
    targets = [r for r in rows if r.get("deck_id") == deck_id]
    if not targets:
        raise ValueError(f"master に deck_id={deck_id} の行が見つかりません。")

    # 並び順：unit_no（数値）→ unit_id
    def _sort_key(r):
        try:
            no = int((r.get("unit_no") or "").strip())
        except Exception:
            no = 9999
        return (no, r.get("unit_id", ""))

    targets.sort(key=_sort_key)

    deck_title = targets[0].get("deck_title", deck_id)
    units_json = []
    chosen_out_path = out_path

    for r in targets:
        unit_id = r.get("unit_id", "").strip()
        unit_title = r.get("unit_title", "").strip()
        csv_path = r.get("assets_src_csv", "").strip()
        if not (unit_id and unit_title and csv_path):
            raise ValueError(f"master の行が不完全です: {r}")

        units_json.append(build_unit(unit_id, unit_title, csv_path, free_ratio))

        # 1行目に assets_deck_path があればそれを優先（なければ後で outdir/deck_id.json）
        if not chosen_out_path:
            p = r.get("assets_deck_path", "").strip()
            if p:
                chosen_out_path = p

    deck_json = {
        "id": deck_id,
        "title": deck_title,
        "isPurchased": False,
        "units": units_json,
    }

    if not chosen_out_path:
        os.makedirs(outdir, exist_ok=True)
        chosen_out_path = os.path.join(outdir, f"{deck_id}.json")

    os.makedirs(os.path.dirname(chosen_out_path), exist_ok=True)
    with open(chosen_out_path, "w", encoding="utf-8") as f:
        json.dump(deck_json, f, ensure_ascii=False, indent=2)

    total_cards = sum(len(u["cards"]) for u in units_json)
    print(f"OK: {chosen_out_path} を出力しました。units={len(units_json)} / cards={total_cards}")
    return chosen_out_path


# ---------- CLI ----------

def main():
    ap = argparse.ArgumentParser(description="CSV → JSON(Deck) 変換（deck → units → cards）")
    # モードA：--units で直接指定
    ap.add_argument("--units",
                    help="カンマ区切りで unit を列挙（unit_id:unit_title:csv_path,...）",
                    default="")
    # モードB：マスターCSVから収集
    ap.add_argument("--master",
                    help="deck_unit_master.csv のパス。--deck_id と併用し、この deck に属する unit を自動収集します。",
                    default="")

    # 共通
    ap.add_argument("--deck_id", required=True, help="deck の ID（例: deck_health01）")
    ap.add_argument("--deck_title", help="deck のタイトル（--units モードで必須、--master モードでは master 側を優先）")
    ap.add_argument("--outdir", default="assets/decks", help="出力先ディレクトリ（--out が無指定のとき使用）")
    ap.add_argument("--out", dest="out_path", default="", help="出力 JSON のフルパス（指定時は outdir を無視）")
    ap.add_argument("--free_ratio", type=float, default=0.2, help="無料割合（0.2=20%）")
    args = ap.parse_args()

    try:
        if args.master:
            # マスターCSVモード
            convert_with_master(args.master, args.deck_id, args.outdir, args.out_path, args.free_ratio)
        else:
            # 直接指定モード
            if not args.deck_title:
                raise ValueError("--units モードでは --deck_title を指定してください。")
            raw_units = [s.strip() for s in args.units.split(",")] if args.units else []
            if not raw_units:
                raise ValueError("--units が空です。unit_id:unit_title:csv_path をカンマ区切りで指定してください。")
            convert_with_units_list(args.deck_id, args.deck_title, raw_units, args.outdir, args.out_path, args.free_ratio)

    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
