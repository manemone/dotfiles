"""抜き取った PR ごとに、分類担当へ渡す入力（derived/inputs/<リポ>-<番号>.md）を作る。
実装役のモデルは入力に含めない（分類が実装役のモデルの先入観を受けないようにする）。
対応報告は長いので先頭 REPORT_MAX 文字に切る。
"""
import json, os
from common import *

REVIEW_MAX, REPORT_MAX = 7000, 1800
ids = json.load(open(os.path.join(DERIVED, "sample_ids.json")))["ids"]
prs = {f'{p["repo"]}#{p["n"]}': p for p in json.load(open(os.path.join(DERIVED, "prs_attr.json")))}
d = os.path.join(DERIVED, "inputs")
os.makedirs(d, exist_ok=True)


def strip_header_model(body):
    """見出し行のモデル名を伏せる"""
    head, _, rest = body.partition("\n")
    return head.split("[")[0].strip() + "\n" + rest


for i in ids:
    p = prs[i]
    pr = load_pr(p["repo"], p["n"])
    lines = [f'# {i}', f'題名: {p["title"]}', f'変更行数: {p["size"]}', f'base: {p["base"]}  head: {p["head"]}', ""]
    for ts, body in events(pr):
        if REVIEW_RE.match(body):
            kind, mx = "レビュー指摘", REVIEW_MAX
        elif APPROVE_RE.match(body):
            kind, mx = "承認", 600
        elif REPORT_RE.match(body):
            kind, mx = "対応報告", REPORT_MAX
        else:
            continue
        b = strip_header_model(body)
        if len(b) > mx:
            b = b[:mx] + "\n…（切り詰め）"
        lines += [f"## [{ts}] {kind}", b, ""]
    open(os.path.join(d, i.replace("#", "-") + ".md"), "w").write("\n".join(lines))
print(len(ids), "件 →", d)
