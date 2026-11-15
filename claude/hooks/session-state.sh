#!/bin/sh
#
# claude/hooks/session-state.sh — 会話ごとの状態を「落ちる直前まで」記録するフック。
#
# WSL / Windows の再起動のあと、bin/herdr-resume が「再開してよい会話」だけへ再開を送るための
# 入力を書く（計画書 DOC-2611151244 設計2・ADR DOC-2611151247）。Herdr の agent_status は
# 再起動で失われるので、会話の側で状態を書き続ける。
#
# 書く場所: ${XDG_STATE_HOME:-$HOME/.local/state}/reboot-recovery/sessions/<session_id>.json
#   state      working | idle | blocked | ended
#   updated_at 最後に状態が変わった UNIX 秒
#   crons      {<id>: 作った UNIX 秒}  CronCreate で足し CronDelete で消す
#
# 受けるイベント（claude/settings.json で登録）:
#   UserPromptSubmit                      -> working
#   Stop                                  -> idle
#   Notification(permission_prompt /
#                elicitation_dialog)      -> blocked（承認・質問待ち）
#   PreToolUse(AskUserQuestion)           -> blocked
#   PostToolUse(任意)                     -> blocked だったなら working（承認されて動き出した）
#   PostToolUse(CronCreate / CronDelete)  -> crons を更新
#   SessionEnd                            -> ended（人間が終えた会話は再開しない）
#
# 全ツール呼び出しで走るため速く保つ。**失敗しても会話を止めない**（書けない・入力が壊れている・
# python3 が無い、のどれでも何も言わず exit 0。git-guard.sh / compact-reminder.sh と同じ方針）。

command -v python3 >/dev/null 2>&1 || exit 0

STATE_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/reboot-recovery"

PY_SRC="$(
  cat <<'PYEOF'
import json
import os
import re
import sys
import tempfile
import time

CRON_TOOLS = ("CronCreate", "CronDelete")


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            rec = json.load(f)
        return rec if isinstance(rec, dict) else {}
    except (OSError, ValueError):
        return {}


def save(path, rec):
    d = os.path.dirname(path)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".tmp-")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(rec, f, ensure_ascii=False)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def cron_id(obj):
    """CronCreate の応答から id を拾う。形が分からないので緩く探す。"""
    if isinstance(obj, dict):
        for key in ("id", "job_id", "jobId", "cron_id"):
            if isinstance(obj.get(key), str) and obj[key]:
                return obj[key]
    text = obj if isinstance(obj, str) else json.dumps(obj, ensure_ascii=False)
    m = re.search(r"""["']?(?:job[_ ]?)?id["']?\s*[:=]?\s*["']?([0-9A-Za-z_-]{6,})""", text)
    return m.group(1) if m else None


def main():
    payload = json.load(sys.stdin)
    sid = payload.get("session_id")
    event = payload.get("hook_event_name")
    # session_id はファイル名になる。想定外の文字は捨てる（パス区切りの混入を防ぐ）。
    if not isinstance(sid, str) or not re.fullmatch(r"[0-9A-Za-z_-]{1,128}", sid):
        return
    root = os.environ["STATE_ROOT"]
    path = os.path.join(root, "sessions", sid + ".json")
    now = int(time.time())
    tool = payload.get("tool_name")

    new_state = None
    if event == "UserPromptSubmit":
        new_state = "working"
    elif event == "Stop":
        new_state = "idle"
    elif event == "SessionEnd":
        # 人間が終えたと分かる理由だけ ended にする。other などは WSL の停止に伴う終了でも出うるので、
        # 直前の状態を残す（全会話が ended で上書きされて再開が全滅するのを防ぐ）。
        if payload.get("reason") in ("prompt_input_exit", "logout", "clear", "resume"):
            new_state = "ended"
    elif event == "Notification":
        if payload.get("notification_type") in ("permission_prompt", "elicitation_dialog"):
            new_state = "blocked"
    elif event == "PreToolUse" and tool == "AskUserQuestion":
        new_state = "blocked"
    elif event not in ("PostToolUse",):
        return

    rec = load(path)
    changed = False

    if event == "PostToolUse":
        if tool in CRON_TOOLS:
            crons = rec.get("crons") if isinstance(rec.get("crons"), dict) else {}
            if tool == "CronCreate":
                tin0 = payload.get("tool_input")
                # 一回きりのジョブ（recurring: false）は実行後に自分で消え、CronDelete も来ない。
                # 巡回として数えない。
                if not (isinstance(tin0, dict) and tin0.get("recurring") is False):
                    key = cron_id(payload.get("tool_response")) or "anon-%d" % now
                    crons[key] = now
            else:
                tin = payload.get("tool_input") if isinstance(payload.get("tool_input"), dict) else {}
                key = cron_id(tin)
                if key in crons:
                    del crons[key]
                else:
                    # id が分からない削除は、いちばん古い1件を消す（増えたままにしない）。
                    if crons:
                        del crons[min(crons, key=crons.get)]
            rec["crons"] = crons
            changed = True
        if rec.get("state") == "blocked":
            new_state = "working"

    if new_state is not None and (rec.get("state") != new_state or event != "PostToolUse"):
        rec["state"] = new_state
        rec["updated_at"] = now
        changed = True
    if not changed:
        return
    rec["session_id"] = sid
    if isinstance(payload.get("cwd"), str):
        rec["cwd"] = payload["cwd"]
    rec["last_event"] = event
    if isinstance(payload.get("transcript_path"), str):
        rec["transcript_path"] = payload["transcript_path"]
    save(path, rec)


try:
    main()
except BaseException:
    pass
PYEOF
)"

# ペイロードは stdin のまま python3 へ渡す（引数にすると大きい tool_response で E2BIG になりうる。
# compact-reminder.sh と同じ理由）。python 側のコードは -c で渡す。
STATE_ROOT="$STATE_ROOT" python3 -c "$PY_SRC" 2>/dev/null
exit 0
