"""層化抜き取り。層 = 仮の PR 種類 × 実装役のモデル群。指摘のあった PR（rounds_with_findings>=1）
から取る。再現実験の対象の傘（環境変数 REVIEW_UMBRELLAS=リポ/ベース,...）の孫 PR は全数入れる。
乱数は固定シード。結果は derived/sample_ids.json。
"""
import json, os, random
from collections import defaultdict, Counter
from common import *

TARGET = int(os.environ.get("REVIEW_SAMPLE_TARGET", "150"))
MIN_PER_CELL = 3
GROUP = {"Sonnet": "Sonnet", "Opus": "Opus", "不明": "不明", "混在": "不明"}

prs = json.load(open(os.path.join(DERIVED, "prs_attr.json")))
umb = {tuple(u.split("/", 1)) for u in os.environ.get("REVIEW_UMBRELLAS", "").split(",") if u}
for p in prs:
    p["grp"] = GROUP.get(p["impl"], "その他(弱いモデル等)")
    p["id"] = f'{p["repo"]}#{p["n"]}'
pool = [p for p in prs if p["rounds_with_findings"] >= 1]
forced = [p for p in pool if (p["repo"], p["base"]) in umb]
rest = [p for p in pool if (p["repo"], p["base"]) not in umb]
cells = defaultdict(list)
for p in rest:
    cells[(p["prekind"], p["grp"])].append(p)
budget = max(TARGET - len(forced), 0)
rng = random.Random(20261014)
picked = []
alloc = {}
for k, v in sorted(cells.items()):
    n = min(len(v), max(MIN_PER_CELL, round(budget * len(v) / len(rest))))
    alloc[k] = (len(v), n)
    picked += rng.sample(v, n)
ids = sorted({p["id"] for p in forced + picked})
json.dump({"ids": ids, "forced": sorted(p["id"] for p in forced),
           "alloc": {f"{k[0]}|{k[1]}": v for k, v in alloc.items()}},
          open(os.path.join(DERIVED, "sample_ids.json"), "w"), ensure_ascii=False, indent=1)
print("合計", len(ids), "（傘の全数", len(forced), "＋層から", len(picked), "）")
for k, (tot, n) in sorted(alloc.items()):
    print(f"{k[0]:10s} {k[1]:20s} 母数{tot:4d} 抜取{n:3d}")
