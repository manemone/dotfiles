"""再現実験の集計（使い捨て）。derived/replay/{truth,match}/ を読み、傘別・レビュアーのモデル別・種類別の拾えた割合を標準出力へ。
excluded（レビュー前 head が取れず最終版で埋めた孫、ブランチに当たらなかった孫）の正解は分母から外す。環境変数: REVIEW_DATA"""
import json, os, glob, collections
from common import DERIVED

R = os.path.join(DERIVED, "replay")
# 傘の実装役（孫1 の文書 §5.4。傘1 は DeepSeek を1本含む混在、傘2 は Qwen が主）
IMPL = {1: "混在(DeepSeek含む)", 2: "Qwen", 3: "Sonnet", 4: "Sonnet", 5: "Sonnet"}


def load():
    rows = []
    for mp in sorted(glob.glob(os.path.join(R, "match", "u*-*-r*.json"))):
        name = os.path.basename(mp)[:-5]
        u, model, run = name.split("-")
        un = int(u[1:])
        truth = {f["gid"]: f for f in json.load(open(os.path.join(R, "truth", f"{u}.json")))["findings"]}
        m = json.load(open(mp))
        rows.append((un, model, run, truth, m))
    return rows


def pct(a, b):
    return f"{a}/{b} ({100*a//b}%)" if b else "-"


def tally(rows, key, cats=("A", "B", "C")):
    agg = collections.defaultdict(lambda: collections.Counter())
    for un, model, run, truth, m in rows:
        for v in m["truth"]:
            t = truth.get(v["gid"])
            if not t or t["excluded"] or t["cat"] not in cats:
                continue
            k = key(un, model, t)
            agg[k]["n"] += 1
            agg[k][v["verdict"]] += 1
    return agg


def show(title, agg):
    print(f"\n### {title}\n\n| 区分 | 正解数(のべ) | hit | hit+partial |\n|---|---|---|---|")
    for k in sorted(agg, key=str):
        c = agg[k]
        print(f"| {k} | {c['n']} | {pct(c['hit'], c['n'])} | {pct(c['hit'] + c['partial'], c['n'])} |")


rows = load()
print(f"レビュー結果 {len(rows)} 本")
show("傘別", tally(rows, lambda u, mo, t: f"傘{u}（実装役 {IMPL[u]}）"))
show("レビュアーのモデル別", tally(rows, lambda u, mo, t: mo))
show("傘×レビュアーのモデル", tally(rows, lambda u, mo, t: f"傘{u} {mo}"))
show("元の実装役別", tally(rows, lambda u, mo, t: IMPL[u]))
show("指摘の種類別", tally(rows, lambda u, mo, t: t["cat"]))
show("後続の孫へ波及する指摘（spill）", tally(rows, lambda u, mo, t: f"spill={bool(t.get('spill'))}"))
show("指摘が出たラウンド（gid の2番目）", tally(rows, lambda u, mo, t: "1回目のレビュー" if t["gid"].split("-")[1] == "1" else "2回目以降（修正の差分への指摘を含む）"))
show("種類×モデル", tally(rows, lambda u, mo, t: f"{t['cat']} {mo}"))

# 2回の走りの一致（ばらつき）: 同じ傘・モデルで gid ごとに run1/run2 の hit が一致した割合
print("\n### 2回の走りのばらつき（hit の有無が run1/run2 で一致した正解の割合）\n")
by = collections.defaultdict(dict)
for un, model, run, truth, m in rows:
    by[(un, model)][run] = {v["gid"]: v["verdict"] == "hit" for v in m["truth"] if not truth[v["gid"]]["excluded"]}
for (un, model), d in sorted(by.items()):
    if "r1" in d and "r2" in d:
        g = d["r1"].keys() & d["r2"].keys()
        same = sum(d["r1"][x] == d["r2"][x] for x in g)
        either = sum(d["r1"][x] or d["r2"][x] for x in g)
        print(f"- 傘{un} {model}: 一致 {pct(same, len(g))}、どちらかで hit {either} 件")

print("\n### 最終レビューだけが見つけた新しい指摘（正解に無いもの）\n\n| 傘・モデル・回 | finding 総数 | 新規 A | 新規 B | 新規 C | 新規 D | うち人工物の疑い |\n|---|---|---|---|---|---|---|")
tot = collections.Counter()
for un, model, run, truth, m in rows:
    c = collections.Counter(x["kind"] for x in m["new"])
    art = sum(1 for x in m["new"] if x.get("artifact"))
    print(f"| 傘{un} {model} {run} | {m['review_finding_count']} | {c['new_A']} | {c['new_B']} | {c['new_C']} | {c['new_D']} | {art} |")
    tot.update(c); tot["art"] += art; tot["n"] += m["review_finding_count"]
print(f"| 合計 | {tot['n']} | {tot['new_A']} | {tot['new_B']} | {tot['new_C']} | {tot['new_D']} | {tot['art']} |")

# 正解のうち、どの走りでも hit にならなかったもの（傘別の件数）
print("\n### 全部の走りで拾えなかった正解（hit が 0 回）\n")
cnt = collections.defaultdict(lambda: collections.Counter())
seen = collections.defaultdict(set)
for un, model, run, truth, m in rows:
    for v in m["truth"]:
        t = truth[v["gid"]]
        if t["excluded"]:
            continue
        seen[(un, v["gid"])].add(t["cat"])
        if v["verdict"] == "hit":
            cnt[un][v["gid"]] += 1
for un in sorted({k[0] for k in seen}):
    gids = [g for (u, g) in seen if u == un]
    miss = [g for g in gids if cnt[un][g] == 0]
    cats = collections.Counter(next(iter(seen[(un, g)])) for g in miss)
    print(f"- 傘{un}: 正解 {len(gids)} 件のうち {len(miss)} 件が全部の走りで hit なし（A {cats['A']} B {cats['B']} C {cats['C']}）")
