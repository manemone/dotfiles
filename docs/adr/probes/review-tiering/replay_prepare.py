"""再現実験の準備（使い捨て）: 傘ごとの孫 PR と「最初のレビュー前の head」を特定する。

gh は読み取りだけ（pr view）。結果は derived/replay/umbrella<N>.json（リポの外）に書く。
環境変数: REVIEW_DATA, REVIEW_OWNER
"""
import json, os, subprocess, sys
from common import DERIVED, load_rows, load_pr, umbrellas, REVIEW_RE, APPROVE_RE

OWNER = os.environ.get("REVIEW_OWNER") or sys.exit("REVIEW_OWNER を渡すこと")
OUT = os.path.join(DERIVED, "replay")
os.makedirs(OUT, exist_ok=True)


def gh_commits(repo, n):
    r = subprocess.run(["gh", "pr", "view", str(n), "-R", f"{OWNER}/{repo}", "--json",
                        "commits,mergedAt,mergeCommit,baseRefOid,headRefOid"],
                       capture_output=True, text=True, check=True)
    return json.loads(r.stdout)


def first_review_time(pr):
    ts = [r["submittedAt"] for r in pr["reviews"] if r.get("submittedAt")]
    # 🤖🔍 / 🤖✅ のコメントも「最初のレビュー」に数える
    for c in pr["comments"]:
        if REVIEW_RE.match(c["body"]) or APPROVE_RE.match(c["body"]):
            ts.append(c["createdAt"])
    return min(ts) if ts else None


um_rows = json.load(open(os.path.join(os.environ["REVIEW_DATA"], "um.json")))
for i, u in enumerate(umbrellas(), 1):
    repo, base = u.split("/", 1)
    prs = sorted([r for r in load_rows() if r["repo"] == repo and r["base"] == base], key=lambda r: r["n"])
    out = []
    for r in prs:
        pr = load_pr(repo, r["n"])
        meta = gh_commits(repo, r["n"])
        t0 = first_review_time(pr)
        commits = meta["commits"]
        before = [c for c in commits if t0 is None or c["committedDate"] <= t0]
        out.append({"n": r["n"], "title_len": len(r["title"]), "mergedAt": meta["mergedAt"],
                    "firstReviewAt": t0, "ncommits": len(commits),
                    "pre_review_head": before[-1]["oid"] if before else None,
                    "merge_oid": (meta.get("mergeCommit") or {}).get("oid"),
                    "final_head": meta["headRefOid"], "find": r["find"], "size": r["size"]})
    um_pr = [x["n"] for x in um_rows if x["repo"] == repo and x["head"] == base]
    json.dump({"umbrella": i, "repo": repo, "base": base, "umbrella_pr": um_pr[0] if um_pr else None, "prs": out},
              open(os.path.join(OUT, f"umbrella{i}.json"), "w"), ensure_ascii=False, indent=1)
    print(f"傘{i}: 孫 {len(out)}本, レビュー前headが取れた {sum(1 for p in out if p['pre_review_head'])}本")
