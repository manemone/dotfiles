#!/bin/sh
#
# claude/hooks/git-guard.sh — PreToolUse フック。
#
# 「main / master へのマージ・push は人間、それ以外の git 操作は AI に
# 任せる」という線引きを機械的に担保する。判定できない入力は必ず ask に
# 倒す（allow に倒すことは絶対にしない）。設計の根拠・入出力契約の確認結果・
# 却下案は docs/adr/DOC-2609121719_git-operation-permission-policy.md を参照。
#
# 判定表（この関数の外に判定ロジックを重複させないこと。保護ブランチの
# 定義もこのスクリプト内の1箇所——下の GIT_GUARD_PROTECTED_BRANCHES——のみ）:
#   gh pr merge  : base を gh pr view で解決。保護ブランチなら deny、他は allow
#   git push     : --force/--force-with-lease/-f/+<refspec> が付く場合のみ対象。
#                  対象ブランチが保護ブランチなら deny。他は --force-with-lease
#                  を allow、裸の --force/-f は ask
#   git merge    : 現在のブランチ（マージ先）が保護ブランチなら deny、他は allow
#   それ以外     : 何も言わず終了（既存の permissions.ask に委ねる）
#
# このフックは全 Bash 呼び出しで走るため、対象外のコマンドは JSON を
# パースする前の文字列一致で弾く（速い経路）。

# 保護ブランチの定義はここ1箇所のみ。
GIT_GUARD_PROTECTED_BRANCHES="main master"

INPUT="$(cat)"

# 速い経路: git ... merge / git ... push / gh ... pr ... merge のいずれの
# 字面も含まれない入力は、JSON パースすら行わず即座に抜ける。"git merge" の
# ような連続文字列ではなく緩い間隔一致にしているのは、`git -C <dir> merge`
# のようにグローバルオプションが挟まるケースを取りこぼして「何も言わない」
# （本来は ask にすべき判定不能ケース）に落ちるのを防ぐため。
case "$INPUT" in
  *"git"*"merge"* | *"git"*"push"* | *"gh"*"pr"*"merge"*) ;;
  *) exit 0 ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
  # 判定不能。allow には倒さず、固定の ask 応答を返す。
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"git-guard: python3 が見つからないため git/gh コマンドの安全性を判定できません"}}'
  exit 0
fi

GIT_GUARD_PROTECTED_BRANCHES="$GIT_GUARD_PROTECTED_BRANCHES" python3 - "$INPUT" <<'PYEOF'
import json
import os
import re
import shlex
import subprocess
import sys

PROTECTED = set(os.environ.get("GIT_GUARD_PROTECTED_BRANCHES", "main master").split())
GH_TIMEOUT = 8
GIT_TIMEOUT = 5

# git push のオプションのうち、値をスペース区切りで取りうるもの。
# これ以外の未知の "-" 始まりトークンが出てきたら、安全に対象ブランチを
# 解決できないと判断して ask に倒す（ADR「既知の制限」参照）。
VALUE_TAKING_SHORT = {"-o"}
VALUE_TAKING_LONG = ("--push-option", "--repo", "--receive-pack")

FORCE_LEASE_RE = re.compile(r"^--force-with-lease(=.*)?$")


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


def ask(reason):
    emit("ask", reason)


def allow():
    emit("allow")


def deny(reason):
    emit("deny", reason)


def run(cmd, cwd, timeout):
    try:
        return subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout
        )
    except Exception:
        return None


def current_branch(cwd):
    proc = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd, GIT_TIMEOUT)
    if proc is None or proc.returncode != 0:
        return None
    branch = proc.stdout.strip()
    if not branch or branch == "HEAD":
        return None
    return branch


def gh_base_ref(target, cwd):
    cmd = ["gh", "pr", "view"]
    if target:
        cmd.append(target)
    cmd += ["--json", "baseRefName", "-q", ".baseRefName"]
    proc = run(cmd, cwd, GH_TIMEOUT)
    if proc is None or proc.returncode != 0:
        return None
    base = proc.stdout.strip()
    return base or None


def tokenize(command):
    try:
        return shlex.split(command)
    except ValueError:
        return None


def find_subcommand(tokens, words):
    # tokens 内で words（例: ["gh", "pr", "merge"]）が連続して出現する
    # 最初の位置の直後インデックスを返す。グローバルオプション（git -C dir
    # merge、gh --repo o/r pr merge 等）が挟まると一致せず None になり、
    # 呼び出し側は ask に倒す（安全側）。
    n = len(words)
    for i in range(len(tokens) - n + 1):
        if tokens[i : i + n] == words:
            return i + n
    return None


