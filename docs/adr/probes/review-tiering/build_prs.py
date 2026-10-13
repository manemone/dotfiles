"""rows.json と pr/*.json から、孫 PR ごとの属性表（derived/prs.json）を作る。

実装役のモデル = 『🤖💬 対応報告』コメントの見出しの [モデル | 努力量]。
対応報告が無い PR（1回目で承認・指摘なし）は、後から fetch_trailers.py で
コミットの Co-Authored-By から補う（trailer_model）。
"""
import json, os
from common import *

out = []
for r in load_rows():
    pr = load_pr(r["repo"], r["n"])
    ev = events(pr)
    reviews = [b for _, b in ev if REVIEW_RE.match(b)]
    approvals = [b for _, b in ev if APPROVE_RE.match(b)]
    reports = [b for _, b in ev if REPORT_RE.match(b)]
    impl = sorted({normalize_model(header_model(b)) for b in reports} - {"不明"})
    rev = sorted({normalize_model(header_model(b)) for b in reviews + approvals} - {"不明"})
    out.append({
        "repo": r["repo"], "n": r["n"], "base": r["base"], "head": r["head"],
        "title": r["title"], "size": r["size"],
        "rounds_with_findings": len(reviews), "approvals": len(approvals),
        "reports": len(reports), "rows_find": r["find"],
        "implementer_report": impl, "reviewer": rev,
    })
json.dump(out, open(os.path.join(DERIVED, "prs.json"), "w"), ensure_ascii=False, indent=1)
print(len(out), "PR →", os.path.join(DERIVED, "prs.json"))
