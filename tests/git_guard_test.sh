#!/usr/bin/env bash
#
# tests/git_guard_test.sh — claude/hooks/git-guard.sh のスタンドアロンテスト。
#
# 2つの観点を同じ重みで検証する（ADR
# docs/adr/DOC-2609121719_git-operation-permission-policy.md、claude/README.md §3.5）。
#
#   1. 判定表: `gh pr merge` の base が保護ブランチなら deny、それ以外は allow
#   2. **無音でなければならない操作**: autopilot（傘ブランチ方式の無人運転）が
#      日常的に行うコマンドが1つも承認ダイアログを出さない（= フックが何も言わない）
#
# 2 は PR #94 のレビューが見落とした観点であり、そのまま「`cd <repo> && git status`
# が全部 ask になる」回帰を通した直接の原因になった。**1 を足すときは必ず 2 も足す。**
#
# gh を PATH 先頭のスタブに差し替えるため、ネットワークにも実リポジトリの状態にも
# 依存しない。
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
GH_ARGS_FILE="$STUB_DIR/gh-args"

# gh スタブ: `gh [<グローバルオプション>] pr view [<target>] --json baseRefName -q ...`
# に応答する。受け取った引数を $GH_ARGS_FILE に記録するので、フックが
# `-R <owner/repo>` を引き継いだかを検証できる。
# GIT_GUARD_TEST_BASE_REF（export 必須）が空なら失敗する（base 解決不能を模擬）。
cat >"$STUB_DIR/gh" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >"$GH_ARGS_FILE"
if [ -z "${GIT_GUARD_TEST_BASE_REF:-}" ]; then
  exit 1
fi
printf '%s\n' "$GIT_GUARD_TEST_BASE_REF"
exit 0
STUB
chmod +x "$STUB_DIR/gh"
export GH_ARGS_FILE

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
# を取り出す。出力が空なら "(none)" を返す（＝何も言わない）。
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

# assert_silent <label> <command>
# 「何も言わない」ことだけを主張する。無音一覧はこれで固定する。
assert_silent() {
  assert_decision "$1" "(none)" "$(run_hook "$2" | extract_decision)"
}

log "=== git-guard.sh テスト ==="

# ── 1. 判定表（フックが担保する唯一の1点） ───────────────────────
log "--- gh pr merge の base 判定 ---"

export GIT_GUARD_TEST_BASE_REF="master"
assert_decision \
  "gh pr merge: base=master は deny" \
  "deny" "$(run_hook "gh pr merge 1 --squash --delete-branch" | extract_decision)"

assert_decision \
  "gh pr merge: 連結コマンドの中でも deny（連結で迂回できない）" \
  "deny" "$(run_hook "cd /tmp && gh pr merge 1 --squash" | extract_decision)"

assert_decision \
  "gh pr merge: --body の値をマージ対象と取り違えない" \
  "deny" "$(run_hook "gh pr merge --squash -b 'merge 済み' 42" | extract_decision)"

# -R は対象リポジトリを cwd から動かすため、cwd 基準の base 解決は成立しない。
# gh pr view 側へ引き継げているかを引数の実物で検証する。
: >"$GH_ARGS_FILE"
assert_decision \
  "gh -R <owner/repo> pr merge: base=master なら deny" \
  "deny" "$(run_hook "gh -R other/repo pr merge 7 --squash" | extract_decision)"
if grep -q -- "-R other/repo" "$GH_ARGS_FILE"; then
  pass "gh -R <owner/repo> が gh pr view へ引き継がれている"
else
  fail "gh -R <owner/repo> が gh pr view へ引き継がれていない (args: $(cat "$GH_ARGS_FILE"))"
fi

export GIT_GUARD_TEST_BASE_REF="main"
assert_decision \
  "gh pr merge: base=main は deny" \
  "deny" "$(run_hook "gh pr merge --squash" | extract_decision)"

export GIT_GUARD_TEST_BASE_REF="git-guard-regressions"
assert_decision \
  "gh pr merge: base=傘ブランチは allow（孫→傘のマージは無音で通す）" \
  "allow" "$(run_hook "gh pr merge 12 --squash --delete-branch" | extract_decision)"