def strip_quoted(command):
    # シングル/ダブルクォートで囲まれた区間を取り除く。has_chain() の
    # 判定にだけ使う（コミットメッセージ中の "merge 済み; 掃除も" のような
    # 引用符内の ; / | を連結と誤認しないため）。エスケープされた引用符や
    # ネストしたクォートを厳密に再現するものではないが、万一取りこぼしても
    # && / ; / | が残っていれば ask に倒れるだけで allow 方向には振れない。
    return re.sub(r"'[^']*'|\"[^\"]*\"", "", command)


def has_chain(command):
    # 複数コマンドが && / ; / | で連結されている場合、対象を一意に特定
    # できないため ask に倒す（fail-safe）。
    return bool(re.search(r"&&|;|\|", strip_quoted(command)))


def subcommand_of(tokens, prog):
    # tokens 内で prog（"git" または "gh"）が最初に現れる位置を探し、
    # その直後の非オプショントークンをサブコマンドとして返す。
    # 戻り値: (subcommand, uncertain)
    #   - prog が見つからない: (None, False) — このプログラムへの呼び出しではない
    #   - 直後のトークンが "-" 始まり（グローバルオプション）: (None, True) —
    #     サブコマンドを安全に断定できない
    #   - それ以外: (トークン, False)
    #
    # 単純な「最初の出現位置」判定であり、`echo git merge` のように prog が
    # 別コマンドの引数値として現れる場合を誤検出することがあるが、その
    # 場合でも実際には git/gh が実行されないため deny/ask になっても実害は
    # 無い（fail-safe の本質——main/master への操作を allow に倒さない——は
    # 損なわれない）。
    for i, tok in enumerate(tokens):
        if tok == prog:
            if i + 1 < len(tokens):
                nxt = tokens[i + 1]
                if nxt.startswith("-"):
                    return None, True
                return nxt, False
            return None, False
    return None, False


def handle_gh_pr_merge(command, cwd):
    tokens = tokenize(command)
    if tokens is None:
        ask("git-guard: gh pr merge のコマンドを解析できませんでした")
        return
    start = find_subcommand(tokens, ["gh", "pr", "merge"])
    if start is None:
        ask("git-guard: gh pr merge の対象を特定できませんでした（グローバルオプションの可能性）")
        return
    # --repo/-R は gh pr view の対象リポジトリを cwd 以外へ切り替える。
    # これを無視すると、判定対象（cwd のリポジトリ）と実際にマージされる
    # リポジトリが食い違い、別リポジトリの base を見て誤って allow しうる。
    if any(
        tok in ("--repo", "-R") or tok.startswith("--repo=") for tok in tokens
    ):
        ask("git-guard: --repo/-R 指定付き gh pr merge は対象リポジトリを安全に解決できません")
        return
    target = None
    for tok in tokens[start:]:
        if tok.startswith("-"):
            continue
        target = tok
        break
    base = gh_base_ref(target, cwd)
    if base is None:
        ask(
            "git-guard: gh pr view で base ブランチを解決できませんでした"
            "（PR 番号の解決失敗・gh 実行失敗の可能性）"
        )
        return
    if base in PROTECTED:
        deny(
            f"base ブランチ '{base}' は保護ブランチです。"
            "main/master へのマージは人間が行います"
        )
    else:
        allow()


def handle_git_push(command, cwd):
    tokens = tokenize(command)
    if tokens is None:
        ask("git-guard: git push のコマンドを解析できませんでした")
        return
    start = find_subcommand(tokens, ["git", "push"])
    if start is None:
        ask("git-guard: git push の対象を特定できませんでした（グローバルオプションの可能性）")
        return

    rest = tokens[start:]

    has_force_lease = False
    has_bare_force = False
    positional = []

    i = 0
    while i < len(rest):
        tok = rest[i]
        if FORCE_LEASE_RE.match(tok):
            has_force_lease = True
            i += 1
            continue
        if tok in ("--force", "-f"):
            has_bare_force = True
            i += 1
            continue
        if tok in VALUE_TAKING_SHORT:
            i += 2
            continue
        if any(tok == p or tok.startswith(p + "=") for p in VALUE_TAKING_LONG):
            i += 1 if "=" in tok else 2
            continue
        if tok.startswith("-"):
            ask(
                f"git-guard: 未知の git push オプション '{tok}' のため"
                "対象ブランチを安全に解決できません"
            )
            return
        positional.append(tok)
        i += 1

    if not has_force_lease and not has_bare_force and not any(
        p.startswith("+") for p in positional
    ):
        # force 系フラグも +refspec も無い ⇒ このフックの対象外。
        say_nothing()
        return

    if len(positional) == 0:
        refspec = None
    elif len(positional) == 1:
        refspec = None  # positional[0] はリモート名
    elif len(positional) == 2:
        refspec = positional[1]
    else:
        ask("git-guard: git push の引数から対象ブランチを一意に特定できませんでした（複数の refspec）")
        return

    if refspec is not None and refspec.startswith("+"):
        has_bare_force = True  # 先頭 "+" は lease 無しの force 相当
        refspec = refspec[1:]

    if refspec:
        dst = refspec.split(":")[-1] if ":" in refspec else refspec
        if dst.startswith("refs/heads/"):
            dst = dst[len("refs/heads/") :]
        if dst in ("HEAD", "@"):
            # "HEAD" / "@" は「現在チェックアウトしているブランチ」を指す
            # git の特殊参照であり、ブランチ名そのものではない。文字列の
            # まま比較すると常に非保護扱いになってしまう。
            target_branch = current_branch(cwd)
        else:
            target_branch = dst
    else:
        target_branch = current_branch(cwd)

    if not target_branch:
        ask("git-guard: git push の対象ブランチを解決できませんでした")
        return

    if target_branch in PROTECTED:
        deny(f"'{target_branch}' は保護ブランチです。force push は人間が行います")
        return

    if has_force_lease and not has_bare_force:
        allow()
    else:
        ask(f"'{target_branch}' への force push（lease 無し）です。内容を確認してください")


