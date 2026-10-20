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

# run_hook <role> <session> <transcript> [extra-kind]
# extra-kind: big（tool_response が 128 KiB 超）/ subagent（agent_id 付き）/
#   commit・push・prcreate・prompt（区切りの Bash）/ sendmsg（SendMessage）/ ls（区切りでない Bash）
run_hook() {
  local role="$1" session="$2" transcript="$3" extra="${4:-}"
  local json
  json=$(python3 -c '
import json, sys
d = {"session_id": sys.argv[1], "transcript_path": sys.argv[2],
     "hook_event_name": "PostToolUse", "tool_name": "Bash"}
if sys.argv[3] == "big":
    d["tool_response"] = {"stdout": "x" * 300000}
cmds = {"commit": "git commit -m x", "push": "git push --force-with-lease",
        "prcreate": "gh pr create --base token-levers", "prompt": "herdr agent prompt p1 hi",
        "ls": "ls -la"}
if sys.argv[3] in cmds:
    d["tool_input"] = {"command": cmds[sys.argv[3]]}
if sys.argv[3] == "sendmsg":
    d["tool_name"] = "SendMessage"
    d["tool_input"] = {"to": "x", "message": "hi"}
if sys.argv[3] == "subagent":
    d["agent_id"] = "a1b2c3"
    d["agent_type"] = "Explore"
print(json.dumps(d))
' "$session" "$transcript" "$extra")
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

log "--- 区切りのツール呼び出し（1区切り1回） ---"
S=s-bnd
write_transcript "$T" 210000
assert_speaks "区切りでない呼び出しで閾値超えの最初の 1 回は差し込む" "$(run_hook implementer $S "$T" ls)"
write_transcript "$T" 215000
out=$(run_hook implementer $S "$T" commit)
assert_speaks "50k 未満の増加でも、区切り（git commit）なら差し込む" "$out"
case "$out" in *"1行書く"*) pass "区切りの文面は compact するか見送るかを1行書かせる" ;; *) fail "区切りの文面が想定と違う (got: $out)" ;; esac
write_transcript "$T" 218000
assert_silent "同じ区切り（commit → push → PR 作成）では繰り返さない" "$(run_hook implementer $S "$T" push)$(run_hook implementer $S "$T" prcreate)"
write_transcript "$T" 220000
assert_silent "区切りでない呼び出しは 50k 未満なら黙る" "$(run_hook implementer $S "$T" ls)"
# コミット系のクールダウン中でも、依頼系（再レビュー依頼）の区切りには届く。
assert_speaks "コミットの直後でも、再レビュー依頼（herdr agent prompt）の直後には差し込む" "$(run_hook implementer $S "$T" prompt)"
assert_silent "同じ依頼系の区切り（SendMessage）では繰り返さない" "$(run_hook implementer $S "$T" sendmsg)"
# クールダウンを過去へずらして、次の区切りとみなす（2行目がコミット系、3行目が依頼系）。
python3 - "$XDG_STATE_HOME/dotfiles/compact-reminder/$S" <<'PY'
import sys
ctx = open(sys.argv[1]).read().split()[0]
open(sys.argv[1], "w").write("%s\n%f\n%f" % (ctx, 1.0, 1.0))
PY
assert_speaks "次のコミット系の区切りでは再び差し込む" "$(run_hook implementer $S "$T" commit)"
assert_speaks "次の依頼系の区切り（SendMessage）でも再び差し込む" "$(run_hook implementer $S "$T" sendmsg)"
write_transcript "$T" 190000
assert_silent "区切りでも閾値以下なら黙る" "$(run_hook implementer s-bnd-low "$T" commit)"
write_transcript "$T" 300000
assert_silent "区切りでもサブエージェントなら黙る" "$(run_hook implementer s-bnd-sub "$T" subagent)"

log "--- 対象外の役割で python3 を起動しない ---"
# 全ツール呼び出しで走るので、区切りの判定を足しても対象外の役割は python3 を起動してはならない。
FAKEBIN="$TMP/fakebin"
mkdir -p "$FAKEBIN"
printf '#!/bin/sh\necho called >>"%s/python-calls"\nexit 0\n' "$TMP" >"$FAKEBIN/python3"
chmod +x "$FAKEBIN/python3"
write_transcript "$T" 300000
for r in commander reviewer ""; do
  if [ -n "$r" ]; then
    printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | OCW_ROLE="$r" PATH="$FAKEBIN:$PATH" "$HOOK"
  else
    printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}' | env -u OCW_ROLE PATH="$FAKEBIN:$PATH" "$HOOK"
  fi
done
if [ ! -e "$TMP/python-calls" ]; then pass "commander・reviewer・未設定では python3 を起動しない"; else fail "対象外の役割で python3 が起動された"; fi

log "--- 実入力の形（大きい tool_response・サブエージェント） ---"
# PostToolUse は matcher なしで全ツールの出力を含む。引数渡しだと 128 KiB 超で exec が失敗し、
# 文脈が最も増える呼び出しで通知が落ちる。
S=s-extra
write_transcript "$T" 300000
assert_speaks "128 KiB 超の tool_response でも差し込む" "$(run_hook implementer $S "$T" big)"
# サブエージェントの呼び出しは黙り、間引き状態も進めない（そのあと本体の呼び出しでは差し込む）。
S=s-sub
assert_silent "agent_id 付き（サブエージェント）では閾値超えでも黙る" "$(run_hook implementer $S "$T" subagent)"
assert_speaks "サブエージェントは状態を進めず、本体の呼び出しでは差し込む" "$(run_hook implementer $S "$T")"

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
