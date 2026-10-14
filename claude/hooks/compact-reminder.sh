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

# ペイロードは stdin ではなく引数で渡す（ヒアドキュメントが stdin を占有するため。git-guard.sh と同じ）。
INPUT="$(cat)"

COMPACT_REMINDER_STATE_ROOT="$STATE_ROOT" python3 - "$INPUT" <<'PYEOF'
import json
import os
import sys

# 閾値は pr-review-loop の「区切りでの自己 compact」と同じ 200,000。
THRESHOLD = 200000
# 差し込んだあと、文脈がこれだけ増えるまでは再掲しない（毎回差し込むと
# それ自体が文脈を太らせ、無視されるようにもなる）。
STEP = 50000
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


def main():
    payload = json.loads(sys.argv[1])
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
    last = None
    try:
        with open(state_file) as f:
            last = int(f.read().strip())
    except Exception:
        pass

    if ctx <= THRESHOLD:
        # compact で閾値以下に戻った。次に超えたとき最初の 1 回から差し込めるよう消す。
        if last is not None:
            try:
                os.remove(state_file)
            except OSError:
                pass
        return

    if last is not None and ctx < last + STEP:
        return

    os.makedirs(STATE_ROOT, exist_ok=True)
    with open(state_file, "w") as f:
        f.write(str(ctx))

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
exit 0
