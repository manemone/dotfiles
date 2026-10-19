"""derived/labels/*.json（指摘ごとのラベル）と prs_attr.json から、結果の表を Markdown で出す。

使い方: REVIEW_DATA=<生データ> python3 aggregate.py [population|sample|kappa|umbrella|all]
repeat=true の指摘は集計から除く。
"""
import json, os, sys, glob
from collections import Counter, defaultdict
from common import *

CATS = ["A", "B", "C", "D1", "D2"]
KINDS = [("docs", "文書だけ"), ("foundation", "土台"), ("small", "小さい"), ("code", "実装コード")]
GROUPS = ["Sonnet", "Opus", "弱いモデル(DeepSeek/Qwen/Kimi)", "その他(Fable/GPT)", "不明"]
sel = sys.argv[1] if len(sys.argv) > 1 else "all"

prs = {f'{p["repo"]}#{p["n"]}': p for p in json.load(open(os.path.join(DERIVED, "prs_attr.json")))}
for k, p in prs.items():
    p["grp"] = model_group(p["impl"])


def load_labels(d="labels"):
    out = {}
    for f in sorted(glob.glob(os.path.join(DERIVED, d, "*.json"))):
        j = json.load(open(f))
        out[pr_key(j["id"])] = j
    return out


def pct(a, b):
    return "%.0f%%" % (100 * a / b) if b else "-"


def table(head, rows):
    print("| " + " | ".join(head) + " |")
    print("|" + "---|" * len(head))
    for r in rows:
        print("| " + " | ".join(str(x) for x in r) + " |")
    print()


def pr_key(label_id):
    # ラベルの id は「<リポ>-<番号>」。リポ名にハイフンを含むので最後のハイフンで分ける
    repo, n = label_id.rsplit("-", 1)
    return f"{repo}#{n}"


def population():
    print("### 母集団（孫 PR 全数）\n")
    pop = list(prs.values())
    rows = []
    for key, name in KINDS:
        v = [p for p in pop if p["prekind"] == key]
        rows.append([name + "（仮判定）", len(v), pct(sum(p["rows_find"] == 0 for p in v), len(v)),
                     "%.2f" % (sum(p["rows_find"] for p in v) / len(v)) if v else "-"])
    table(["PR の種類", "PR 数", "指摘なしで承認", "指摘ラウンド数の平均"], rows)
    rows = []
    for g in GROUPS:
        v = [p for p in pop if p["grp"] == g]
        rows.append([g, len(v), pct(sum(p["rows_find"] == 0 for p in v), len(v)),
                     "%.2f" % (sum(p["rows_find"] for p in v) / len(v)) if v else "-"])
    table(["実装役のモデル", "PR 数", "指摘なしで承認", "指摘ラウンド数の平均"], rows)
    print("実装役の判明元:", dict(Counter(p["impl_src"] for p in pop)),
          "／不明の割合 %s\n" % pct(sum(p["impl"] == "不明" for p in pop), len(pop)))
    print("モデル系統の内訳:", dict(Counter(p["impl"] for p in pop)), "\n")


