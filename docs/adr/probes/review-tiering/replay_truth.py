"""再現実験の正解データ（傘ごと）を作る（使い捨て）。孫1 の labels（A/B/C、再掲を除く）から、
傘に属する孫 PR の指摘を並べる。レビュー前の head が取れず最終版で埋めた孫の指摘は、取りこぼしの判定から外す（excluded）。
出力は derived/replay/truth/u<N>.json（PRIVATE の中身を含むのでリポの外）。環境変数: REVIEW_DATA"""
import json, os
from common import DERIVED, umbrellas

OUT = os.path.join(DERIVED, "replay", "truth")
os.makedirs(OUT, exist_ok=True)
for i, u in enumerate(umbrellas(), 1):
    meta = json.load(open(os.path.join(DERIVED, "replay", f"umbrella{i}.json")))
    repo = meta["repo"]
    items, excl_prs = [], []
    # ブランチに当たらなかった孫（傘の履歴に無かった等）は取りこぼしの判定から外す。REPLAY_SCRATCH は replay_build.sh の親ディレクトリ
    not_applied = set()
    all_filled, part_filled = set(), set()  # 全ファイルをマージ後の版で埋めた孫 / 一部だけ埋めた孫
    logp = os.path.join(os.environ.get("REPLAY_SCRATCH", ""), f"u{i}.build.log")
    if os.path.exists(logp):
        for line in open(logp):
            if "NOT-APPLIED" in line:
                not_applied.add(int(line.split("\t")[0][2:]))
            elif "\tconflict:" in line and "total_files=" in line:
                cols = line.rstrip("\n").split("\t")
                pr = int(cols[0][2:])
                filled = int(cols[1].split(":")[1].removesuffix("files"))
                total = int(cols[3].split("=")[1])
                (all_filled if filled >= total else part_filled).add(pr)
    for p in meta["prs"]:
        lp = os.path.join(DERIVED, "labels", f"{repo}-{p['n']}.json")
        if not os.path.exists(lp):
            continue
        # レビュー前 head が取れず最終版で埋めた孫、ブランチに当たらなかった孫、全ファイルをマージ後の版で埋めた孫は、
        # 欠陥が replay ブランチに無い（直った後のコードをレビューさせている）ので判定から外す
        fills = p["pre_review_head"] is None or p["n"] in not_applied or p["n"] in all_filled
        if fills:
            excl_prs.append(p["n"])
        # 一部だけ埋めた孫は、ラベルにファイルの情報が無いのでファイル単位では外せない（part_filled で感度分析する）
        for f in json.load(open(lp))["findings"]:
            if f.get("repeat") or f["cat"] not in ("A", "B", "C"):
                continue
            items.append({"gid": f"{p['n']}-{f['round']}-{f['idx']}", "pr": p["n"], "cat": f["cat"],
                          "spill": f.get("spill"), "note": f.get("note", ""), "excluded": fills,
                          "part_filled": p["n"] in part_filled})
    json.dump({"umbrella": i, "excluded_prs": excl_prs, "findings": items}, open(os.path.join(OUT, f"u{i}.json"), "w"),
              ensure_ascii=False, indent=1)
    n_ok = [x for x in items if not x["excluded"]]
    print(f"傘{i}: 正解 {len(n_ok)}件（A {sum(x['cat']=='A' for x in n_ok)} B {sum(x['cat']=='B' for x in n_ok)} C {sum(x['cat']=='C' for x in n_ok)}）, 除外 {len(items)-len(n_ok)}件 PR={excl_prs}")
