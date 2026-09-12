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

# git スタブ: `git rev-parse --abbrev-ref HEAD` にのみ応答する。
# GIT_GUARD_TEST_CURRENT_BRANCH（export 必須。未設定なら "current-branch"）を返す。
# GIT_GUARD_TEST_GIT_FAIL=1 のときは非ゼロ終了する（現在のブランチ解決失敗を模擬）。
cat >"$STUB_DIR/git" <<'STUB'
#!/bin/sh
if [ "${GIT_GUARD_TEST_GIT_FAIL:-0}" = "1" ]; then
  exit 1
fi
if [ "$1" = "rev-parse" ] && [ "$2" = "--abbrev-ref" ] && [ "$3" = "HEAD" ]; then
  printf '%s\n' "${GIT_GUARD_TEST_CURRENT_BRANCH:-current-branch}"
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
