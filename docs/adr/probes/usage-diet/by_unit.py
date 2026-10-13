"""傘・PR の単位で、役割別（実装・レビュー・司令官）のトークンと API 単価換算の費用を出す。

使い方（リポジトリのルートから。gh が使えること）:
    python3 -I docs/adr/probes/usage-diet/by_unit.py [<リポ>:]<傘ブランチ> [[<リポ>:]<傘ブランチ> ...]
    <リポ> は GitHub の owner/name（例 manemone/sheaf）。省略すると USAGE_BASE、それも無ければ cwd のリポ。
    複数の傘を渡すと並べて出す（運用を変える前後の比較は、前の傘と後の傘を渡す）。
    他のリポの傘は `manemone/sheaf:foo` のように書く（ローカルのリポのディレクトリ名は GitHub の name と同じとみなす）。
    USAGE_BASE  <リポ> を省いたときの既定のリポ（owner/name）。

PR の特定: 傘ブランチを向き先にした PR（gh pr list --base <傘>）の head ブランチを孫とみなし、
そのブランチ名のワークツリー（同じリポのもの）で動いたセッションを、その PR の費用とする。
傘ブランチ自身のワークツリーのセッションは「傘（司令官）」に積む。
役割: 孫 PR のセッションは、最初の指示（セッション間メッセージを含む）に「PRレビューを実行してください」が
あればレビュー、なければ実装。傘のセッションは司令官。
単価: Claude は role2.py と同じ（DOC-2610130216 §1）。DeepSeek は bin/prices/deepseek-*.json の最新。
どちらでもないモデルは費用に入れず、末尾に警告する。サブエージェントのログは含めない。
ログ（~/.claude/projects）は約30日で消えるので、古い傘は欠ける。欠けた PR は「ログなし」と出す。
"""
import collections
import glob
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PRICES = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "bin", "prices"))
CLAUDE = {"opus": (4, 20, 0.20, 5, 8), "sonnet": (2, 10, 0.20, 2.5, 4), "haiku": (0.10, 0.50, 0.01, 0.125, 0.20)}
ROLES = ["実装", "レビュー", "司令官"]
REVIEW_MARK = "PRレビューを実行してください"


def deepseek_prices():
    files = sorted(glob.glob(os.path.join(PRICES, "deepseek-*.json")))
    return json.load(open(files[-1]))["models"] if files else {}


DS = deepseek_prices()


def usage_cost(model, u):
    """(費用 $, 読み, 書き込み, 出力, 入力) を返す。単価不明は費用 None。"""
    rd, out, inp = u.get("cache_read_input_tokens", 0), u.get("output_tokens", 0), u.get("input_tokens", 0)
    cc = u.get("cache_creation") or {}
    w1, w5 = cc.get("ephemeral_1h_input_tokens", 0), cc.get("ephemeral_5m_input_tokens", 0)
    if not cc:
        w5 = u.get("cache_creation_input_tokens", 0)
    toks = (rd, w1 + w5, out, inp)
    key = next((k for k in CLAUDE if k in model), None)
    if key:
        pi, po, pr, p5, p1 = CLAUDE[key]
        return ((pi * inp + po * out + pr * rd + p5 * w5 + p1 * w1) / 1e6, *toks)
    if model in DS:
        p = DS[model]
        return ((p["cache_hit_in"] * rd + p["cache_miss_in"] * (inp + w1 + w5) + p["out"] * out) / 1e6, *toks)
    return (None, *toks)


def split_proj(proj, repos):
    p = re.sub(r"^.*?-projects-", "", proj, count=1)
    for r in sorted(repos, key=len, reverse=True):
        if p.startswith(r + "-"):
            return r, p[len(r) + 1:]
    return "?", p


