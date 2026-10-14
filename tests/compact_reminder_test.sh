#!/usr/bin/env bash
#
# tests/compact_reminder_test.sh — claude/hooks/compact-reminder.sh のスタンドアロンテスト。
#
# 入力 JSON（PostToolUse）と transcript を与えて、差し込む／黙るを確かめる。
# 状態ファイルは XDG_STATE_HOME を一時ディレクトリに向けるため、実 $HOME に触れない。
#
# Usage:
#   tests/compact_reminder_test.sh
set -uo pipefail

SCRIPT_DIR=$(
  cd "$(dirname "$0")" || exit 1
  pwd
)
REPO_ROOT=$(
  cd "$SCRIPT_DIR/.." || exit 1
  pwd
)
HOOK="$REPO_ROOT/claude/hooks/compact-reminder.sh"

FAIL=0
TMP=""

log() { printf '%s\n' "$*"; }
pass() { printf '  [PASS] %s\n' "$1"; }
fail() {
  printf '  [FAIL] %s\n' "$1" >&2
  FAIL=1
}

cleanup() {
  [ -n "$TMP" ] && rm -rf "$TMP"
}
trap cleanup EXIT

TMP="$(mktemp -d)"
export XDG_STATE_HOME="$TMP/state"

# write_transcript <path> <context-tokens>
# 直近の assistant 行の usage 合計が <context-tokens> になる transcript を作る。
# 手前に巨大な行（ツール結果相当）を置き、末尾だけを読む実装でも壊れないことを兼ねる。
write_transcript() {
  python3 - "$1" "$2" <<'PY'
import json, sys
path, ctx = sys.argv[1], int(sys.argv[2])
with open(path, "w") as f:
    f.write(json.dumps({"type": "user", "message": {"content": "x" * 3_000_000}}) + "\n")
    f.write(json.dumps({"type": "assistant", "message": {"usage": {
        "input_tokens": 10, "cache_read_input_tokens": ctx - 10 - 5,
        "cache_creation_input_tokens": 5}}}) + "\n")
    f.write(json.dumps({"type": "user", "message": {"content": "tool result"}}) + "\n")
PY
}

# run_hook <role> <session> <transcript>
run_hook() {
  local role="$1" session="$2" transcript="$3"
  local json
  json=$(python3 -c '
import json, sys
print(json.dumps({"session_id": sys.argv[1], "transcript_path": sys.argv[2],
                  "hook_event_name": "PostToolUse", "tool_name": "Bash"}))
' "$session" "$transcript")
  if [ -n "$role" ]; then
    printf '%s' "$json" | OCW_ROLE="$role" "$HOOK"
  else
    printf '%s' "$json" | env -u OCW_ROLE "$HOOK"
  fi
}

assert_speaks() {
  local label="$1" out="$2"
  if printf '%s' "$out" | python3 -c '
import json, sys
d = json.load(sys.stdin)["hookSpecificOutput"]
assert d["hookEventName"] == "PostToolUse" and "self-compact" in d["additionalContext"]
' 2>/dev/null; then
    pass "$label"
  else
    fail "$label (got: $out)"
  fi
}

assert_silent() {
  if [ -z "$2" ]; then pass "$1"; else fail "$1 (got: $2)"; fi
}

log "=== compact-reminder.sh テスト ==="

T="$TMP/t.jsonl"

log "--- 役割の絞り込み ---"
write_transcript "$T" 300000
assert_silent "commander では黙る" "$(run_hook commander s-role "$T")"
assert_silent "reviewer では黙る" "$(run_hook reviewer s-role "$T")"
assert_silent "OCW_ROLE 未設定では黙る" "$(run_hook "" s-role "$T")"

log "--- 閾値と間引き（同一セッション） ---"
S=s-thr
write_transcript "$T" 200000
assert_silent "閾値ちょうど（200,000）では黙る" "$(run_hook implementer $S "$T")"
write_transcript "$T" 200001
assert_speaks "閾値超えで最初の 1 回は差し込む" "$(run_hook implementer $S "$T")"
write_transcript "$T" 249999
assert_silent "直近の差し込みから 50k 未満の増加では黙る" "$(run_hook implementer $S "$T")"
write_transcript "$T" 250001
assert_speaks "50k 増えたら再掲する" "$(run_hook implementer $S "$T")"
write_transcript "$T" 80000
assert_silent "compact で閾値以下に戻ると黙る" "$(run_hook implementer $S "$T")"
write_transcript "$T" 210000
assert_speaks "戻ったあと再び超えたら最初の 1 回から差し込む" "$(run_hook implementer $S "$T")"

log "--- 判定できない入力では黙り、止めない ---"
printf 'not json' | OCW_ROLE=implementer "$HOOK"
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "壊れた入力でも exit 0"
else
  fail "壊れた入力で exit $rc"
fi
assert_silent "transcript が無いと黙る" "$(run_hook implementer s-missing "$TMP/nonexistent.jsonl")"
printf 'garbage\n{"type":"assistant"\n' >"$TMP/bad.jsonl"
assert_silent "usage を読めない transcript では黙る" "$(run_hook implementer s-bad "$TMP/bad.jsonl")"
write_transcript "$T" 300000
assert_silent "session_id にパス区切りがあると黙る" "$(run_hook implementer "../evil" "$T")"

# 明示的な exit は使わない（git_guard_test.sh と同じ理由。trap の後の exit は SC2329 を誤検知する）。
[ "$FAIL" -eq 0 ]
