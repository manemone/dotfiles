#!/usr/bin/env bash
#
# tests/git_guard_test.sh — claude/hooks/git-guard.sh のスタンドアロンテスト。
#
# git / gh を PATH 先頭のスタブに差し替えて判定表（ADR
# docs/adr/DOC-2609121719_git-operation-permission-policy.md、claude/README.md
# §3.5）を検証する。ネットワークにも実リポジトリの状態にも依存しない。
#
# Usage:
#   tests/git_guard_test.sh
set -uo pipefail

SCRIPT_DIR=$(
  cd "$(dirname "$0")" || exit 1
  pwd
)
REPO_ROOT=$(
  cd "$SCRIPT_DIR/.." || exit 1
  pwd
)
HOOK="$REPO_ROOT/claude/hooks/git-guard.sh"

FAIL=0
STUB_DIR=""

log() { printf '%s\n' "$*"; }
pass() { printf '  [PASS] %s\n' "$1"; }
fail() {
  printf '  [FAIL] %s\n' "$1" >&2
  FAIL=1
}

cleanup() {
  [ -n "$STUB_DIR" ] && rm -rf "$STUB_DIR"
}
trap cleanup EXIT

STUB_DIR="$(mktemp -d)"
WORKTREE_DIR="$STUB_DIR/worktree"
mkdir -p "$WORKTREE_DIR/.git" "$WORKTREE_DIR/tests" "$WORKTREE_DIR/claude/hooks" "$STUB_DIR/outside"
ln -s "$STUB_DIR/outside" "$WORKTREE_DIR/escape-link"
export GIT_GUARD_TEST_WORKTREE_ROOT="$WORKTREE_DIR"

# git スタブ: `git rev-parse --abbrev-ref HEAD` と `git rev-parse --show-toplevel`
# に応答する。GIT_GUARD_TEST_CURRENT_BRANCH（export 必須。未設定なら
# "current-branch"）/ GIT_GUARD_TEST_WORKTREE_ROOT（未設定なら $STUB_DIR/worktree）
# を返す。GIT_GUARD_TEST_GIT_FAIL=1 のときは非ゼロ終了する（解決失敗を模擬）。
cat >"$STUB_DIR/git" <<'STUB'
#!/bin/sh
if [ "${GIT_GUARD_TEST_GIT_FAIL:-0}" = "1" ]; then
  exit 1
fi
if [ "$1" = "rev-parse" ] && [ "$2" = "--abbrev-ref" ] && [ "$3" = "HEAD" ]; then
  printf '%s\n' "${GIT_GUARD_TEST_CURRENT_BRANCH:-current-branch}"
  exit 0
fi
if [ "$1" = "rev-parse" ] && [ "$2" = "--show-toplevel" ]; then
  if [ -z "${GIT_GUARD_TEST_WORKTREE_ROOT:-}" ]; then
    exit 1
  fi
  printf '%s\n' "$GIT_GUARD_TEST_WORKTREE_ROOT"
  exit 0
fi
exit 1
STUB
chmod +x "$STUB_DIR/git"

# gh スタブ: `gh pr view [<target>] --json baseRefName -q .baseRefName` に応答する。
# GIT_GUARD_TEST_BASE_REF（export 必須）が空なら失敗する（PR 解決不能を模擬）。
cat >"$STUB_DIR/gh" <<'STUB'
#!/bin/sh
if [ -z "${GIT_GUARD_TEST_BASE_REF:-}" ]; then
  exit 1
fi
printf '%s\n' "$GIT_GUARD_TEST_BASE_REF"
exit 0
STUB
chmod +x "$STUB_DIR/gh"

