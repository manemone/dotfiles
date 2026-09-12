#!/bin/sh
#
# claude/hooks/git-guard.sh — PreToolUse フック。
#
# 担保するのは**1点だけ**:
#
#   `gh pr merge` のマージ先（base）が保護ブランチ（main / master）なら deny。
#
# それ以外は何も言わない（既存の `permissions` に委ねる）。**判定できない入力も
# 何も言わない。** 「判定できなければ ask に倒す」という初版（PR #94）の設計思想は
# 破棄した。シェルコマンドの大半は静的解析できないため、その方針は事実上
# 「大半を ask にする」と同義であり、`cd <repo> && git status` のような読み取り
# 専用コマンドまで承認ダイアログを出して無人ペインを止めていた。
#
# なぜ `gh pr merge` だけがフックの仕事なのか: 不可逆なのは「リモートを書き換える
# 操作」だけであり、そのうち `git push` は対象が**コマンド文字列に現れる**ため
# `claude/settings.json` の `permissions.ask` グロブ（`Bash(git push * main*)` /
# `Bash(git push * master*)` ほか）で表現できる。base が PR 側の属性であり
# コマンド文字列に現れない `gh pr merge` だけが、グロブで表現できずフックを要する。
# ローカルの `git merge` は push しなければ巻き戻せるため対象外。
#
# 設計の根拠・却下案・受け入れた残余リスクは
# docs/adr/DOC-2609121719_git-operation-permission-policy.md を参照。

# 保護ブランチの定義はここ1箇所のみ。
GIT_GUARD_PROTECTED_BRANCHES="main master"

INPUT="$(cat)"

# 速い経路: `gh` `pr` `merge` の字面が揃わない入力は JSON パースすら行わず抜ける。
# このフックは全 Bash 呼び出しで走るため、対象外のコマンドを安く捨てる。
case "$INPUT" in
  *"gh"*"pr"*"merge"*) ;;
  *) exit 0 ;;
esac

# python3 が無ければ何も言わない（ask に倒さない）。フックが唯一の担保である
# のは事実だが、判定できないことを理由に人間を呼ぶのは上記のとおり破棄した方針。
command -v python3 >/dev/null 2>&1 || exit 0

GIT_GUARD_PROTECTED_BRANCHES="$GIT_GUARD_PROTECTED_BRANCHES" python3 - "$INPUT" <<'PYEOF'
import json
import os
import shlex
import subprocess
import sys

PROTECTED = set(os.environ.get("GIT_GUARD_PROTECTED_BRANCHES", "main master").split())
GH_TIMEOUT = 8

# `gh pr merge` のうち、値をスペース区切りで取るオプション。次のトークンを
# マージ対象（PR 番号 / URL / ブランチ名）と取り違えないために読み飛ばす。
MERGE_VALUE_TAKING = {
    "-b",
    "--body",
    "-F",
    "--body-file",
    "-t",
    "--subject",
    "--match-head-commit",
    "--author-email",
}

# `gh` のグローバルオプションのうち、対象リポジトリを cwd から動かすもの。
# base の解決を cwd 任せにすると別リポジトリのブランチで判定してしまうため、
# `gh pr view` 側へそのまま引き継ぐ。
REPO_FLAGS = ("-R", "--repo")


def emit(decision, reason=None):
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,
        }
    }
    if reason is not None:
        out["hookSpecificOutput"]["permissionDecisionReason"] = reason
    sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")
    sys.exit(0)


def say_nothing():
    sys.exit(0)


def find_pr_merge(tokens):
    # tokens 内の `gh ... pr merge` を探し、(repo_args, target) を返す。
    # 見つからなければ None。`cd <dir> && gh pr merge 1` のように連結されて
    # いても、`gh` 以降のトークン列だけを見るので同じように拾える。
    for i, tok in enumerate(tokens):
        if tok != "gh":
            continue
        repo_args = []
        j = i + 1
        while j < len(tokens) and tokens[j] != "pr":
            tok_j = tokens[j]
            if tok_j in REPO_FLAGS and j + 1 < len(tokens):
                repo_args = [tok_j, tokens[j + 1]]
                j += 2
                continue
            if tok_j.startswith("--repo="):
                repo_args = [tok_j]
            elif not tok_j.startswith("-"):
                # `pr` 以外のサブコマンドだった（gh issue ... 等）。
                break
            j += 1
        if j >= len(tokens) or tokens[j] != "pr":
            continue
        if j + 1 >= len(tokens) or tokens[j + 1] != "merge":
            continue
        return repo_args, merge_target(tokens[j + 2 :])
    return None


def merge_target(rest):
    # `gh pr merge` の後ろから、マージ対象（PR 番号 / URL / ブランチ名）を取り出す。
    # 省略されていれば None（`gh pr view` 側も省略時は現在のブランチの PR を引く）。
    skip = False
    for tok in rest:
        if skip:
            skip = False
            continue
        if tok.startswith("-"):
            if tok in MERGE_VALUE_TAKING:
                skip = True
            continue
        return tok
    return None


def resolve_base(repo_args, target, cwd):
    cmd = ["gh"] + repo_args + ["pr", "view"]
    if target is not None:
        cmd.append(target)
    cmd += ["--json", "baseRefName", "-q", ".baseRefName"]
    try:
        proc = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=GH_TIMEOUT
        )
    except Exception:
        return None
    if proc.returncode != 0:
        return None
    base = proc.stdout.strip()
    return base or None


def main():
    # ペイロードは stdin ではなくコマンドライン引数で受け取る: `python3 - <json>`
    # のヒアドキュメント方式では stdin がスクリプト本体に占有されるため。
    if len(sys.argv) < 2:
        say_nothing()
    try:
        payload = json.loads(sys.argv[1])
    except Exception:
        say_nothing()

    if payload.get("tool_name") != "Bash":
        say_nothing()

    command = (payload.get("tool_input") or {}).get("command")
    if not isinstance(command, str) or not command.strip():
        say_nothing()

    try:
        tokens = shlex.split(command)
    except ValueError:
        say_nothing()

    found = find_pr_merge(tokens)
    if found is None:
        say_nothing()

    repo_args, target = found
    base = resolve_base(repo_args, target, payload.get("cwd") or None)
    if base is None:
        # base を解決できない（gh の実行失敗・PR 不明）。ask には倒さない。
        say_nothing()

    if base in PROTECTED:
        emit(
            "deny",
            f"git-guard: この PR の base は '{base}' です。"
            "保護ブランチへのマージは人間が行います（AGENTS.md 最重要ルール）",
        )
    # base が保護ブランチでないと確定した場合だけ allow を返す。孫→傘のマージを
    # 確実に無音で通すための積極的な allow であり、判定不能時の allow ではない。
    emit("allow")


main()
PYEOF
