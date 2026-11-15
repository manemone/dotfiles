"""bin/herdr-resume の判定と送信、claude/hooks/session-state.sh の記録の検証。

herdr は PATH 上のスタブに差し替える（実際の Herdr・Claude の会話には触れない）。
固定している regression:
- 承認待ち・質問待ちだった会話へ再開を送ってしまう（承認を飛ばす。最も危ない）
- 作業中・巡回あり待機中を送らない / 巡回なし待機中・記録なしへ送ってしまう
- 同じ boot_id で recover を2回呼ぶと2度送る
- フックが失敗したとき会話を止める（非 0 で終わる・何かを出力する）
"""

import importlib.machinery
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HERDR_RESUME = REPO_ROOT / "bin" / "herdr-resume"
HOOK = REPO_ROOT / "claude" / "hooks" / "session-state.sh"

_loader = importlib.machinery.SourceFileLoader("herdr_resume", str(HERDR_RESUME))
_spec = importlib.util.spec_from_loader("herdr_resume", _loader)
hr = importlib.util.module_from_spec(_spec)
_loader.exec_module(hr)

NOW = 1_800_000_000


def rec(state, age=60, crons=None):
    return {"state": state, "updated_at": NOW - age, "crons": crons or {}}


class DecideTest(unittest.TestCase):
    def test_judgement_table(self):
        fresh_cron = {"c1": NOW - 3600}
        old_cron = {"c1": NOW - 8 * 86400}
        cases = [
            # (記録, ペイン状態, 期待 action, 期待 kind)
            (rec("blocked"), "idle", "skip", None),  # 承認待ちだった: 必ず送らない
            (rec("working"), "blocked", "skip", None),  # 今ペインが承認待ち: 記録より優先して送らない
            (rec("working"), "idle", "send", "resume"),
            (rec("idle", crons=fresh_cron), "idle", "send", "cron"),
            (rec("idle", crons=old_cron), "idle", "skip", None),
            (rec("idle"), "idle", "skip", None),
            (None, "idle", "skip", None),
            (rec("working", age=2 * 86400), "idle", "skip", None),
            (rec("ended", crons=fresh_cron), "idle", "skip", None),
            (rec("working"), "unknown", "skip", None),
            (rec("working"), "done", "send", "resume"),  # 背面のペインは idle でなく done になる
            ({**rec("working"), "interrupted": True}, "idle", "skip", None),  # 人間が Esc で止めた
        ]
        for record, status, action, kind in cases:
            d = hr.decide(record, status, NOW)
            self.assertEqual((d["action"], d["kind"]), (action, kind), (record, status, d))
        # 承認待ちだった会話は人間に回す扱いで報告に載る
        self.assertTrue(hr.decide(rec("blocked"), "idle", NOW)["needs_human"])


STUB = r"""#!/bin/sh
# 偽の herdr。pane list / workspace list は固定、agent prompt は引数を記録する。
case "$1 $2" in
  "pane list") cat "$STUB_DIR/panes.json" ;;
  "workspace list") echo '{"result":{"workspaces":[{"workspace_id":"w1","label":"ws"}]}}' ;;
  "agent prompt") printf '%s\n' "$3" >>"$STUB_DIR/sent.log"; echo '{"ok":true}' ;;
  *) exit 1 ;;
esac
"""


def pane(pid, sid, status):
    return {"pane_id": pid, "agent": "claude", "agent_status": status, "workspace_id": "w1",
            "cwd": "/x", "agent_session": {"value": sid}}


class RecoverTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        t = Path(self.tmp.name)
        (t / "bin").mkdir()
        stub = t / "bin" / "herdr"
        stub.write_text(STUB)
        stub.chmod(0o755)
        self.state = t / "state"
        (self.state / "reboot-recovery" / "sessions").mkdir(parents=True)
        self.env = {**os.environ, "PATH": "%s:%s" % (t / "bin", os.environ["PATH"]), "STUB_DIR": str(t),
                    "XDG_STATE_HOME": str(self.state), "HERDR_RESUME_BOOT_ID": "boot-1",
                    "HERDR_RESUME_WINDOWS_BOOT": "2026-01-01T00:00:00",
                    "HERDR_RESUME_SETTLE_SECONDS": "0"}
        self.t = t

    def put(self, sid, record):
        (self.state / "reboot-recovery" / "sessions" / (sid + ".json")).write_text(json.dumps(record))

    def run_cmd(self, *args):
        now = int(__import__("time").time())
        return subprocess.run([str(HERDR_RESUME), *args], env=self.env, capture_output=True, text=True,
                              check=True, cwd=self.tmp.name), now

    def test_recover_sends_only_safe_and_only_once(self):
        now = int(__import__("time").time())
        for sid, r in {
            "s-blocked": {"state": "blocked", "updated_at": now - 10},
            "s-work": {"state": "working", "updated_at": now - 10},
            "s-cron": {"state": "idle", "updated_at": now - 10, "crons": {"c": now - 10}},
            "s-idle": {"state": "idle", "updated_at": now - 10},
            "s-esc": {"state": "working", "updated_at": now - 10, "transcript_path": str(self.t / "esc.jsonl")},
        }.items():
            self.put(sid, r)
        (self.t / "esc.jsonl").write_text("\n".join(json.dumps(d) for d in [
            {"type": "assistant", "message": {"content": [{"type": "text", "text": "x"}]}},
            {"type": "user", "message": {"role": "user", "content": [
                {"type": "text", "text": "[Request interrupted by user]"}]}},
            {"type": "file-history-snapshot"}]))
        (self.t / "panes.json").write_text(json.dumps({"result": {"panes": [
            pane("w1:p1", "s-blocked", "idle"), pane("w1:p2", "s-work", "idle"),
            pane("w1:p3", "s-cron", "idle"), pane("w1:p4", "s-idle", "idle"),
            pane("w1:p5", "s-none", "idle"), pane("w1:p6", "s-esc", "idle"),
            # agent なしで cwd に claude を含むだけのシェルは、起動中の Claude と見なして待たない・載せない
            {"pane_id": "w1:p7", "agent_status": "unknown", "workspace_id": "w1", "cwd": "/x",
             "terminal_title": "~/projects/dotfiles/master/claude/hooks"},
            {"pane_id": "w1:p8", "agent_status": "unknown", "workspace_id": "w1", "cwd": "/x",
             "terminal_title": "u: claude --resume abc"}]}}))
        self.run_cmd("recover", "--json")
        sent = (self.t / "sent.log").read_text().splitlines()
        self.assertEqual(len(sent), 2)  # 作業中と巡回あり待機中だけ
        report = json.loads((self.state / "reboot-recovery" / "last-recovery.json").read_text())
        self.assertEqual({e["pane_id"] for e in report["sent"]}, {"w1:p2", "w1:p3"})
        not_sent = {e["pane_id"]: e for e in report["not_sent"]}
        self.assertEqual(set(not_sent), {"w1:p1", "w1:p4", "w1:p5", "w1:p6", "w1:p8"})
        self.assertTrue(not_sent["w1:p1"]["needs_human"])
        self.assertEqual(not_sent["w1:p6"]["code"], "interrupted")
        self.assertEqual(report["boot_id"], "boot-1")
        # 同じ boot_id の2回目は送らない
        self.run_cmd("recover", "--json")
        self.assertEqual(len((self.t / "sent.log").read_text().splitlines()), 2)
        # boot_id が変われば（再び落ちて戻った）また送れる
        self.env["HERDR_RESUME_BOOT_ID"] = "boot-2"
        self.run_cmd("recover", "--json")
        self.assertEqual(len((self.t / "sent.log").read_text().splitlines()), 4)


