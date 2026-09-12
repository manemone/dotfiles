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
#   chmod        : -R/--recursive 無し・モードが実行ビット付与のみ（+x 等の
#                  シンボリック指定。数値モードは対象外）・対象パスが全て
#                  現在の git ワークツリー内かつ .git 配下でなければ allow。
#                  1つでも満たさなければ ask（deny ではない）
#   rm -r/-rf/-fr等: 対象パスが全て一時ディレクトリ配下（このセッションの
#                  scratchpad、または $TMPDIR/`/tmp` 自身より深い場所）に
#                  解決されれば allow。ワークツリー内は対象外（ask のまま）
#   それ以外     : 何も言わず終了（既存の permissions.ask に委ねる）
#
# chmod/rm はいずれも「危険かどうかは対象がどこにあるかで決まる」ため、
# git 操作と同じ理由でここで判定する（背景3-G）。判定できなければ ask に
# 倒すのは git/gh の arm と同じ fail-safe（allow に倒すことは絶対にしない）。
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
  *"git"*"merge"* | *"git"*"push"* | *"gh"*"pr"*"merge"* | *"chmod"* | *"rm"*) ;;
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

# chmod: allow してよいのは、モードが実行ビット付与のみのシンボリック指定
# （+x, u+x, a+x, ug+x 等）のときだけ。数値モード（755 等）や他の操作
# （u+s, o+w, u-x 等）、複合指定（u+x,g-w）は対象外（ADR §背景3-G参照）。
CHMOD_MODE_RE = re.compile(r"^[ugoa]*\+x$")
CHMOD_RECURSIVE_FLAGS = {"-R", "--recursive"}
# 出力の詳細さだけを変える無害なフラグ。これ以外の "-" 始まりトークンは
# 未知として ask に倒す（--reference=RFILE 等、意味が変わるものを含む）。
CHMOD_SAFE_FLAGS = {"-c", "--changes", "-v", "--verbose", "-f", "--silent", "--quiet"}

# rm -r: allow してよいのは、対象パスが全て一時ディレクトリ配下に解決
# されるときだけ（ADR §背景3-G参照。ワークツリー内は対象外）。
RM_RECURSIVE_SHORT_CHARS = {"r", "R"}
RM_KNOWN_SHORT_CHARS = {"r", "R", "f", "v", "i"}
RM_SAFE_LONG_FLAGS = {"--force", "--verbose", "--interactive"}
RM_RECURSIVE_LONG_FLAGS = {"--recursive"}


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


def worktree_root(cwd):
    proc = run(["git", "rev-parse", "--show-toplevel"], cwd, GIT_TIMEOUT)
    if proc is None or proc.returncode != 0:
        return None
    root = proc.stdout.strip()
    if not root:
        return None
    return os.path.realpath(root)


def resolve_path(token, cwd):
    # シンボリックリンクと ".." を解決した絶対パスを返す。存在しないパス
    # でも lexical に正規化される（chmod/rm の対象は通常存在するファイルだが、
    # 解決に失敗する場合のみ None を返し呼び出し側で ask に倒す）。
    try:
        base = cwd or os.getcwd()
        path = token if os.path.isabs(token) else os.path.join(base, token)
        return os.path.realpath(path)
    except Exception:
        return None


def is_within(path, base):
    return path == base or path.startswith(base + os.sep)


def is_temp_allowed(resolved):
    # このセッションの scratchpad（/tmp/claude-<id>/...）。"/tmp" 自体が
    # シンボリックリンク（macOS の /tmp -> /private/tmp 等）でも一致するよう
    # realpath したうえで比較する。
    tmp_root = os.path.realpath("/tmp")
    if re.match(re.escape(tmp_root) + r"/claude-[^/]+/", resolved):
        return True
    # $TMPDIR（未設定なら /tmp）自身より深い場所（mktemp -d が作る
    # /tmp/tmp.XXXXXXXXXX を含む）。$TMPDIR 自身は allow にしない。
    tmpdir = os.environ.get("TMPDIR") or "/tmp"
    tmpdir_real = os.path.realpath(tmpdir)
    if resolved == tmpdir_real:
        return False
    if resolved.startswith(tmpdir_real + os.sep):
        return True
    return False


def find_prog(tokens, prog):
    # tokens 内で prog（"chmod" または "rm"）が最初に現れる位置を返す。
    # git/gh の subcommand_of と同じ理由（環境変数プレフィックス等を
    # 取りこぼさない）で、位置0固定ではなく全体を走査する。見つからない
    # 場合は None（このプログラムへの呼び出しではない）。
    for i, tok in enumerate(tokens):
        if tok == prog:
            return i
    return None


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