def sample():
    L = load_labels()
    print(f"### 抜き取り分（ラベル付き PR {len(L)} 本）\n")
    fl = []  # (kind, grp, cat, spill, resolution, pr)
    for k, j in L.items():
        p = prs[k]
        for f in j["findings"]:
            if f.get("repeat"):
                continue
            fl.append((j["kind"], p["grp"], f["cat"], bool(f.get("spill")), f.get("resolution"), k))
    print(f"指摘の総数（再掲を除く）: {len(fl)}\n")
    for title, idx, labs in (("PR の種類別", 0, [k for k, _ in KINDS]), ("実装役のモデル別", 1, GROUPS)):
        rows = []
        for lab in labs:
            sub = [f for f in fl if f[idx] == lab]
            prset = {f[5] for f in sub}
            n_pr = sum(1 for j in L.values() if (j["kind"] if idx == 0 else prs[pr_key(j["id"])]["grp"]) == lab)
            ab = len({f[5] for f in sub if f[2] in ("A", "B")})
            a = len({f[5] for f in sub if f[2] == "A"})
            c = Counter(f[2] for f in sub)
            name = dict(KINDS).get(lab, lab)
            rows.append([name, n_pr, len(sub)] + [f"{c[x]} ({pct(c[x], len(sub))})" for x in CATS]
                        + [f"{a} ({pct(a, n_pr)})", f"{ab} ({pct(ab, n_pr)})"])
        print(f"#### {title}\n")
        table(["区分", "PR 数", "指摘数"] + CATS + ["A を含む PR", "A/B を含む PR"], rows)
    c = Counter(f[2] for f in fl)
    print("#### 全体\n")
    table(["区分", "指摘数", "割合", "うち後続の孫に波及", "波及の割合"],
          [[x, c[x], pct(c[x], len(fl)), sum(1 for f in fl if f[2] == x and f[3]),
            pct(sum(1 for f in fl if f[2] == x and f[3]), c[x])] for x in CATS]
          + [["計", len(fl), "", sum(1 for f in fl if f[3]), pct(sum(1 for f in fl if f[3]), len(fl))]])
    rc = Counter((f[2], f[4]) for f in fl)
    print("#### 指摘への対応の結末（resolution）\n")
    table(["区分", "直した", "実装者が反論・見送り", "判定不能"],
          [[x, rc[(x, "fixed")], rc[(x, "declined")], rc[(x, "unknown")]] for x in CATS]
          + [["計", sum(v for (c_, r), v in rc.items() if r == "fixed"),
              sum(v for (c_, r), v in rc.items() if r == "declined"),
              sum(v for (c_, r), v in rc.items() if r == "unknown")]])
    ab_only = [j for j in L.values() if not any((not f.get("repeat")) and f["cat"] in ("A", "B", "C") for f in j["findings"])]
    print(f"A/B/C を1件も含まない PR（指摘は D1/D2 だけ、または無し）: {len(ab_only)} / {len(L)} ({pct(len(ab_only), len(L))})\n")
    # 仮判定との一致
    cm = Counter((prs[pr_key(j['id'])]['prekind'], j['kind']) for j in L.values())
    print("#### 仮判定（題名と行数）と最終判定の突き合わせ\n")
    table(["仮判定＼最終"] + [n for _, n in KINDS],
          [[n0] + [cm[(k0, k1)] for k1, _ in KINDS] for k0, n0 in KINDS])


def kappa():
    A, B = load_labels("labels"), load_labels("labels2")
    ids = sorted(set(A) & set(B))
    tot = same = 0
    pairs = Counter()
    kind_same = 0
    for i in ids:
        fa = {(f["round"], f["idx"]): f["cat"] for f in A[i]["findings"] if not f.get("repeat")}
        fb = {(f["round"], f["idx"]): f["cat"] for f in B[i]["findings"] if not f.get("repeat")}
        kind_same += A[i]["kind"] == B[i]["kind"]
        for k in set(fa) | set(fb):
            tot += 1
            a, b = fa.get(k, "欠"), fb.get(k, "欠")
            same += a == b
            pairs[tuple(sorted((a, b)))] += 1
    print(f"### 基準ぶれ（同じ {len(ids)} 本を別々に2回分類）\n")
    print(f"指摘 {tot} 件のうちカテゴリ一致 {same} 件（{pct(same, tot)}）。PR の種類の一致 {kind_same}/{len(ids)}。\n")
    ab = lambda c: "A/B" if c in ("A", "B") else c
    s2 = sum(1 for _ in [0])
    table(["組み合わせ", "件数"], [[" / ".join(k), v] for k, v in pairs.most_common() if k[0] != k[1]])


def umbrella():
    L = load_labels()
    print("### 再現実験の対象の傘\n")
    rows = []
    for n, u in enumerate(umbrellas(), 1):
        repo, base = u.split("/", 1)
        ps = [p for p in prs.values() if p["repo"] == repo and p["base"] == base]
        fl = []
        for p in ps:
            j = L.get(f'{p["repo"]}#{p["n"]}')
            if j:
                fl += [f for f in j["findings"] if not f.get("repeat")]
        c = Counter(f["cat"] for f in fl)
        rows.append([f"傘{n}", len(ps), dict(Counter(p["impl"] for p in ps)),
                     sum(p["rows_find"] for p in ps), len(fl), " ".join(f"{x}:{c[x]}" for x in CATS)])
    table(["傘（リポ・ベースは非公開のため通し番号）", "孫 PR 数", "実装役", "指摘ラウンド", "指摘数", "内訳"], rows)


for name, fn in (("population", population), ("sample", sample), ("kappa", kappa), ("umbrella", umbrella)):
    if sel in (name, "all"):
        fn()
