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
# `claude/settings.json` のフック側 timeout（15秒）より短くしておく。ただし
# 「gh は生きているが遅い」状態ではフックだけが先に諦めて無音になり、後続の
# `gh pr merge` 本体（タイムアウト無し）は成功しうる。この窓は ADR §7 に
# 残余リスクとして明記してある。
GH_TIMEOUT = 12

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

# 対象リポジトリを cwd から動かすオプション。base の解決を cwd 任せにすると
# 別リポジトリのブランチで判定してしまうため、`gh pr view` 側へ引き継ぐ。
# `--repo` は `gh pr` 配下の inherited flag であり、`gh` の直後だけでなく
# `pr merge` の後ろにも書ける（`gh pr merge 7 -R owner/repo`）。片側しか
# 見ないと、その値をマージ対象と取り違えて cwd 基準で解決してしまう。
REPO_FLAGS = {"-R", "--repo"}

# `gh` をコマンドとして扱ってよい位置。直前がこれらのいずれか（または先頭）
# でなければ、ヒアドキュメントの本文や他コマンドの引数として現れた `gh` で
# あり、実行されない。誤って deny すると無人ペインが止まる（deny は
# bypassPermissions でも覆せないぶん ask より強く止まる）。
COMMAND_POSITION_PREV = {"&&", "||", ";", ";;", "|", "|&", "(", ")", "{", "}", "do", "then", "else", "!"}


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


def repo_arg_of(tok, nxt):
    # トークンが `--repo` 指定なら (repo_args, 次のトークンも消費するか) を返す。
    # そうでなければ (None, False)。`-Rowner/repo` の密着形も `gh` は受け付ける。
    if tok in REPO_FLAGS:
        return ([tok, nxt], True) if nxt is not None else (None, False)
    if tok.startswith("--repo=") or (tok.startswith("-R") and len(tok) > 2):
        return [tok], False
    return None, False


def find_pr_merge(tokens):
    # tokens 内の `gh ... pr merge` を探し、(repo_args, target) を返す。
    # 見つからなければ None。`cd <dir> && gh pr merge 1` のように連結されて
    # いても、`gh` 以降のトークン列だけを見るので同じように拾える。
    for i, tok in enumerate(tokens):
        if tok != "gh":
            continue
        if i > 0 and tokens[i - 1] not in COMMAND_POSITION_PREV:
            # 実行されない `gh`（ヒアドキュメントの本文、`echo gh pr merge 95` の
            # 引数など）。拾うと無関係な書き込みコマンドが deny される。
            continue
        repo_args = []
        j = i + 1
        while j < len(tokens) and tokens[j] != "pr":
            tok_j = tokens[j]
            found, consumed = repo_arg_of(
                tok_j, tokens[j + 1] if j + 1 < len(tokens) else None
            )
            if found is not None:
                repo_args = found
                j += 2 if consumed else 1
                continue
            if not tok_j.startswith("-"):
                # `pr` 以外のサブコマンドだった（gh issue ... 等）。
                break
            j += 1
        if j >= len(tokens) or tokens[j] != "pr":
            continue
        if j + 1 >= len(tokens) or tokens[j + 1] != "merge":
            continue
        rest_repo_args, target = scan_merge_args(tokens[j + 2 :])
        return (rest_repo_args or repo_args), target
    return None


def scan_merge_args(rest):
    # `gh pr merge` の後ろから、`--repo` 指定とマージ対象（PR 番号 / URL /
    # ブランチ名）を取り出す。`--repo` は inherited flag なのでここにも書ける。
    # 対象が省略されていれば None（`gh pr view` 側も省略時は現在のブランチの
    # PR を引く）。
    repo_args = []
    target = None
    skip = False
    for idx, tok in enumerate(rest):
        if skip:
            skip = False
            continue
        found, consumed = repo_arg_of(
            tok, rest[idx + 1] if idx + 1 < len(rest) else None
        )
        if found is not None:
            repo_args = found
            skip = consumed
            continue
        if tok.startswith("-"):
            if tok in MERGE_VALUE_TAKING:
                skip = True
            continue
        if target is None:
            target = tok
    return repo_args, target


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