def mentions_guarded_command(command):
    # トークン化不能・複数コマンド連結のとき、このフックが担保している
    # コマンド（git/gh/chmod/rm）に言及している可能性があれば ask に倒す。
    # 言及が無ければ何も言わず既存の permissions に委ねる。
    return bool(
        re.search(r"\bgit\b", command)
        or re.search(r"\bgh\b", command)
        or re.search(r"\bchmod\b", command)
        or re.search(r"\brm\b", command)
    )


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


def handle_chmod(command, cwd):
    tokens = tokenize(command)
    if tokens is None:
        ask("git-guard: chmod のコマンドを解析できませんでした")
        return
    idx = find_prog(tokens, "chmod")
    if idx is None:
        say_nothing()
        return
    rest = tokens[idx + 1 :]

    mode = None
    paths = []
    for tok in rest:
        if tok in CHMOD_RECURSIVE_FLAGS:
            ask("git-guard: chmod -R/--recursive は対象範囲が広いため確認してください")
            return
        if tok in CHMOD_SAFE_FLAGS:
            continue
        if tok.startswith("-"):
            ask(f"git-guard: chmod の未知のオプション '{tok}' のため安全に判定できません")
            return
        if mode is None:
            mode = tok
            continue
        paths.append(tok)

    if mode is None or not paths:
        ask("git-guard: chmod のモード/対象を特定できませんでした")
        return
    if not CHMOD_MODE_RE.match(mode):
        ask(
            f"git-guard: chmod のモード '{mode}' は実行ビット付与（+x 等）ではないため"
            "確認してください"
        )
        return

    root = worktree_root(cwd)
    if root is None:
        ask("git-guard: git ワークツリーのルートを解決できませんでした")
        return
    git_meta = os.path.realpath(os.path.join(root, ".git"))

    for p in paths:
        resolved = resolve_path(p, cwd)
        if resolved is None:
            ask(f"git-guard: chmod の対象 '{p}' を解決できませんでした")
            return
        if not is_within(resolved, root):
            ask(f"git-guard: chmod の対象 '{p}' が git ワークツリー外です")
            return
        if resolved == git_meta or is_within(resolved, git_meta):
            ask(f"git-guard: chmod の対象 '{p}' が .git 配下です")
            return

    allow()


def handle_rm(command, cwd):
    tokens = tokenize(command)
    if tokens is None:
        ask("git-guard: rm のコマンドを解析できませんでした")
        return
    idx = find_prog(tokens, "rm")
    if idx is None:
        say_nothing()
        return
    rest = tokens[idx + 1 :]

    recursive = False
    paths = []
    for tok in rest:
        if tok == "--":
            continue
        if tok in RM_RECURSIVE_LONG_FLAGS:
            recursive = True
            continue
        if tok in RM_SAFE_LONG_FLAGS:
            continue
        if tok.startswith("--"):
            ask(f"git-guard: rm の未知のオプション '{tok}' のため安全に判定できません")
            return
        if tok.startswith("-") and len(tok) > 1:
            chars = set(tok[1:])
            if not chars <= RM_KNOWN_SHORT_CHARS:
                ask(f"git-guard: rm の未知のオプション '{tok}' のため安全に判定できません")
                return
            if chars & RM_RECURSIVE_SHORT_CHARS:
                recursive = True
            continue
        paths.append(tok)

    if not recursive:
        # -r/-R/--recursive の無い rm はこのフックの対象外
        # （permissions.ask にも rm -r 系のパターンしか無いため元々ここへ来ない）。
        say_nothing()
        return

    if not paths:
        ask("git-guard: rm -r の対象を特定できませんでした")
        return

    # ワークツリー内は対象外（allow にしない）。通常ワークツリーは /tmp 配下
    # には無いが、万一 /tmp 配下にチェックアウトされている場合でも
    # is_temp_allowed() だけでは判定を誤るため、明示的に除外する。
    # worktree_root が解決できない（git リポジトリ外）場合は、保護すべき
    # ワークツリーが無いとみなし、この除外は行わない。
    root = worktree_root(cwd)

    for p in paths:
        resolved = resolve_path(p, cwd)
        if resolved is None or not is_temp_allowed(resolved):
            ask(
                f"git-guard: rm -r の対象 '{p}' が一時ディレクトリ配下と確認できません"
                "（ワークツリー内の削除は人間が確認します）"
            )
            return
        if root is not None and is_within(resolved, root):
            ask(f"git-guard: rm -r の対象 '{p}' は git ワークツリー内です")
            return

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
        if mentions_guarded_command(command):
            ask("git-guard: コマンドをトークン化できず安全に判定できません")
        else:
            say_nothing()
        return

    if has_chain(command):
        if mentions_guarded_command(command):
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

    if find_prog(tokens, "chmod") is not None:
        handle_chmod(command, cwd)
        return

    if find_prog(tokens, "rm") is not None:
        handle_rm(command, cwd)
        return

    say_nothing()


main()
PYEOF
