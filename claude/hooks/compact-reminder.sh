#!/bin/sh
#
# claude/hooks/compact-reminder.sh — PostToolUse フック。
#
# 実装の孫（OCW_ROLE=implementer）の文脈が閾値を超えていたら、「区切りなら
# self-compact を判断すること」と一文を差し込む（additionalContext）。
# **compact そのものは打たない**（コマンドを実行しない）。判断は孫に任せる。
#
# 判断の機会がスキル本文の特定の区切りにしか無く、作業に没頭すると判断自体が
# 起きないため、それを補う仕組み。閾値・区切り・回数の上限は ADR
# DOC-2610142337（実装途中の自己 compact）に合わせてあり、フック自身の決定は
# ADR DOC-2610142359 を参照。
#
# 差し込みは2種類。(1) 区切りに当たるツール呼び出し（git commit / git push /
# gh pr create / herdr agent prompt / SendMessage）で閾値超えなら、1区切り1回。
# 区切りの近くに届けば判断が起きるため。(2) 区切りでない呼び出しでは、従来どおり
# 閾値超えの最初の 1 回と、その後 50k 増えるごと。
#
# 何も言わない（exit 0・出力なし）条件:
#   - OCW_ROLE が implementer でない（司令官・レビュワー・未設定）
#   - 文脈が閾値以下 / transcript が読めない / 入力が壊れている / python3 が無い
#   - 直近に差し込んだ文脈から増分が足りない（間引き）
# いずれもエージェントを止めない（git-guard.sh と同じ方針）。