# run_hook <command> [cwd]
# 最小限の PreToolUse JSON をフックへ流し込み、stdout を返す。
run_hook() {
  local command="$1" cwd="${2:-$REPO_ROOT}"
  local json
  json=$(python3 -c '
import json, sys
print(json.dumps({
    "session_id": "test",
    "cwd": sys.argv[1],
    "hook_event_name": "PreToolUse",
    "tool_name": "Bash",
    "tool_input": {"command": sys.argv[2]},
}))
' "$cwd" "$command")
  printf '%s' "$json" | PATH="$STUB_DIR:$PATH" "$HOOK"
}

# run_hook_raw <json>
# tool_name が Bash 以外のケースなど、JSON を直接組み立てたいときに使う。
run_hook_raw() {
  printf '%s' "$1" | PATH="$STUB_DIR:$PATH" "$HOOK"
}

# extract_decision
# フックの stdout（空、または hookSpecificOutput JSON）から permissionDecision
# を取り出す。出力が空なら "(none)" を返す（判定表の「何も言わない」）。
extract_decision() {
  python3 -c '
import json, sys
raw = sys.stdin.read().strip()
if not raw:
    print("(none)")
    sys.exit(0)
try:
    data = json.loads(raw)
except Exception:
    print("(invalid-json)")
    sys.exit(0)
print(data.get("hookSpecificOutput", {}).get("permissionDecision", "(no-decision)"))
'
}

assert_decision() {
  local label="$1" expected="$2" actual="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$label (expected: $expected)"
  else
    fail "$label (expected: $expected, got: $actual)"
  fi
}

log "=== git-guard.sh テスト ==="

# ── gh pr merge ──────────────────────────────────────────────────
export GIT_GUARD_TEST_BASE_REF="master"
assert_decision \
  "gh pr merge: base=master（保護ブランチ）は deny" \
  "deny" "$(run_hook "gh pr merge 1 --squash" | extract_decision)"
unset GIT_GUARD_TEST_BASE_REF

export GIT_GUARD_TEST_BASE_REF="autopilot-permissions"
assert_decision \
  "gh pr merge: base=傘ブランチ（非保護）は allow" \
  "allow" "$(run_hook "gh pr merge 1 --squash" | extract_decision)"
unset GIT_GUARD_TEST_BASE_REF

# GIT_GUARD_TEST_BASE_REF 未設定 → gh スタブが失敗 → base 解決不能
assert_decision \
  "gh pr merge: gh 実行失敗（PR 解決不能）は ask（allow に倒れない）" \
  "ask" "$(run_hook "gh pr merge 999999 --squash" | extract_decision)"

# ── git push ─────────────────────────────────────────────────────
export GIT_GUARD_TEST_CURRENT_BRANCH="feature"
assert_decision \
  "git push --force-with-lease: 非保護ブランチ（refspec 省略）は allow" \
  "allow" "$(run_hook "git push --force-with-lease origin" | extract_decision)"
unset GIT_GUARD_TEST_CURRENT_BRANCH

assert_decision \
  "git push --force-with-lease: 保護ブランチへの明示 refspec は deny" \
  "deny" "$(run_hook "git push --force-with-lease origin master" | extract_decision)"

assert_decision \
  "裸の git push --force: 非保護ブランチでも ask" \
  "ask" "$(run_hook "git push --force origin feature" | extract_decision)"

assert_decision \
  "git push -f: 保護ブランチは deny" \
  "deny" "$(run_hook "git push -f origin master" | extract_decision)"

assert_decision \
  "git push +<refspec>: 保護ブランチは deny（lease 無し force 相当）" \
  "deny" "$(run_hook "git push origin +feature:master" | extract_decision)"

assert_decision \
  "force 系フラグも +refspec も無い git push は対象外（何も言わない）" \
  "(none)" "$(run_hook "git push origin feature" | extract_decision)"

assert_decision \
  "git push に未知の値取りオプションが混入: 安全に解決できず ask" \
  "ask" "$(run_hook "git push --unknown-opt value origin feature --force" | extract_decision)"

# refspec が "HEAD" / "@"（現在のブランチを指す特殊参照）のとき、文字列
# のまま比較せず現在のブランチへ解決すること（レビュー指摘2の回帰）。
export GIT_GUARD_TEST_CURRENT_BRANCH="master"
assert_decision \
  "git push --force-with-lease origin HEAD: 現在のブランチ(保護)へ解決して deny" \
  "deny" "$(run_hook "git push --force-with-lease origin HEAD" | extract_decision)"
assert_decision \
  "git push --force-with-lease origin @: 現在のブランチ(保護)へ解決して deny" \
  "deny" "$(run_hook "git push --force-with-lease origin @" | extract_decision)"
unset GIT_GUARD_TEST_CURRENT_BRANCH

export GIT_GUARD_TEST_CURRENT_BRANCH="feature"
assert_decision \
  "git push --force-with-lease origin HEAD: 現在のブランチ(非保護)へ解決して allow" \
  "allow" "$(run_hook "git push --force-with-lease origin HEAD" | extract_decision)"
unset GIT_GUARD_TEST_CURRENT_BRANCH

# ── gh pr merge に --repo/-R が付くケース（レビュー指摘3の回帰）────
# --repo/-R は gh pr view の対象リポジトリを cwd 以外へ切り替えるため、
# 安全に base を解決できない。base=非保護でも allow に倒れないこと。
export GIT_GUARD_TEST_BASE_REF="autopilot-permissions"
assert_decision \
  "gh pr merge --repo <owner/repo>: 対象リポジトリを安全に解決できず ask" \
  "ask" "$(run_hook "gh pr merge 1 --repo other/repo --squash" | extract_decision)"
assert_decision \
  "gh pr merge -R <owner/repo>: 対象リポジトリを安全に解決できず ask" \
  "ask" "$(run_hook "gh pr merge 1 -R other/repo --squash" | extract_decision)"
assert_decision \
  "gh pr merge --repo=<owner/repo>: 対象リポジトリを安全に解決できず ask" \
  "ask" "$(run_hook "gh pr merge 1 --repo=other/repo --squash" | extract_decision)"
unset GIT_GUARD_TEST_BASE_REF

# ── has_chain の引用符誤検出対策（レビュー指摘4の回帰）────────────
# コミットメッセージ等の引用符の中に ; / | があるだけの無関係なコマンドを
# 連結と誤認して ask に倒さないこと。
assert_decision \
  "引用符内の ';' はコマンド連結と誤認しない" \
  "(none)" "$(run_hook 'git commit -m "merge 済み判定を追加; 掃除も"' | extract_decision)"
assert_decision \
  "引用符内の '|' はコマンド連結と誤認しない" \
  "(none)" "$(run_hook 'git commit -m "push|pull を整理"' | extract_decision)"

# ── git merge ────────────────────────────────────────────────────
export GIT_GUARD_TEST_CURRENT_BRANCH="master"
assert_decision \
  "git merge: 現在のブランチ（マージ先）が保護ブランチなら deny" \
  "deny" "$(run_hook "git merge origin/master" | extract_decision)"
unset GIT_GUARD_TEST_CURRENT_BRANCH

export GIT_GUARD_TEST_CURRENT_BRANCH="feature"
assert_decision \
  "git merge: 現在のブランチが非保護なら allow" \
  "allow" "$(run_hook "git merge origin/master" | extract_decision)"
unset GIT_GUARD_TEST_CURRENT_BRANCH

export GIT_GUARD_TEST_GIT_FAIL=1
assert_decision \
  "git merge: 現在のブランチ解決失敗は ask（allow に倒れない）" \
  "ask" "$(run_hook "git merge origin/master" | extract_decision)"
unset GIT_GUARD_TEST_GIT_FAIL

# ── fail-safe: 複数コマンドの連結 ───────────────────────────────
assert_decision \
  "複数コマンド連結（&&）は ask（allow に倒れない）" \
  "ask" "$(run_hook "git merge foo && rm -rf /" | extract_decision)"

assert_decision \
  "複数コマンド連結（;）は ask（allow に倒れない）" \
  "ask" "$(run_hook "git push --force origin master; echo done" | extract_decision)"

# ── グローバルオプションでサブコマンド位置が特定できないケース ──
assert_decision \
  "git -C <dir> merge: サブコマンド位置が特定できず ask（allow に倒れない）" \
  "ask" "$(run_hook "git -C /tmp/foo merge" | extract_decision)"

# ── chmod（背景3-G） ────────────────────────────────────────────
assert_decision \
  "chmod +x: ワークツリー内の相対パスは allow" \
  "allow" "$(run_hook "chmod +x tests/foo.sh" "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "chmod u+x: シンボリック指定のバリエーションも allow" \
  "allow" "$(run_hook "chmod u+x claude/hooks/new-hook.sh" "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "chmod +x: ワークツリー外の絶対パスは ask（allow に倒れない）" \
  "ask" "$(run_hook "chmod +x /etc/passwd" "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "chmod +x: '..' によるワークツリー脱出は ask（allow に倒れない）" \
  "ask" "$(run_hook "chmod +x ../escaped.sh" "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "chmod +x: シンボリックリンク経由のワークツリー脱出は ask（allow に倒れない）" \
  "ask" "$(run_hook "chmod +x escape-link/payload.sh" "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "chmod +x: .git 配下は ask（allow に倒れない）" \
  "ask" "$(run_hook "chmod +x .git/hooks/pre-commit" "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "chmod -R +x: 再帰指定は ask（allow に倒れない）" \
  "ask" "$(run_hook "chmod -R +x tests" "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "chmod 755: 数値モードは ask（allow に倒れない）" \
  "ask" "$(run_hook "chmod 755 tests/foo.sh" "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "chmod u+x,g-w: 複合指定は ask（allow に倒れない）" \
  "ask" "$(run_hook "chmod u+x,g-w tests/foo.sh" "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "chmod --reference: 未知の意味変更オプションは ask（allow に倒れない）" \
  "ask" "$(run_hook "chmod --reference=tests/foo.sh tests/bar.sh" "$WORKTREE_DIR" | extract_decision)"

# ── chmod/rm: シェル展開前のリテラルを誤って解決しない（レビュー指摘1の回帰）
# bash 自身がこのフックより後でチルダ展開・変数展開・glob・find の {} 展開を
# 行うため、展開後の実際のパスはフックには見えない。フックがこれらのトークンを
# 「たまたま cwd 配下に見える文字列」として誤って解決し allow してしまうと、
# 実際には bash がワークツリー外（実ホームディレクトリ等）へ展開して実行する。
assert_decision \
  "chmod +x ~/bin/x: チルダ展開前の文字列を誤ってワークツリー内と判定しない" \
  "ask" "$(run_hook "chmod +x ~/bin/x" "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "chmod +x \$HOME/foo: 変数展開前の文字列を誤ってワークツリー内と判定しない" \
  "ask" "$(run_hook "chmod +x \$HOME/foo" "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "find -exec chmod +x {} +: findのプレースホルダを対象パスとして解決しない" \
  "ask" "$(run_hook "find . -name '*.sh' -exec chmod +x {} +" "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "chmod +x foo*.sh: glob展開前の文字列を対象パスとして解決しない" \
  "ask" "$(run_hook "chmod +x foo*.sh" "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "rm -rf \$TMPDIR/foo: 変数展開前の文字列は一時ディレクトリ配下と判定しない（ask）" \
  "ask" "$(run_hook "rm -rf \$TMPDIR/foo" "$WORKTREE_DIR" | extract_decision)"

# ── mentions_guarded_command のクォート誤検出対策（レビュー指摘5の回帰） ──
# 引用符の中に語として現れるだけの chmod/rm を、複数コマンド連結時の
# フォールバック判定で誤って ask に倒さない（read-only なコマンドが無人ペインを
# 止める新たな原因にならないようにする）。
assert_decision \
  "grep で 'chmod' を検索するだけの読み取り専用コマンドは連結があっても何も言わない" \
  "(none)" "$(run_hook 'grep -rn "chmod" claude/ | head' "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "grep で 'rm' を検索するだけの読み取り専用コマンドは連結があっても何も言わない" \
  "(none)" "$(run_hook 'grep -rn "rm -rf" claude/ | head' "$WORKTREE_DIR" | extract_decision)"

# ── git/gh は strip_quoted を通さない（ラウンド2レビュー指摘の回帰） ──────
# 引用符の"中身自体が実際に実行されるコマンド"であるケース（sh -c 等）で
# git/gh への言及を見逃すと、フックが唯一の担保である git push --force 等が
# 何の判定も受けずに素通りしてしまう。chmod/rm 用に strip_quoted 化した際、
# git/gh もまとめて strip_quoted してしまっていた回帰（孫1のフェイルセーフを
# 弱めていた）。
assert_decision \
  "sh -c 経由の git push --force は引用符内でも連結扱いで ask（allow に倒れない）" \
  "ask" "$(run_hook 'echo x | sh -c "git push --force origin master"' "$WORKTREE_DIR" | extract_decision)"

# ── rm -r（背景3-G。mktemp -d の後片付けを通すのが目的） ──────────
assert_decision \
  "rm -rf: このセッションの scratchpad 配下は allow" \
  "allow" "$(run_hook 'rm -rf /tmp/claude-1000/some-session/scratchpad' "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "rm -rf: mktemp -d が作る /tmp/tmp.XXXXXXXXXX は allow" \
  "allow" "$(run_hook 'rm -rf /tmp/tmp.AbCdEfGhIj' "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "rm -fr: フラグの順序が違っても同じ判定（allow）" \
  "allow" "$(run_hook 'rm -fr /tmp/tmp.AbCdEfGhIj' "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "rm -r: /tmp 自身は ask（allow に倒れない）" \
  "ask" "$(run_hook 'rm -rf /tmp' "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "rm -r: ワークツリー内は ask（allow に倒れない。コミット前は git でも復元不能）" \
  "ask" "$(run_hook "rm -rf tests/foo.sh" "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "rm -r: /home 配下の絶対パスは ask（allow に倒れない）" \
  "ask" "$(run_hook 'rm -rf /home/someuser/data' "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "rm -r: 未知のオプションは ask（allow に倒れない）" \
  "ask" "$(run_hook 'rm -r --unknown-opt /tmp/tmp.AbCdEfGhIj' "$WORKTREE_DIR" | extract_decision)"

assert_decision \
  "rm（-r 無し）はこのフックの対象外（何も言わない）" \
  "(none)" "$(run_hook "rm tests/foo.sh" "$WORKTREE_DIR" | extract_decision)"

export TMPDIR="$STUB_DIR/customtmp"
mkdir -p "$TMPDIR"
assert_decision \
  "rm -rf: カスタム TMPDIR より深い場所は allow" \
  "allow" "$(run_hook "rm -rf $TMPDIR/tmp.custom123" "$WORKTREE_DIR" | extract_decision)"
assert_decision \
  "rm -rf: カスタム TMPDIR 自身は ask（allow に倒れない）" \
  "ask" "$(run_hook "rm -rf $TMPDIR" "$WORKTREE_DIR" | extract_decision)"
unset TMPDIR

# ── 無関係なコマンドには一切言及しない ───────────────────────────
assert_decision \
  "git/gh と無関係なコマンドは何も言わない" \
  "(none)" "$(run_hook "npm run build" | extract_decision)"

assert_decision \
  "merge/push を伴わない git サブコマンドは何も言わない" \
  "(none)" "$(run_hook "git status" | extract_decision)"

assert_decision \
  "'merge' を含むだけの無関係なコマンド（誤検出対策）は何も言わない" \
  "(none)" "$(run_hook 'git commit -m "merge conflict fix"' | extract_decision)"

# ── Bash 以外のツール呼び出しは対象外 ────────────────────────────
NON_BASH_JSON=$(python3 -c 'import json; print(json.dumps({"tool_name": "Edit", "tool_input": {"command": "git merge master"}}))')
assert_decision \
  "tool_name が Bash 以外なら何も言わない" \
  "(none)" "$(run_hook_raw "$NON_BASH_JSON" | extract_decision)"

# ── 速い経路が "rm" の部分文字列一致で実質無効化されない（レビュー指摘3の回帰） ──
# cwd が "...permissions..." のような "rm" を部分文字列として含むパスのとき、
# 単純な `*"rm"*` では速い経路が常に不成立になり、無関係なコマンドでも
# 毎回 python3 が起動してしまう（実測: 1.7ms → 57ms）。python3 を偽の
# スタブに差し替え、無関係なコマンドでは実際に起動されないことを確認する。
NOPY_DIR="$STUB_DIR/nopython"
mkdir -p "$NOPY_DIR"
cat >"$NOPY_DIR/python3" <<'STUB'
#!/bin/sh
[ -n "${GIT_GUARD_TEST_MARKER:-}" ] && : >"$GIT_GUARD_TEST_MARKER"
exit 1
STUB
chmod +x "$NOPY_DIR/python3"

PERMISSIONS_CWD="/tmp/tmp.fakeworkdir/autopilot-permissions-05-fast-path-test"
FAST_PATH_MARKER="$STUB_DIR/python3-invoked-marker"

rm -f "$FAST_PATH_MARKER"
IRRELEVANT_JSON=$(python3 -c 'import json,sys; print(json.dumps({"cwd": sys.argv[1], "hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": "npm run build"}}))' "$PERMISSIONS_CWD")
RAW_OUTPUT=$(printf '%s' "$IRRELEVANT_JSON" | GIT_GUARD_TEST_MARKER="$FAST_PATH_MARKER" PATH="$NOPY_DIR:$STUB_DIR:$PATH" "$HOOK")
if [ -z "$RAW_OUTPUT" ] && [ ! -e "$FAST_PATH_MARKER" ]; then
  pass "速い経路: cwdに'permissions'を含んでいても無関係なコマンドではpython3を起動しない"
else
  fail "速い経路: cwdに'permissions'を含む場合の無関係コマンド判定（raw_output='$RAW_OUTPUT'、marker存在=$([ -e "$FAST_PATH_MARKER" ] && echo yes || echo no)）"
fi

rm -f "$FAST_PATH_MARKER"
RELEVANT_JSON=$(python3 -c 'import json,sys; print(json.dumps({"cwd": sys.argv[1], "hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": "rm -rf /tmp/foo"}}))' "$PERMISSIONS_CWD")
printf '%s' "$RELEVANT_JSON" | GIT_GUARD_TEST_MARKER="$FAST_PATH_MARKER" PATH="$NOPY_DIR:$STUB_DIR:$PATH" "$HOOK" >/dev/null
if [ -e "$FAST_PATH_MARKER" ]; then
  pass "速い経路: cwdに'permissions'を含んでいても実際の rm コマンドは python3 起動まで届く"
else
  fail "速い経路: 実際の rm コマンドが cwd の 'permissions' 文字列に埋もれて素通りしてしまっている"
fi
rm -f "$FAST_PATH_MARKER"

# ── claude/settings.json の permissions.ask パターン検証 ──────────
# 計画書「設計2」（2026-09-12 訂正）の要求: git push --force-with-lease は
# permissions.ask のどのパターンにも一致してはいけない（フックの allow が
# permissions.ask に上書きされてしまうため）。裸の --force / -f / +<refspec>
# / --delete、ブランチ名が main/master を含む push は、フック不在でも
# 無条件に止まる必要があるため、いずれかのパターンに一致しなければならない。
# 孫5（背景3-G）で同じ理由により chmod / rm -r 系のパターンも narrow 化した:
# ワークツリー内の chmod +x・/tmp 配下（scratchpad・mktemp -d 生成物）への
# rm -r は一致してはいけない。-R/絶対パスの chmod、/home・$HOME・/Users（macOS
# のホーム）等の名指しした危険な絶対パスへの rm -r・chmod は、フック不在でも
# 無条件に止まる必要があるため一致しなければならない（レビュー指摘2の回帰）。
# permissions.ask のマッチングは "*"（空白含む任意文字列）による glob なので
# Python の fnmatch で近似検証する（ADR §3.3 参照）。
PATTERN_CHECK=$(
  python3 - "$REPO_ROOT/claude/settings.json" <<'PYEOF'
import fnmatch
import json
import sys

with open(sys.argv[1]) as f:
    settings = json.load(f)

ask_patterns = [
    p[len("Bash(") : -1]
    for p in settings.get("permissions", {}).get("ask", [])
    if p.startswith("Bash(") and p.endswith(")")
]


def matches_any(command):
    return any(fnmatch.fnmatchcase(command, p) for p in ask_patterns)


# (コマンド, permissions.ask のどれかに一致すべきか)
cases = [
    ("git push --force-with-lease origin feature", False),
    ("git push origin feature --force-with-lease", False),
    ("git push --force-with-lease", False),
    ("git push --force origin feature", True),
    ("git push origin feature --force", True),
    ("git push --force", True),
    ("git push -f origin feature", True),
    ("git push origin +feature:feature", True),
    ("git push origin --delete feature", True),
    ("git push origin main", True),
    ("git push origin master", True),
    ("git push origin feature", False),
    # chmod（背景3-G）: ワークツリー内の相対パスへの +x は、フックが
    # allow を返しても permissions.ask のどのパターンにも一致してはいけない。
    ("chmod +x tests/foo.sh", False),
    ("chmod u+x claude/hooks/new-hook.sh", False),
    # フック不在でも無条件に止めたいもの（-R/絶対パス）は一致する必要がある。
    ("chmod -R +x tests", True),
    ("chmod --recursive +x tests", True),
    ("chmod -v -R +x tests", True),
    ("chmod +x /etc/passwd", True),
    # rm -r（背景3-G。mktemp -d の後片付けを通すのが目的）:
    # /tmp 配下（scratchpad・mktemp -d 生成物）は一致してはいけない。
    ("rm -rf /tmp/tmp.AbCdEfGhIj", False),
    ("rm -rf /tmp/claude-1000/some-session/scratchpad", False),
    # フック不在でも無条件に止めたい、名指しした危険な絶対パスは一致する必要がある。
    ("rm -rf /home/someuser/data", True),
    ("rm -r /home/someuser/data", True),
    ("rm -fr /usr/local/foo", True),
    ("rm -rf /etc/foo", True),
    ("rm -rf /var/foo", True),
    ("rm -rf /mnt/foo", True),
    ("rm -rf /opt/foo", True),
    ("rm -rf ~/secrets", True),
    # レビュー指摘2の回帰: $HOME・macOS のホーム /Users も名指しした網に要る。
    ("rm -rf $HOME/secrets", True),
    ("rm -r $HOME/secrets", True),
    ("rm -fr /Users/someuser/data", True),
    ("rm -rf /Users/someuser/data", True),
    ("chmod +x ~/bin/x", True),
    ("chmod +x $HOME/bin/x", True),
    # 受け入れる残余リスク（ADR に明記）: ワークツリー内の相対パスへの
    # rm -r は名指しの網に無い。フックが唯一の担保（フック不在時は fail-open）。
    ("rm -rf tests/foo.sh", False),
]

ok = True
for command, expected in cases:
    actual = matches_any(command)
    if actual != expected:
        ok = False
        print(f"NG: {command!r} -> matches={actual} expected={expected}", file=sys.stderr)

sys.exit(0 if ok else 1)
PYEOF
)
PATTERN_CHECK_RC=$?
if [ "$PATTERN_CHECK_RC" -eq 0 ]; then
  pass "claude/settings.json の permissions.ask: force-with-lease 非一致・裸force等の一致を確認"
else
  fail "claude/settings.json の permissions.ask パターン検証: $PATTERN_CHECK"
fi

if [ "$FAIL" -eq 0 ]; then
  log "=== git-guard.sh テスト: 全件成功 ==="
else
  log "=== git-guard.sh テスト: 失敗あり ==="
fi

# 明示的な exit は使わない（tests/deploy_smoke.sh と同じ理由）。shellcheck は
# 「trap で登録した関数の後に exit があると、その関数への呼び出しが無い
# （SC2329）」と誤検知する既知の癖があるため、最後の式の終了コードを
# そのままスクリプトの終了コードにする。
[ "$FAIL" -eq 0 ]