unset GIT_GUARD_TEST_BASE_REF

# GIT_GUARD_TEST_BASE_REF 未設定 → gh スタブが失敗 → base 解決不能。
# 初版は ask に倒していた。判定できないときは何も言わない（既存の permissions に委ねる）。
assert_silent \
  "gh pr merge: base 解決不能でも ask に倒さない" \
  "gh pr merge 999999 --squash"

assert_silent \
  "gh pr view（merge 以外のサブコマンド）は対象外" \
  "gh pr view 12 --json title"

assert_decision \
  "tool_name が Bash 以外なら何も言わない" \
  "(none)" "$(run_hook_raw '{"tool_name":"Read","tool_input":{"file_path":"gh pr merge"}}' | extract_decision)"

# ── 2. 無音でなければならない操作 ────────────────────────────────
# autopilot が日常的に行うコマンド。ここに1つでも ask が出ると無人ペインが
# 止まり、傘ブランチ方式が成立しない。フックは「何も言わない」こと。
log "--- 無音でなければならない操作 ---"

assert_silent "傘の上流追随: git fetch" "git fetch origin"
assert_silent "傘の上流追随: git merge origin/master" "git merge origin/master"
assert_silent "傘の rebase 追随" "git rebase origin/master"
assert_silent \
  "傘ブランチへの force-with-lease" \
  "git push --force-with-lease origin git-guard-regressions"
assert_silent \
  "孫ブランチへの force-with-lease（refspec 省略）" \
  "git push --force-with-lease"
assert_silent "孫ブランチの初回 push" "git push -u origin ph-01-foo"
assert_silent "読み取り専用の連結: cd && git status" "cd /home/x/repo && git status"
assert_silent \
  "読み取り専用の連結: ; 区切り" \
  "git log --oneline -1; git branch --show-current"
assert_silent "読み取り専用の連結: パイプ" "git log | head"
assert_silent "読み取り専用の連結: パイプ + grep" "git status | grep modified"
assert_silent "連結した書き込み操作: add && commit" 'git add -A && git commit -m "回帰を潰す"'
assert_silent "別ディレクトリ指定: git -C <dir> status" "git -C /home/x/other status"
assert_silent "別ディレクトリ指定: git -C <dir> log" "git -C /home/x/other log --oneline -1"
assert_silent "別ディレクトリ指定: git -C <dir> merge" "git -C /home/x/other merge origin/master"
assert_silent \
  "ループ内の cd && git（PR #94 で実際に最初に止まったコマンド）" \
  "for r in a b; do cd \$r && git config --get ocw.worktreeDir; done"
assert_silent "chmod +x" "chmod +x tools/doc-id/doc-id"
assert_silent "一時ディレクトリの後片付け" "rm -rf /tmp/tmp.AbCdEf"
assert_silent "コミットメッセージに merge を含む" 'git commit -m "merge 済み; 掃除も"'
assert_silent "トークン化できない入力（git）" 'git commit -m "unbalanced'
assert_silent "トークン化できない入力（gh pr merge）" 'gh pr merge "unbalanced'
assert_silent "gh pr merge に言及するだけの文字列" 'grep -rn "gh pr merge" docs/'

# master への push はフックではなく claude/settings.json の permissions.ask
# グロブ（Bash(git push * master*)）が受け持つ。フック側は無音であること。
assert_silent \
  "master への push はフックの担当外（グロブが受け持つ）" \
  "git push origin master"

log ""
if [ "$FAIL" -eq 0 ]; then
  log "=== git-guard.sh テスト: 全件成功 ==="
else
  log "=== git-guard.sh テスト: 失敗あり ===" >&2
fi

# 明示的な exit は使わない（tests/deploy_smoke.sh と同じ理由）。shellcheck は
# 「trap で登録した関数の後に exit があると、その関数への呼び出しが無い
# （SC2329）」と誤検知する既知の癖があるため、最後の式の終了コードを
# そのままスクリプトの終了コードにする。
[ "$FAIL" -eq 0 ]
