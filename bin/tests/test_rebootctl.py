"""bin/rebootctl の「壊れると危ない」振る舞いの検証。

powershell.exe / herdr / herdr-resume はスタブへ差し替え、実 Windows にも実 Herdr にも
触れない。固定する regression:

- `setup` は管理者コマンドを表示するだけで、powershell.exe を一度も呼ばない
  （呼ぶと管理者操作を人間の承認なしに実行しうる）
- `boot` は何度呼んでも Herdr のサーバを二重に起動しない。herdr-resume が無くても止まらない
- `status` は powershell.exe が無くても落ちず、「読めなかった」ことを出す
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

    def run_ctl(self, *args: str, path_only_stubs: bool = False):
        env = dict(os.environ)
        env["XDG_STATE_HOME"] = str(self.state)
        env["REBOOTCTL_RESTORE_WAIT"] = "6"
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

    def test_boot_starts_control_tower_once(self) -> None:
        for _ in range(3):
            r = self.run_ctl("boot")
            self.assertEqual(r.returncode, 0, r.stderr)
        calls = self.calls_text().splitlines()
        self.assertEqual(len([c for c in calls if c.startswith("herdr workspace create")]), 1, "管制の会話が二重に立った")
        runs = [c for c in calls if c.startswith("herdr pane run w2:p1")]
        self.assertEqual(len(runs), 1)
        self.assertIn("--model sonnet", runs[0])

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

    def test_status_survives_unreadable_windows(self) -> None:
        # スタブの PATH から powershell.exe を外す（Windows 側が読めない状況）
        r = self.run_ctl("status", "--json", path_only_stubs=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        data = json.loads(r.stdout)
        self.assertFalse(data["windows_readable"])
        self.assertIsNone(data["au_options"])


if __name__ == "__main__":
    unittest.main()
