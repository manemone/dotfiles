"""傘・PR の単位で、役割別（実装・レビュー・司令官）の API 単価換算の費用を出す。

使い方（リポジトリのルートから。gh が使えること）:
    python3 -I docs/adr/probes/usage-diet/by_unit.py <傘ブランチ> [<傘ブランチ> ...]
複数の傘を渡すと並べて出す（運用を変える前後の比較は、前の傘と後の傘を渡す）。
    USAGE_REPOS  役割の分類に使うリポ名（ワークツリーのディレクトリ名の先頭）。既定 dotfiles
    USAGE_BASE   PR の向き先を探すリポ（gh の -R に渡す）。既定は cwd のリポ

PR の特定: 傘ブランチを向き先にした PR（gh pr list --base <傘>）の head ブランチを孫とみなし、
そのブランチ名のワークツリーで動いたセッションを、その PR の費用とする。傘ブランチ自身の
ワークツリーのセッションは「傘（司令官）」に積む。分類は role.py の classify と同じ。
単価は role2.py と同じ（DOC-2610130216 §1）。サブエージェントのログは含めない。
"""
import collections
import datetime
import glob
import json
import os
import re
import subprocess
import sys

REPOS = [r for r in os.environ.get("USAGE_REPOS", "dotfiles").split(",") if r]
P = {"opus": (4, 20, 0.20, 5, 8), "sonnet": (2, 10, 0.20, 2.5, 4), "haiku": (0.10, 0.50, 0.01, 0.125, 0.20)}


def split_proj(proj):
    p = re.sub(r"^.*?-projects-", "", proj, count=1)
    for r in REPOS:
        if p.startswith(r + "-"):
            return r, p[len(r) + 1:]
    return "?", p


def classify(branch, texts):
    if any("PRレビューを実行してください" in t for t in texts[:2]):
        return "レビュー"
    if branch in ("master", "main"):
        return "会話"
    if re.match(r"^[a-z0-9]+-\d\d-", branch) or any("孫" in t and "プロンプ" in t for t in texts[:2]):
        return "実装"
    return "司令官"


def call_cost(model, u):
    key = "opus" if "opus" in model else ("sonnet" if "sonnet" in model else "haiku")
    pi, po, pr, p5, p1 = P[key]
    cc = u.get("cache_creation") or {}
    w1, w5 = cc.get("ephemeral_1h_input_tokens", 0), cc.get("ephemeral_5m_input_tokens", 0)
    if not cc:
        w5 = u.get("cache_creation_input_tokens", 0)
    return (pi * u.get("input_tokens", 0) + po * u.get("output_tokens", 0)
            + pr * u.get("cache_read_input_tokens", 0) + p5 * w5 + p1 * w1) / 1e6


def read_session(path):
    texts, msgs = [], {}
    for line in open(path, errors="ignore"):
        try:
            d = json.loads(line)
        except ValueError:
            continue
        if d.get("type") == "user" and not d.get("isMeta") and len(texts) < 3:
            c = d["message"].get("content")
            if isinstance(c, list):
                c = " ".join(x.get("text", "") for x in c if isinstance(x, dict))
            if c and not c.startswith("<local-command") and "command-name>" not in c and not c.startswith("<task-notification"):
                texts.append(c)
        m = d.get("message", {}) if d.get("type") == "assistant" else {}
        if m.get("id"):
            msgs[m["id"]] = (m.get("model") or "", m.get("usage") or {})
    return texts, msgs


def grandchildren(umbrella):
    cmd = ["gh", "pr", "list", "--base", umbrella, "--state", "all", "--limit", "200", "--json", "number,headRefName"]
    if os.environ.get("USAGE_BASE"):
        cmd += ["-R", os.environ["USAGE_BASE"]]
    out = json.loads(subprocess.run(cmd, capture_output=True, text=True, check=True).stdout)
    return {pr["headRefName"]: pr["number"] for pr in out}


def collect(umbrellas):
    """{傘: {単位(傘 or PR番号): {役割: 費用}}}"""
    wanted = {}
    for um in umbrellas:
        wanted[um] = (um, None)
        for br, num in grandchildren(um).items():
            wanted[br] = (um, num)
    res = {um: collections.defaultdict(lambda: collections.defaultdict(float)) for um in umbrellas}
    calls = collections.Counter()
    for f in glob.glob(os.path.expanduser("~/.claude/projects/*/*.jsonl")):
        proj = f.split("/projects/")[1].split("/")[0]
        _, br = split_proj(proj)
        if br not in wanted:
            continue
        um, num = wanted[br]
        texts, msgs = read_session(f)
        if not msgs:
            continue
        role = classify(br, texts)
        unit = "傘" if num is None else "#%d %s" % (num, br)
        for model, u in msgs.values():
            res[um][unit][role] += call_cost(model, u)
            calls[um] += 1
    return res, calls


def main(umbrellas):
    res, calls = collect(umbrellas)
    roles = ["実装", "レビュー", "司令官"]
    for um in umbrellas:
        print("== 傘 %s（%d コール）" % (um, calls[um]))
        print("%-44s %8s %8s %8s %8s" % ("単位", *roles, "計"))
        tot = collections.Counter()
        prs = [k for k in res[um] if k != "傘"]
        for unit in ["傘"] + sorted(prs):
            row = res[um].get(unit, {})
            print("%-44s %8.0f %8.0f %8.0f %8.0f" % (unit, *(row.get(r, 0) for r in roles), sum(row.get(r, 0) for r in roles)))
            for r in roles:
                tot[r] += row.get(r, 0)
        print("%-44s %8.0f %8.0f %8.0f %8.0f" % ("合計 $", *(tot[r] for r in roles), sum(tot[r] for r in roles)))
        if prs:
            n = len(prs)
            print("%-44s %8.1f %8.1f %8.1f %8.1f" % ("PR 1本あたり $（傘を除く・%d本）" % n,
                  *(sum(res[um][p].get(r, 0) for p in prs) / n for r in roles),
                  sum(sum(res[um][p].get(r, 0) for r in roles) for p in prs) / n))
        print()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