def read_session(path):
    head, msgs = [], {}
    for line in open(path, errors="ignore"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("type") == "user" and len(head) < 6:
            c = d["message"].get("content")
            if isinstance(c, list):
                c = " ".join(x.get("text", "") for x in c if isinstance(x, dict))
            if c and not c.startswith("<local-command") and "command-name>" not in c:
                head.append(c)
        m = d.get("message", {}) if d.get("type") == "assistant" else {}
        if m.get("id"):
            msgs[m["id"]] = (m.get("model") or "", m.get("usage") or {})
    return head, msgs


def gh(args, repo):
    cmd = ["gh", *args] + (["-R", repo] if repo else [])
    return json.loads(subprocess.run(cmd, capture_output=True, text=True, check=True).stdout)


def parse_arg(a):
    repo, _, um = a.rpartition(":")
    repo = repo or os.environ.get("USAGE_BASE") or ""
    if not repo:
        repo = gh(["repo", "view", "--json", "nameWithOwner"], None)["nameWithOwner"]
    return repo, um


def collect(targets):
    prs = {t: {pr["headRefName"]: pr["number"] for pr in gh(
        ["pr", "list", "--base", t[1], "--state", "all", "--limit", "200", "--json", "number,headRefName"], t[0])}
        for t in targets}
    repos = {t[0].split("/")[-1] for t in targets} | {r for r in os.environ.get("USAGE_REPOS", "").split(",") if r}
    wanted = {}
    for t in targets:
        name = t[0].split("/")[-1]
        wanted[(name, t[1])] = (t, None)
        for br, num in prs[t].items():
            wanted[(name, br)] = (t, num)
    # res[傘][単位] = {役割: [費用, 読み, 書き込み, 出力, 入力]}
    res = {t: collections.defaultdict(lambda: collections.defaultdict(lambda: [0.0, 0, 0, 0, 0])) for t in targets}
    unknown = collections.Counter()
    for f in glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl")):
        proj = f.split("/projects/")[1].split("/")[0]
        key = split_proj(proj, repos)
        if key not in wanted:
            continue
        t, num = wanted[key]
        head, msgs = read_session(f)
        if not msgs:
            continue
        if num is None:
            role, unit = "司令官", "傘"
        else:
            role = "レビュー" if REVIEW_MARK in "".join(head[:1]) else "実装"
            unit = "#%d %s" % (num, key[1])
        for model, u in msgs.values():
            if model.startswith("<"):
                continue
            cost, rd, wr, out, inp = usage_cost(model, u)
            row = res[t][unit][role]
            if cost is None:
                unknown[model] += 1
            else:
                row[0] += cost
            for i, v in enumerate((rd, wr, out, inp), 1):
                row[i] += v
    return res, prs, unknown


def m(n):
    return "%.1f" % (n / 1e6)


def main(args):
    targets = [parse_arg(a) for a in args]
    res, prs, unknown = collect(targets)
    for t in targets:
        r = res[t]
        print("== 傘 %s（%s）" % (t[1], t[0]))
        print("費用 $ / トークン(百万)  [計 = 読み+書き込み+出力+入力]")
        print("%-40s %s" % ("単位", " ".join("%-18s" % x for x in ROLES) + " 計 $"))
        tot = {x: [0.0, 0, 0, 0, 0] for x in ROLES}
        have = 0
        for unit in ["傘"] + ["#%d %s" % (n, b) for b, n in sorted(prs[t].items(), key=lambda x: x[1])]:
            if unit not in r:
                print("%-40s (ログなし)" % unit)
                continue
            if unit != "傘":
                have += 1
            cells, s = [], 0.0
            for x in ROLES:
                v = r[unit].get(x, [0.0, 0, 0, 0, 0])
                cells.append("%-18s" % ("%.0f / %sM" % (v[0], m(sum(v[1:])))))
                s += v[0]
                tot[x] = [a + b for a, b in zip(tot[x], v)]
            print("%-40s %s %.0f" % (unit, " ".join(cells), s))
        print("%-40s %s %.0f" % ("合計", " ".join("%-18s" % ("%.0f / %sM" % (tot[x][0], m(sum(tot[x][1:])))) for x in ROLES), sum(tot[x][0] for x in ROLES)))
        print("内訳(百万) " + "  ".join("%s: 読み%s 書き%s 出力%s 入力%s" % (x, *(m(v) for v in tot[x][1:])) for x in ROLES))
        if have:
            pr_units = [u for u in r if u != "傘"]
            avg = [sum(r[u].get(x, [0])[0] for u in pr_units) / have for x in ROLES]
            print("PR 1本あたり $（ログのあった %d/%d 本）: %s 計 %.1f" % (
                have, len(prs[t]), " ".join("%s %.1f" % (x, a) for x, a in zip(ROLES, avg)), sum(avg)))
        if have < len(prs[t]):
            print("注意: %d 本の PR はログが残っていない（約30日で消える）。比較の基準にはしない" % (len(prs[t]) - have))
        print()
    if unknown:
        print("警告: 単価が分からないモデルのコールは費用に入れていない: " + ", ".join("%s×%d" % kv for kv in unknown.items()))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
