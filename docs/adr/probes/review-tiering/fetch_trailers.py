"""実装役が引けなかった PR（対応報告が無い）について、gh（読み取りのみ）でコミットの
Co-Authored-By trailer を取り、derived/trailers.json に保存する。

環境変数 REVIEW_OWNER にリポの所有者を渡す。リモートへの書き込みは一切しない。
"""
import json, os, subprocess, re
from concurrent.futures import ThreadPoolExecutor
from common import *

OWNER = os.environ.get("REVIEW_OWNER")
if not OWNER:
    raise SystemExit("REVIEW_OWNER（GitHub の所有者名）を環境変数で渡すこと")

prs = json.load(open(os.path.join(DERIVED, "prs.json")))
todo = [p for p in prs if not p["implementer_report"]]
out_path = os.path.join(DERIVED, "trailers.json")
done = json.load(open(out_path)) if os.path.exists(out_path) else {}


def fetch(p):
    key = f'{p["repo"]}#{p["n"]}'
    if key in done:
        return key, done[key]
    r = subprocess.run(
        ["gh", "pr", "view", str(p["n"]), "-R", f'{OWNER}/{p["repo"]}', "--json", "commits"],
        capture_output=True, text=True)
    if r.returncode:
        return key, {"error": r.stderr.strip()[:200]}
    commits = json.loads(r.stdout)["commits"]
    names = []
    for c in commits:
        for m in re.finditer(r"Co-Authored-By:\s*([^<\n]+)", c.get("messageBody") or "", re.I):
            names.append(m.group(1).strip())
    return key, {"n_commits": len(commits), "coauthors": sorted(set(names))}


with ThreadPoolExecutor(6) as ex:
    for key, v in ex.map(fetch, todo):
        done[key] = v
json.dump(done, open(out_path, "w"), ensure_ascii=False, indent=1)
print(len(todo), "PR →", out_path, "エラー", sum(1 for v in done.values() if "error" in v))
