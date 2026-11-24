"""bin/rebootctl の「壊れると危ない」振る舞いの検証。

powershell.exe / herdr / herdr-resume はスタブへ差し替え、実 Windows にも実 Herdr にも
触れない。固定する regression:

- `setup` は管理者コマンドを表示するだけで、powershell.exe を一度も呼ばない
  （呼ぶと管理者操作を人間の承認なしに実行しうる）
- `boot` は何度呼んでも Herdr のサーバを二重に起動しない。herdr-resume が無くても止まらない
- `watch` は再起動待ちでないとき・読めないときは管制の会話へ何も送らない。再起動待ちのときだけ送り、
  同じ `windows_last_boot` への予告は1回だけ。解けたら印を消し、送れなかったとき（承認待ち・作業中・管制なし）は
  印を書かない。`control-tower.json` のほかの鍵は壊さない
- `boot` は boot_id が変わり Windows の最終起動時刻が同じなら WSL だけの起き直しと判定し、起動時の差し込み口を
  名前順に呼ぶ（1本の失敗・時間切れで残りを止めない）。`--once-per-boot` は同じ起動で2回目以降、差し込み口も
  管制への送信も繰り返さない
- 起動時の `netuse` / `netuse-boot`（root で NAS の資格情報から net use を張り、ユーザーへ切り替えて boot）は、パスワードを標準出力・標準エラー・
  boot.log のどこにも出さず、失敗しても資格情報が無くても 0 で終わる（後ろの boot を止めない）。
  `setup` は NAS の UNC が分かるときだけ net use の操作を足す
- 管制の会話は `$HOME` でなく専用のフォルダで起こす（信頼を保存できないと毎回確認で止まる）
- `status` は powershell.exe が無くても落ちず、「読めなかった」ことを出す
- `status` の NAS の確認は、確認先が未設定なら飛ばし、Windows 側が読めないときは「確認できなかった」を
  「届かない」と取り違えず、UNC と WSL 経由を別々に出す
"""

import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

REBOOTCTL = Path(__file__).resolve().parents[1] / "rebootctl"


def write_stub(path: Path, body: str) -> None:
    path.write_text("#!/bin/sh\n" + body)
    path.chmod(path.stat().st_mode | stat.S_IXUSR)


class RebootctlTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self._tmp.cleanup)
        self.tmp = Path(self._tmp.name)
        self.stubs = self.tmp / "stubs"
        self.stubs.mkdir()
        self.state = self.tmp / "state"
        self.calls = self.tmp / "calls.log"
        # herdr: 「サーバ起動済み」の目印ファイルがあれば running を返す。
        # `herdr server` は目印を作って記録する（起動回数が calls.log に残る）
        write_stub(
            self.stubs / "herdr",
            f"""echo "herdr $*" >> {self.calls}
case "$1 $2" in
  "status server")
    [ -e {self.tmp}/running ] && echo "status: running" ;;
  "workspace list")
    if [ -e {self.tmp}/no-workspaces ]; then echo '{{"workspaces":[]}}'
    elif [ -e {self.tmp}/control ]; then echo '{{"workspaces":[{{"workspace_id":"w1"}},{{"workspace_id":"w2","label":"管制"}}]}}'
    else echo '{{"workspaces":[{{"workspace_id":"w1"}}]}}'; fi ;;
  "pane list")
    if [ -e {self.tmp}/pane-noagent ]; then echo '{{"result":{{"panes":[{{"pane_id":"w2:p1"}}]}}}}'
    elif [ -e {self.tmp}/pane-blocked ]; then echo '{{"result":{{"panes":[{{"pane_id":"w2:p1","agent":"claude","agent_status":"blocked"}}]}}}}'
    else echo '{{"result":{{"panes":[{{"pane_id":"w2:p1","agent":"claude","agent_status":"idle"}}]}}}}'; fi ;;
  "agent prompt")
    [ -e {self.tmp}/prompt-timeout ] && {{ echo '{{"error":{{"code":"timeout"}}}}'; exit 1; }} ;;
  "workspace create")
    [ -e {self.tmp}/create-fails ] && exit 1
    touch {self.tmp}/control; echo '{{"result":{{"root_pane":{{"pane_id":"w2:p1"}}}}}}' ;;
  "server "*) ;;
esac
case "$1" in
  server) touch {self.tmp}/running; sleep 5 >/dev/null 2>&1 & ;;
esac
exit 0
""",
        )
        write_stub(self.stubs / "claude", "exit 0\n")
        write_stub(self.stubs / "powershell.exe", f'echo "powershell $*" >> {self.calls}\n')

    def run_ctl(self, *args: str, path_only_stubs: bool = False, extra_env: dict | None = None):
        env = dict(os.environ)
        env.pop("REBOOTCTL_NAS_MOUNT", None)
        env.pop("REBOOTCTL_NAS_UNC", None)
        env["REBOOTCTL_WIN_PS_DIR"] = str(self.tmp / "no-win-ps")  # 実機の Windows を読まない
        env.update(extra_env or {})
        env["XDG_STATE_HOME"] = str(self.state)
        env["REBOOTCTL_RESTORE_WAIT"] = "6"
        env["REBOOTCTL_NET_EXE"] = str(self.tmp / "no-net.exe")  # 実機の net.exe を呼ばない
        env["HOME"] = str(self.tmp / "home")
        (self.tmp / "home").mkdir(exist_ok=True)
        base = "/usr/bin:/bin"
        env["PATH"] = f"{self.stubs}:{base}" if not path_only_stubs else base
        return subprocess.run(
            ["bash", str(REBOOTCTL), *args],
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
        )

    def calls_text(self) -> str:
        return self.calls.read_text() if self.calls.exists() else ""

    def test_setup_prints_commands_without_calling_powershell(self) -> None:
        r = self.run_ctl("setup")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("NoAutoRebootWithLoggedOnUsers", r.stdout)
        self.assertNotIn("powershell", self.calls_text())

    def test_setup_adds_netuse_action_only_when_unc_is_known(self) -> None:
        r = self.run_ctl("setup", extra_env={"REBOOTCTL_NAS_UNC": "\\\\nas\\share"})
        # 操作は1つで、root の netuse-boot（net use と boot を同じ wsl.exe の起動の中で走らせる）
        self.assertIn("-u root -- env HOME=", r.stdout)
        self.assertIn("rebootctl netuse-boot //nas/share ", r.stdout)
        self.assertIn("-Action $action ", r.stdout)
        self.assertNotIn("password", r.stdout.lower())
        r = self.run_ctl("setup")
        self.assertNotIn("netuse-boot //", r.stdout)
        self.assertIn("bash -lc", r.stdout)
        self.assertNotIn("powershell", self.calls_text())

    def test_netuse_never_leaks_password_and_never_fails_boot(self) -> None:
        secret = "S3cr3t-pw"
        cred = self.tmp / "nas-credentials"
        cred.write_text(f"username=alice\npassword={secret}\n")
        env = {"REBOOTCTL_NAS_CREDENTIALS": str(cred)}
        # net.exe のスタブ。受けた引数は calls に残すが、パスワードの引数だけ伏せる（スタブ自身が漏らさない）。
        # 失敗するときは、出力にパスワードを混ぜる
        write_stub(
            self.stubs / "net.exe",
            f"""printf '%s\\n' "net.exe $1 $2 <pw> $4" >> {self.calls}
[ -e {self.tmp}/net-fails ] && {{ echo "error for $3"; exit 2; }}
[ "$3" = '{secret}' ] && exit 0
exit 3
""",
        )
        r = self.run_ctl("netuse", "//nas/share", extra_env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("net.exe use \\\\nas\\share <pw> /user:alice", self.calls_text())
        self.assertIn("を張った", (self.state / "reboot-recovery" / "boot.log").read_text())
        # 失敗しても 0。出力のパスワードは伏せる
        (self.tmp / "net-fails").touch()
        r = self.run_ctl("netuse", "//nas/share", extra_env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("張れなかった", (self.state / "reboot-recovery" / "boot.log").read_text())
        # 資格情報が無い・UNC が無い・net.exe が無いときも 0
        for args, e in (
            (("//nas/share",), {"REBOOTCTL_NAS_CREDENTIALS": str(self.tmp / "none")}),
            ((), env),
        ):
            self.assertEqual(self.run_ctl("netuse", *args, extra_env=e).returncode, 0)
        # 切り替え先のユーザーが引けなくても 0 で終わり、boot を呼べなかったことを残す
        r = self.run_ctl("netuse-boot", "//nas/share", "no-such-user-xyz", "--hold", extra_env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("切り替えられない", (self.state / "reboot-recovery" / "boot.log").read_text())
        r = self.run_ctl("netuse", "//nas/share", path_only_stubs=True, extra_env=env)
        self.assertEqual(r.returncode, 0)
        log = (self.state / "reboot-recovery" / "boot.log").read_text()
        self.assertIn("netuse:", log)
        for text in (log, r.stdout, r.stderr):
            self.assertNotIn(secret, text)

    def test_netuse_boot_hands_user_runtime_dir_to_boot(self) -> None:
        # runuser は「-u ユーザー --」を外して後ろをそのまま実行するスタブ（実機の root 切り替えはテストで再現できない）。
        # boot の代わりに、渡った環境を書き出す
        write_stub(self.stubs / "runuser", 'shift 3\nexec "$@"\n')
        dump = self.tmp / "env.out"
        boot = self.tmp / "fake-boot"
        write_stub(boot, f'echo "xdg=${{XDG_RUNTIME_DIR-unset}} bus=${{DBUS_SESSION_BUS_ADDRESS-unset}}" > {dump}\n')
        user = subprocess.run(["id", "-un"], capture_output=True, text=True).stdout.strip()
        uid = subprocess.run(["id", "-u"], capture_output=True, text=True).stdout.strip()
        run_dir = self.tmp / "run-user"
        env = {
            "REBOOTCTL_RUN_USER_DIR": str(run_dir),
            "REBOOTCTL_BOOT_CMD": str(boot),
            "REBOOTCTL_NAS_CREDENTIALS": str(self.tmp / "none"),
            # root のログオンの値が残っていても、そのままは渡らない
            "XDG_RUNTIME_DIR": "/run/user/0",
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/run/user/0/bus",
        }
        rt = run_dir / uid

        def boot_env() -> str:
            dump.unlink(missing_ok=True)
            r = self.run_ctl("netuse-boot", "//nas/share", user, extra_env=env)
            self.assertEqual(r.returncode, 0, r.stderr)
            return dump.read_text().strip()

        # /run/user/<uid> が無い → 2つとも外す
        self.assertEqual(boot_env(), "xdg=unset bus=unset")
        # あるがバスのソケットが無い → XDG_RUNTIME_DIR だけ置き換える（env の -u は代入より先）
        rt.mkdir(parents=True)
        self.assertEqual(boot_env(), f"xdg={rt} bus=unset")
        # ソケットもある → 両方置き換える
        import socket

        sock = socket.socket(socket.AF_UNIX)
        self.addCleanup(sock.close)
        sock.bind(str(rt / "bus"))
        self.assertEqual(boot_env(), f"xdg={rt} bus=unix:path={rt}/bus")

    def test_control_tower_is_not_started_in_home(self) -> None:
        r = self.run_ctl("boot")
        self.assertEqual(r.returncode, 0, r.stderr)
        create = [c for c in self.calls_text().splitlines() if c.startswith("herdr workspace create")]
        self.assertEqual(len(create), 1)
        self.assertNotIn(f"--cwd {self.tmp / 'home'} ", create[0] + " ")
        self.assertIn(f"--cwd {self.state / 'reboot-recovery' / 'control'} ", create[0] + " ")

    def test_boot_is_idempotent_and_tolerates_missing_herdr_resume(self) -> None:
        for _ in range(2):
            r = self.run_ctl("boot")
            self.assertEqual(r.returncode, 0, r.stderr)
        starts = [line for line in self.calls_text().splitlines() if line == "herdr server"]
        self.assertEqual(len(starts), 1, "Herdr のサーバが二重に起動された")
        log = (self.state / "reboot-recovery" / "boot.log").read_text()
        self.assertIn("herdr-resume が無い", log)
        # 常駐した herdr server がロックを握り続けると、2回目以降の boot が何もしなくなる
        self.assertNotIn("別の boot が実行中", log)

    def test_boot_starts_control_tower_once_and_wakes_restored_one(self) -> None:
        for _ in range(3):
            r = self.run_ctl("boot")
            self.assertEqual(r.returncode, 0, r.stderr)
        calls = self.calls_text().splitlines()
        self.assertEqual(len([c for c in calls if c.startswith("herdr workspace create")]), 1, "管制の会話が二重に立った")
        runs = [c for c in calls if c.startswith("herdr pane run w2:p1")]
        self.assertEqual(len(runs), 1)
        self.assertIn("--model sonnet", runs[0])
        # 2回目以降は、復元された（待機中の）会話へ起動時の手順を送る。作り直さない
        prompts = [c for c in calls if c.startswith("herdr agent prompt w2:p1")]
        self.assertEqual(len(prompts), 2, "復元された管制の会話へ起動時の手順が送られていない")

    def test_boot_does_not_prompt_blocked_control_tower_and_restarts_dead_one(self) -> None:
        (self.tmp / "control").touch()
        (self.tmp / "pane-blocked").touch()
        r = self.run_ctl("boot")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertNotIn("herdr agent prompt", self.calls_text(), "承認待ちの会話へ送ってはいけない")
        (self.tmp / "pane-blocked").unlink()
        (self.tmp / "pane-noagent").touch()
        r = self.run_ctl("boot")
        self.assertEqual(r.returncode, 0, r.stderr)
        runs = [c for c in self.calls_text().splitlines() if c.startswith("herdr pane run w2:p1")]
        self.assertEqual(len(runs), 1, "エージェントが居ない管制のペインを起動し直していない")

    def test_prompt_timeout_is_logged_as_unconfirmed_not_failed(self) -> None:
        (self.tmp / "control").touch()
        (self.tmp / "prompt-timeout").touch()
        r = self.run_ctl("boot")
        self.assertEqual(r.returncode, 0, r.stderr)
        log = (self.state / "reboot-recovery" / "boot.log").read_text()
        self.assertIn("届いたか未確認", log)
        self.assertNotIn("送れなかった", log)

    def test_boot_continues_when_control_tower_cannot_start(self) -> None:
        (self.tmp / "create-fails").touch()
        r = self.run_ctl("boot")
        self.assertEqual(r.returncode, 0, r.stderr)
        log = (self.state / "reboot-recovery" / "boot.log").read_text()
        self.assertIn("管制の会話を起こせなかった", log)
        self.assertIn("boot: 終了", log)

    def test_boot_completes_when_no_workspaces(self) -> None:
        (self.tmp / "no-workspaces").touch()
        r = self.run_ctl("boot")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("boot: 終了", (self.state / "reboot-recovery" / "boot.log").read_text())

    def test_boot_detects_wsl_only_restart_runs_hooks_and_skips_same_boot(self) -> None:
        win = "2026-11-21T23:07:45+09:00"
        write_stub(self.stubs / "powershell.exe", f"echo last_boot={win}\n")
        state_dir = self.state / "reboot-recovery"
        state_dir.mkdir(parents=True)
        state_file = state_dir / "boot-state.json"
        # 前回の起動の記録: boot_id は今と違い、Windows の最終起動時刻は同じ（WSL だけの起き直し）
        state_file.write_text(json.dumps({"boot_id": "old", "windows_last_boot": win, "cause": "windows_reboot", "finished": True}))
        hooks = self.tmp / "boot.d"
        hooks.mkdir()
        out = self.tmp / "hooks.out"
        write_stub(hooks / "10-first", f'echo "first $REBOOTCTL_BOOT_CAUSE $REBOOTCTL_WINDOWS_LAST_BOOT" >> {out}\n')
        write_stub(hooks / "20-fails", f"echo fails >> {out}\nexit 3\n")
        write_stub(hooks / "30-hangs", f"echo hangs >> {out}\nexec sleep 30\n")
        write_stub(hooks / "40-last", f"echo last >> {out}\n")
        (hooks / "50-not-executable").write_text("#!/bin/sh\necho nope\n")
        env = {"REBOOTCTL_BOOT_D": str(hooks), "REBOOTCTL_HOOK_TIMEOUT": "1"}

        r = self.run_ctl("boot", "--once-per-boot", extra_env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        # 1本が失敗・時間切れでも残りが呼ばれ、順は名前順、実行権の無いものは呼ばれない
        self.assertEqual(
            out.read_text().splitlines(),
            [f"first wsl_restart {win}", "fails", "hangs", "last"],
        )
        record = json.loads(state_file.read_text())
        self.assertEqual((record["cause"], record["finished"]), ("wsl_restart", True))
        log = (state_dir / "boot.log").read_text()
        self.assertIn("時間切れ", log)
        self.assertIn("boot: 終了", log)
        prompts_before = len(self.prompts())

        # 同じ起動での再実行（タスクの繰り返し）は、差し込み口も管制への送信も繰り返さない
        r = self.run_ctl("boot", "--once-per-boot", extra_env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(out.read_text().splitlines()), 4)
        self.assertEqual(len(self.prompts()), prompts_before)
        self.assertEqual(json.loads(state_file.read_text())["cause"], "wsl_restart")

        # Windows の最終起動時刻が前回と違えば、Windows の再起動
        state_file.write_text(json.dumps({"boot_id": "old", "windows_last_boot": "2026-11-01T00:00:00+09:00", "cause": "x", "finished": True}))
        r = self.run_ctl("boot", extra_env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(json.loads(state_file.read_text())["cause"], "windows_reboot")

        # Windows が読めなかった起動は、前回の値を残さず空で記録する（次の判定を誤らせない）
        write_stub(self.stubs / "powershell.exe", "exit 1\n")
        state_file.write_text(json.dumps({"boot_id": "old", "windows_last_boot": win, "cause": "x", "finished": True}))
        r = self.run_ctl("boot", extra_env=env)
        self.assertEqual(r.returncode, 0, r.stderr)
        record = json.loads(state_file.read_text())
        self.assertEqual((record["cause"], record["windows_last_boot"]), ("unknown", ""))

    def test_pause_and_resume_touch_only_the_task_and_shutdown_needs_the_flag(self) -> None:
        write_stub(self.stubs / "wsl.exe", f'echo "wsl.exe $*" >> {self.calls}\n')
        # 決めた引数以外（--help を含む）は、タスクにも WSL にも触れずに使い方を出して終わる
        for bad in (("pause", "--help"), ("pause", "-h"), ("pause", "--shutdown", "x"), ("resume", "--help")):
            r = self.run_ctl(*bad)
            self.assertEqual(r.returncode, 2, bad)
            self.assertIn("Usage", r.stderr)
        self.assertEqual(self.calls_text(), "", "不正な引数でタスクか WSL に触れた")
        r = self.run_ctl("pause")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Disable-ScheduledTask", self.calls_text())
        self.assertNotIn("wsl.exe", self.calls_text(), "--shutdown 無しで WSL を止めてはいけない")
        r = self.run_ctl("resume")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("Enable-ScheduledTask", self.calls_text())
        r = self.run_ctl("pause", "--shutdown")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("wsl.exe --shutdown", self.calls_text())
        # タスクを無効にできなかったときは WSL を止めない
        self.calls.write_text("")
        write_stub(self.stubs / "powershell.exe", "echo denied; exit 1\n")
        r = self.run_ctl("pause", "--shutdown")
        self.assertNotEqual(r.returncode, 0)
        self.assertNotIn("wsl.exe", self.calls_text())

    def watch_setup(self, reboot: str) -> None:
        """Windows の再起動待ちを reboot（True / False）にした powershell.exe のスタブへ差し替える"""
        write_stub(
            self.stubs / "powershell.exe",
            f"echo reboot_required={reboot}; echo last_boot=2026-11-21T23:07:45+09:00\n",
        )
        (self.tmp / "control").touch()

    def prompts(self) -> list[str]:
        return [c for c in self.calls_text().splitlines() if c.startswith("herdr agent prompt")]

    def test_watch_announces_only_when_reboot_pending_and_once(self) -> None:
        state = self.state / "reboot-recovery"
        state.mkdir(parents=True)
        marker = state / "control-tower.json"
        marker.write_text(json.dumps({"notified_boot_id": "b1"}))

        # 再起動待ちでない / Windows が読めない: 何も送らず、モデルも呼ばない
        self.watch_setup("False")
        self.assertEqual(self.run_ctl("watch").returncode, 0)
        r = self.run_ctl("watch", path_only_stubs=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.prompts(), [])
        # 読めなかったことは boot.log に残る（cron の下で黙って止まらない）
        self.assertIn("watch: Windows 側を読めなかった", (state / "boot.log").read_text())

        # 再起動待ち: 1回だけ送り、印を書く（ほかの鍵は残す）。2回目以降は送らない
        self.watch_setup("True")
        for _ in range(3):
            self.assertEqual(self.run_ctl("watch").returncode, 0)
        self.assertEqual(len(self.prompts()), 1, "同じ予告が繰り返し送られた")
        self.assertIn("再起動の予告の手順", self.prompts()[0])
        data = json.loads(marker.read_text())
        self.assertEqual(data["announced_reboot_for"], "2026-11-21T23:07:45+09:00")
        self.assertEqual(data["notified_boot_id"], "b1")

        # 解けたら印だけ消す。次に再起動待ちになればまた1回送る
        self.watch_setup("False")
        self.run_ctl("watch")
        self.assertEqual(json.loads(marker.read_text()), {"notified_boot_id": "b1"})
        self.watch_setup("True")
        self.run_ctl("watch")
        self.assertEqual(len(self.prompts()), 2)

    def test_watch_finds_powershell_outside_the_cron_path(self) -> None:
        # cron の PATH には Windows 側の置き場所が無い。watch が自分で足して読めること
        self.watch_setup("True")
        win_ps = self.tmp / "win-ps"
        win_ps.mkdir()
        (self.stubs / "powershell.exe").rename(win_ps / "powershell.exe")
        r = self.run_ctl("watch", extra_env={"REBOOTCTL_WIN_PS_DIR": str(win_ps)})
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(len(self.prompts()), 1)

    def test_watch_does_not_mark_when_it_could_not_send(self) -> None:
        marker = self.state / "reboot-recovery" / "control-tower.json"
        self.watch_setup("True")
        # 作業中・承認待ち・エージェント無し・管制のワークスペース無し: 送らず、印も書かない（次の巡回で試す）
        (self.tmp / "pane-blocked").touch()
        self.run_ctl("watch")
        (self.tmp / "pane-blocked").unlink()
        (self.tmp / "pane-noagent").touch()
        self.run_ctl("watch")
        (self.tmp / "pane-noagent").unlink()
        (self.tmp / "control").unlink()
        self.run_ctl("watch")
        self.assertEqual(self.prompts(), [])
        self.assertFalse(marker.exists(), "送れていないのに印が書かれた")
        # 届いたか未確認（timeout）は再送しないので印を書く
        (self.tmp / "control").touch()
        (self.tmp / "prompt-timeout").touch()
        self.run_ctl("watch")
        self.run_ctl("watch")
        self.assertEqual(len(self.prompts()), 1)
        self.assertIn("announced_reboot_for", marker.read_text())

    def test_status_survives_unreadable_windows(self) -> None:
        # スタブの PATH から powershell.exe を外す（Windows 側が読めない状況）
        r = self.run_ctl("status", "--json", path_only_stubs=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        data = json.loads(r.stdout)
        self.assertFalse(data["windows_readable"])
        self.assertIsNone(data["au_options"])

    def test_status_reports_nas_checks_separately(self) -> None:
        # 確認先が未設定: 飛ばしたと出す（落ちない）
        data = json.loads(self.run_ctl("status", "--json").stdout)
        self.assertEqual(data["nas_wsl_mounted"], "skipped")
        self.assertEqual(data["nas_windows_unc_reachable"], "skipped")
        self.assertEqual(data["nas_windows_via_wsl_reachable"], "skipped")

        # UNC は届かず、WSL 経由のパスは届く（S4U の WSL の実測と同じ形）。
        # マウント済みの場所として /proc を使う（末尾の / があっても同じに扱う）
        write_stub(self.stubs / "wslpath", 'echo "\\\\wsl.localhost\\X\\nas"\n')
        write_stub(
            self.stubs / "powershell.exe",
            'case "$*" in *wsl.localhost*) echo True;; *) echo False;; esac\n',
        )
        env = {"REBOOTCTL_NAS_MOUNT": "/proc/", "REBOOTCTL_NAS_UNC": "\\\\nas\\share"}
        data = json.loads(self.run_ctl("status", "--json", extra_env=env).stdout)
        self.assertIs(data["nas_wsl_mounted"], True)
        self.assertIs(data["nas_windows_unc_reachable"], False)
        self.assertIs(data["nas_windows_via_wsl_reachable"], True)

        # マウントされていない空のディレクトリは、Windows から見えても「届かない」（空の場所へ書かせない）
        (self.tmp / "empty-dir").mkdir()
        unmounted = {**env, "REBOOTCTL_NAS_MOUNT": str(self.tmp / "empty-dir")}
        data = json.loads(self.run_ctl("status", "--json", extra_env=unmounted).stdout)
        self.assertIs(data["nas_wsl_mounted"], False)
        self.assertIs(data["nas_windows_via_wsl_reachable"], False)

        # Windows 側が読めない（powershell.exe が無い）: 「届かない」でなく null
        r = self.run_ctl("status", "--json", path_only_stubs=True, extra_env=env)
        data = json.loads(r.stdout)
        self.assertIsNone(data["nas_windows_unc_reachable"])
        self.assertIsNone(data["nas_windows_via_wsl_reachable"])


if __name__ == "__main__":
    unittest.main()