def handle_git_merge(command, cwd):
    tokens = tokenize(command)
    if tokens is None:
        ask("git-guard: git merge のコマンドを解析できませんでした")
        return
    start = find_subcommand(tokens, ["git", "merge"])
    if start is None:
        ask("git-guard: git merge の対象を特定できませんでした（グローバルオプションの可能性）")
        return
    branch = current_branch(cwd)
    if not branch:
        ask("git-guard: 現在のブランチを解決できませんでした")
        return
    if branch in PROTECTED:
        deny(f"現在のブランチ '{branch}' は保護ブランチです。マージは人間が行います")
    else:
        allow()


def main():
    # 標準入力ではなくコマンドライン引数で受け取る: python3 - <json> の
    # ように "-"（スクリプトを stdin から読む指定）と併用する場合、stdin は
    # このヒアドキュメント自身に占有されるため、ペイロードを stdin 経由で
    # 渡すことができない（claude/deploy.sh の既存パターンと同じ理由で
    # ファイル/引数渡しにしている）。
    if len(sys.argv) < 2:
        say_nothing()
        return
    try:
        payload = json.loads(sys.argv[1])
    except Exception:
        say_nothing()
        return

    if payload.get("tool_name") != "Bash":
        say_nothing()
        return

    tool_input = payload.get("tool_input") or {}
    command = tool_input.get("command")
    if not isinstance(command, str) or not command.strip():
        say_nothing()
        return

    cwd = payload.get("cwd") or None

    # トークンベースでサブコマンドを特定する（"git merge" のような連続
    # 文字列一致ではなく）。理由: git merge には permissions.ask 側の保険が
    # 無い（設計上フックだけが唯一のガード）ため、単純な文字列一致だと
    # `git commit -m "merge conflict fix"` のような日常的なコマンドまで
    # "merge" を含むという理由で誤って対象扱いしてしまい、無関係な
    # コマンドで頻繁に ask が出て autopilot の目的を損なう。一方で
    # `git -C <dir> merge` のようにサブコマンドの位置にグローバル
    # オプションが挟まって安全に断定できない場合は、素通りさせず ask に
    # 倒す（allow への誤判定は絶対にしないという fail-safe を優先する）。
    tokens = tokenize(command)
    if tokens is None:
        if re.search(r"\bgit\b", command) or re.search(r"\bgh\b", command):
            ask("git-guard: コマンドをトークン化できず安全に判定できません")
        else:
            say_nothing()
        return

    if has_chain(command):
        if re.search(r"\bgit\b", command) or re.search(r"\bgh\b", command):
            ask("git-guard: 複数コマンドが連結されており対象を一意に特定できません")
        else:
            say_nothing()
        return

    git_sub, git_uncertain = subcommand_of(tokens, "git")
    if git_uncertain:
        ask("git-guard: git のグローバルオプションによりサブコマンドを特定できません")
        return
    if git_sub == "merge":
        handle_git_merge(command, cwd)
        return
    if git_sub == "push":
        handle_git_push(command, cwd)
        return

    gh_sub, gh_uncertain = subcommand_of(tokens, "gh")
    if gh_uncertain:
        ask("git-guard: gh のグローバルオプションによりサブコマンドを特定できません")
        return
    if gh_sub == "pr":
        gh_idx = tokens.index("gh")
        pr_idx = gh_idx + 1
        if pr_idx + 1 < len(tokens) and tokens[pr_idx + 1] == "merge":
            handle_gh_pr_merge(command, cwd)
            return

    say_nothing()


main()
PYEOF