class NoBootIdTest(unittest.TestCase):
    def test_recover_refuses_without_boot_id(self):
        # 冪等の鍵が無いまま送らない（2度目の呼び出しで2重に積むため）
        with tempfile.TemporaryDirectory() as d:
            with self.assertRaises(RuntimeError):
                hr.recover(Path(d), NOW, None, None)
            self.assertFalse((Path(d) / "last-recovery.json").exists())


class HookTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.env = {**os.environ, "XDG_STATE_HOME": self.tmp.name}
        self.path = Path(self.tmp.name) / "reboot-recovery" / "sessions" / "abc-1.json"

    def fire(self, payload, env=None, raw=None):
        data = raw if raw is not None else json.dumps(payload)
        return subprocess.run([str(HOOK)], input=data, env=env or self.env, capture_output=True, text=True)

    def state(self):
        return json.loads(self.path.read_text())

    def test_state_transitions_and_cron(self):
        base = {"session_id": "abc-1", "cwd": "/x"}
        self.fire({**base, "hook_event_name": "UserPromptSubmit"})
        self.assertEqual(self.state()["state"], "working")
        self.fire({**base, "hook_event_name": "Notification", "notification_type": "permission_prompt"})
        self.assertEqual(self.state()["state"], "blocked")
        self.fire({**base, "hook_event_name": "PostToolUse", "tool_name": "Bash"})  # 承認されて動いた
        self.assertEqual(self.state()["state"], "working")
        self.fire({**base, "hook_event_name": "PostToolUse", "tool_name": "CronCreate",
                   "tool_response": {"id": "job12345"}})
        self.assertIn("job12345", self.state()["crons"])
        self.fire({**base, "hook_event_name": "Stop"})
        self.assertEqual(self.state()["state"], "idle")
        self.fire({**base, "hook_event_name": "PostToolUse", "tool_name": "CronDelete",
                   "tool_input": {"id": "job12345"}})
        self.assertEqual(self.state()["crons"], {})

    def test_one_shot_cron_and_session_end_reason(self):
        base = {"session_id": "abc-1", "cwd": "/x"}
        self.fire({**base, "hook_event_name": "UserPromptSubmit", "transcript_path": "/t.jsonl"})
        self.assertEqual(self.state()["transcript_path"], "/t.jsonl")
        self.fire({**base, "hook_event_name": "PostToolUse", "tool_name": "CronCreate",
                   "tool_input": {"recurring": False}, "tool_response": {"id": "once1234"}})
        self.assertEqual(self.state().get("crons", {}), {})  # 一回きりは巡回に数えない
        self.fire({**base, "hook_event_name": "SessionEnd", "reason": "other"})  # WSL の停止でも出うる
        self.assertEqual(self.state()["state"], "working")
        self.fire({**base, "hook_event_name": "SessionEnd", "reason": "prompt_input_exit"})
        self.assertEqual(self.state()["state"], "ended")

    def test_failures_never_break_the_conversation(self):
        ro = Path(self.tmp.name) / "ro"
        ro.write_text("file, not dir")  # 状態の置き場所が作れない
        for r in (
            self.fire(None, raw="{not json"),
            self.fire({"session_id": "../evil", "hook_event_name": "Stop"}),
            self.fire({"session_id": "abc-1", "hook_event_name": "Stop"}, env={**self.env, "XDG_STATE_HOME": str(ro)}),
        ):
            self.assertEqual((r.returncode, r.stdout, r.stderr), (0, "", ""))


if __name__ == "__main__":
    unittest.main()
