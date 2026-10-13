"""prs.json に実装役のモデル（impl）と、層化用の仮の PR 種類（prekind）を付けて
derived/prs_attr.json に書く。

impl: 対応報告の見出し > コミットの Co-Authored-By > 不明。複数系統なら『混在』。
prekind は題名と行数だけの粗い仮判定（抜き取りの層を作るためだけに使う）。
最終的な PR の種類は分類担当が差分の概要から付ける（基準は結果の文書）。
"""
import json, os, re
from collections import Counter
from common import *

DOC_RE = re.compile(r"^(docs?|doc)[:(：]|ADR|計画書|文書|README|調査|記録|設計(書|メモ)|方針|索引", re.I)
FOUNDATION_RE = re.compile(r"土台|基盤|骨格|雛形|スキーマ|foundation|scaffold|skeleton|契約|共通|base\b|infra", re.I)

prs = json.load(open(os.path.join(DERIVED, "prs.json")))
tr = json.load(open(os.path.join(DERIVED, "trailers.json")))
for p in prs:
    impl, src = None, None
    if p["implementer_report"]:
        fam = set(p["implementer_report"])
        src = "report"
    else:
        t = tr.get(f'{p["repo"]}#{p["n"]}', {})
        fam = {normalize_model(x) for x in t.get("coauthors", [])} - {"不明"}
        src = "trailer"
    if not fam:
        impl, src = "不明", "none"
    elif len(fam) == 1:
        impl = next(iter(fam))
    else:
        impl = "混在"
    p["impl"], p["impl_src"] = impl, src
    t = p["title"]
    if DOC_RE.search(t):
        p["prekind"] = "docs"
    elif FOUNDATION_RE.search(t):
        p["prekind"] = "foundation"
    elif p["size"] <= 100:
        p["prekind"] = "small"
    else:
        p["prekind"] = "code"
json.dump(prs, open(os.path.join(DERIVED, "prs_attr.json"), "w"), ensure_ascii=False, indent=1)
print("impl:", Counter(p["impl"] for p in prs).most_common())
print("src:", Counter(p["impl_src"] for p in prs).most_common())
print("prekind:", Counter(p["prekind"] for p in prs).most_common())
print("不明の割合: %.1f%%" % (100 * sum(p["impl"] == "不明" for p in prs) / len(prs)))