# 全ツール呼び出しで走るため、対象外の役割は python3 を起動せずに捨てる。
[ "${OCW_ROLE:-}" = "implementer" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

# 状態（セッションごとに最後に差し込んだときの文脈の大きさ）はリポ外へ置く。
STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/compact-reminder"

# ペイロードは stdin のまま python3 へ渡す。引数1つで渡すと、tool_response（ツール出力全体）が
# 128 KiB（Linux の MAX_ARG_STRLEN）を超えたとき exec が E2BIG で失敗する。git-guard.sh は
# matcher が Bash の PreToolUse でコマンド文字列しか受けないため引数渡しで足りるが、このフックは
# matcher なしの PostToolUse で、大きい入力が来る。そのため python のコードの側を -c で渡す。
PY_SRC="$(
  cat <<'PYEOF'
import json
import os
import re
import sys
import time

# 閾値は pr-review-loop の「区切りでの自己 compact」と同じ 200,000。
THRESHOLD = 200000
# 差し込んだあと、文脈がこれだけ増えるまでは再掲しない（毎回差し込むと
# それ自体が文脈を太らせ、無視されるようにもなる）。
STEP = 50000
# 区切りのリマインドを出したあと、これだけ経つまでは同じ種類の区切りでは出さない。
# 種類は 2 つで、互いのクールダウンを消費しない: コミット系（git commit → git push →
# gh pr create の一続きを 1 区切りとする）と、依頼系（レビュー・再レビューの依頼や報告。
# コミット系の直後 5 分以内に来る本命の区切りを黙らせないため）。
BOUNDARY_COOLDOWN = 300
COMMIT_RE = re.compile(
    r"\bgit\s+(?:-C\s+\S+\s+)?(?:commit|push)\b"
    r"|\bgh\s+pr\s+create\b"
)
REQUEST_RE = re.compile(r"\bherdr\s+agent\s+prompt\b")
REQUEST_TOOLS = ("SendMessage",)
# transcript は数十 MB になりうる。末尾だけを読む。1 行が大きい（ツール結果）
# ことがあるので、直近の assistant 行が入る余裕を見て 1 MiB。
TAIL_BYTES = 1024 * 1024

STATE_ROOT = os.environ["COMPACT_REMINDER_STATE_ROOT"]


def context_size(path):
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        size = f.tell()
        start = max(0, size - TAIL_BYTES)
        f.seek(start)
        data = f.read()
    lines = data.split(b"\n")
    if start > 0:
        lines = lines[1:]  # 先頭は行の途中で切れている
    for raw in reversed(lines):
        if b"\"assistant\"" not in raw or b"\"usage\"" not in raw:
            continue
        try:
            entry = json.loads(raw)
            usage = entry["message"]["usage"]
            return (
                usage.get("input_tokens", 0)
                + usage.get("cache_read_input_tokens", 0)
                + usage.get("cache_creation_input_tokens", 0)
            )
        except Exception:
            continue
    return None


def boundary_kind(payload):
    """区切りの種類（"commit" / "request"）。区切りでなければ None。"""
    if payload.get("tool_name") in REQUEST_TOOLS:
        return "request"
    if payload.get("tool_name") != "Bash":
        return None
    tool_input = payload.get("tool_input")
    command = tool_input.get("command") if isinstance(tool_input, dict) else None
    if not isinstance(command, str):
        return None
    if REQUEST_RE.search(command):
        return "request"
    if COMMIT_RE.search(command):
        return "commit"
    return None


def read_state(path):
    """(最後に差し込んだ文脈, {区切りの種類: 最後のリマインドの時刻})。無ければ None / 空。"""
    last = None
    at = {}
    try:
        with open(path) as f:
            lines = f.read().split()
        last = int(lines[0])
        for kind, raw in zip(("commit", "request"), lines[1:3]):
            at[kind] = float(raw)
    except Exception:
        pass
    return last, at


def main():
    payload = json.load(sys.stdin)
    # サブエージェントのツール呼び出しでも、同じフックが発火して agent_id が入る。
    # 通知が親の孫に届かず、サブエージェントが親のペインを compact しうるので黙る。
    if payload.get("agent_id"):
        return
    session_id = payload.get("session_id")
    transcript = payload.get("transcript_path")
    if not isinstance(session_id, str) or not isinstance(transcript, str):
        return
    # セッション ID をファイル名に使うので、パス区切りを含むものは捨てる。
    if not session_id or "/" in session_id or session_id.startswith("."):
        return

    ctx = context_size(transcript)
    if ctx is None:
        return

    state_file = os.path.join(STATE_ROOT, session_id)
    last, boundary_at = read_state(state_file)

    if ctx <= THRESHOLD:
        # compact で閾値以下に戻った。次に超えたとき最初の 1 回から差し込めるよう消す。
        if last is not None:
            try:
                os.remove(state_file)
            except OSError:
                pass
        return

    now = time.time()
    boundary = boundary_kind(payload)
    if boundary:
        if now - boundary_at.get(boundary, 0) < BOUNDARY_COOLDOWN:
            return
    elif last is not None and ctx < last + STEP:
        return

    os.makedirs(STATE_ROOT, exist_ok=True)
    with open(state_file, "w") as f:
        # 区切りの時刻は種類ごとに持ち、ほかの差し込みでは引き継ぐ（無い種類は 0）。
        if boundary:
            boundary_at[boundary] = now
        f.write(
            "%d\n%f\n%f"
            % (ctx, boundary_at.get("commit", 0), boundary_at.get("request", 0))
        )

    if boundary:
        message = (
            "[compact-reminder] 文脈が約 %dk トークン（閾値 200k 超）で、いまは区切りのツール"
            "呼び出しの直後。**次のターンの冒頭で、`ocw self-compact` で compact するか見送るかを"
            "1行書くこと（見送るなら理由も）。** WIP のコミット・指摘対応の修正の途中・承認後の"
            "報告は区切りでないので見送ってよい。区切りなら compact する（手順は自動付与指示と pr-review-loop"
            "「区切りでの自己 compact」）。"
        ) % (ctx // 1000)
    else:
        message = (
        "[compact-reminder] 文脈が約 %dk トークン（閾値 200k 超）。"
        "検証が通ってコミットした直後、またはレビュー（再レビュー）を依頼した直後の"
        "区切りなら、`ocw self-compact` で自分を compact するか判断すること"
        "（手順は自動付与指示と pr-review-loop「区切りでの自己 compact」。"
        "WIP のコミットと指摘対応の修正の途中は区切りでない）。"
        "区切りでなければ続けてよい。この通知は約 50k 増えるごとに再掲する。"
        ) % (ctx // 1000)
    out = {
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": message,
        }
    }
    sys.stdout.write(json.dumps(out, ensure_ascii=False) + "\n")


try:
    main()
except Exception:
    pass
PYEOF
)"

COMPACT_REMINDER_STATE_ROOT="$STATE_ROOT" python3 -c "$PY_SRC"
exit 0
