"""bin/dfup（および将来の dfdown）が組み立てる rsync 呼び出しの検証。

ssh も実転送も伴わない。`DFXFER_RSYNC` に「引数を記録するだけのスタブ」を
差し込むことで、組み立てられたコマンドライン全体を読み取る
（計画書 DOC-2609172237「テスト方針」）。

ここで固定している regression は、どれも「静かに壊れて、壊れたことに
気づけない」類のものに絞ってある:

- 宛先が決まらないときに止まらず飛ぶと、意図しないホストへ送られる
- Linux ローカルで --iconv が付くと、NFC のファイル名が壊れる
- --delete / --remove-source-files が紛れ込むと、原本や宛先の既存ファイルが
  消える。しかも消えたことは転送ログを読み返さないと分からない
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DFUP = REPO_ROOT / "bin" / "dfup"

# 引数を1行1つで ARGS_LOG へ追記するだけのスタブ。--version だけは本物の
# rsync と同じ1行目を返す（dfxfer-lib.sh がメジャー番号を読むため）。
RSYNC_STUB = """#!/bin/sh
if [ "$1" = "--version" ]; then
  printf 'rsync  version %s  protocol version 31\\n'
  exit 0
fi
for a in "$@"; do printf '%%s\\n' "$a"; done >>"$ARGS_LOG"
"""

# macOS 判定は shared/helpers.sh の `uname -s` を通る。PATH の先頭に置いた
# uname で Darwin を名乗らせるのが、テスト専用フラグを1つも足さずに
# 「ローカルが macOS のとき」を再現できる唯一の継ぎ目。
UNAME_STUB = """#!/bin/sh
if [ "$1" = "-s" ]; then
  printf 'Darwin\\n'
else
  printf 'arm64\\n'
fi
"""


class DfxferTestBase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="dfxfer-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

        self.args_log = self.tmp / "args.log"
        self.base_dir = self.tmp / "dfxfer"

        self.fake_bin = self.tmp / "fakebin"
        self.fake_bin.mkdir()
        self._write_exec(self.fake_bin / "uname", UNAME_STUB)

    def _write_exec(self, path, content):
        path.write_text(content, encoding="utf-8")
        path.chmod(0o755)
        return path

    def _rsync_stub(self, version="3.2.7"):
        return self._write_exec(
            self.tmp / f"rsync-{version}", RSYNC_STUB % version
        )

    def _seed_file(self, host, leaf="out", name="memo.txt"):
        d = self.base_dir / host / leaf
        d.mkdir(parents=True, exist_ok=True)
        (d / name).write_text("hello\n", encoding="utf-8")
        return d

    def _run(self, script, *args, env=None, macos=False, rsync_version="3.2.7"):
        run_env = dict(os.environ)
        # 実環境の設定がテストへ漏れ込まないように、まず明示的に落とす。
        for key in (
            "DFXFER_HOST",
            "DFXFER_HOSTS",
            "DFXFER_DIR",
            "DFXFER_REMOTE_DIR",
            "DFXFER_RSYNC",
        ):
            run_env.pop(key, None)
        run_env["ARGS_LOG"] = str(self.args_log)
        run_env["DFXFER_DIR"] = str(self.base_dir)
        run_env["DFXFER_RSYNC"] = str(self._rsync_stub(rsync_version))
        if macos:
            run_env["PATH"] = f"{self.fake_bin}:{run_env['PATH']}"
        run_env.update(env or {})

        proc = subprocess.run(
            [str(script), *args],
            env=run_env,
            capture_output=True,
            text=True,
        )
        return proc

    def _logged_args(self):
        if not self.args_log.exists():
            return []
        return self.args_log.read_text(encoding="utf-8").splitlines()


class DestinationResolutionTest(DfxferTestBase):
    """計画書 1.3 の宛先決定規則。決まらないときは必ず止まる。"""

    def test_single_entry_list_needs_no_default(self):
        self._seed_file("toybox")
        proc = self._run(DFUP, env={"DFXFER_HOSTS": "toybox"})

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("toybox:uploads/", self._logged_args())

    def test_explicit_host_wins_and_needs_no_list(self):
        self._seed_file("work-box")
        proc = self._run(DFUP, env={"DFXFER_HOST": "work-box"})

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("work-box:uploads/", self._logged_args())

    def test_unresolvable_destinations_abort_with_setup_guidance(self):
        """宛先が決まらない3通り。どれも転送せずに止まり、何を設定すれば
        よいかが（export 付きで）伝わること。"""
        self._seed_file("toybox")
        cases = {
            "no config at all": {},
            "whitespace-only list": {"DFXFER_HOSTS": "   "},
            "ambiguous list": {"DFXFER_HOSTS": "toybox work-box"},
            "default not in list": {
                "DFXFER_HOSTS": "toybox work-box",
                "DFXFER_HOST": "typo-box",
            },
        }

        for label, env in cases.items():
            with self.subTest(case=label):
                self.args_log.unlink(missing_ok=True)
                proc = self._run(DFUP, env=env)

                self.assertNotEqual(proc.returncode, 0)
                self.assertEqual(self._logged_args(), [])
                self.assertIn("DFXFER_HOST", proc.stderr)
                self.assertIn("export", proc.stderr)


class RsyncResolutionTest(DfxferTestBase):
    """使う rsync を決めるところ。"""

    def test_mistyped_rsync_override_fails_loudly(self):
        """regression: DFXFER_RSYNC のタイポで、何のメッセージも出さないまま
        終了していた（`set -o pipefail` 下でバージョン確認のパイプラインが
        失敗し、それを受ける代入ごと落ちるため）。~/.zshrc.local に一度
        書いたきり忘れる設定なので、黙って落ちると原因に辿り着けない。"""
        self._seed_file("toybox")
        proc = self._run(
            DFUP,
            env={
                "DFXFER_HOSTS": "toybox",
                "DFXFER_RSYNC": str(self.tmp / "does-not-exist"),
            },
        )

        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("DFXFER_RSYNC", proc.stderr)
        self.assertIn("does-not-exist", proc.stderr)
        self.assertEqual(self._logged_args(), [])


class IconvTest(DfxferTestBase):
    """計画書 1.5。--iconv は「macOS かつ rsync 3.x」のときだけ付く。"""

    ICONV = "--iconv=UTF-8-MAC,UTF-8"

    def test_macos_with_rsync_3x_converts_filenames(self):
        self._seed_file("toybox")
        proc = self._run(DFUP, env={"DFXFER_HOSTS": "toybox"}, macos=True)

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn(self.ICONV, self._logged_args())

    def test_linux_never_converts_filenames(self):
        """Linux ローカルの名前は既に NFC。変換を挟むと逆に壊れるうえ、
        壊れ方が静かで気づけない。"""
        self._seed_file("toybox")
        proc = self._run(DFUP, env={"DFXFER_HOSTS": "toybox"}, macos=False)

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn(self.ICONV, self._logged_args())

    def test_macos_with_old_rsync_warns_but_still_transfers(self):
        """macOS 同梱の rsync は 2.6.9 で --iconv を持たない。ここで
        エラー終了させない、というのが計画書 5.1 の確定事項。"""
        self._seed_file("toybox")
        proc = self._run(
            DFUP,
            env={"DFXFER_HOSTS": "toybox"},
            macos=True,
            rsync_version="2.6.9",
        )

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn(self.ICONV, self._logged_args())
        self.assertIn("brew install rsync", proc.stderr)
        self.assertIn("toybox:uploads/", self._logged_args())

    def test_linux_with_old_rsync_stays_quiet(self):
        """Linux では --iconv が要らないので、古い rsync でも警告しない。"""
        self._seed_file("toybox")
        proc = self._run(
            DFUP,
            env={"DFXFER_HOSTS": "toybox"},
            macos=False,
            rsync_version="2.6.9",
        )

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn("brew install rsync", proc.stderr)


class DfupInvocationTest(DfxferTestBase):
    """dfup が組み立てる rsync コマンドラインそのもの。"""

    def test_sends_out_dir_contents_upward_without_destructive_flags(self):
        self._seed_file("toybox")
        proc = self._run(DFUP, env={"DFXFER_HOSTS": "toybox"})
        args = self._logged_args()

        self.assertEqual(proc.returncode, 0, proc.stderr)

        # 向き: ローカルの out/ が src、リモートが dst。末尾スラッシュは
        # 「ディレクトリの中身」を意味し、out/ 自体を入れ子にしない。
        self.assertEqual(
            args[-2:],
            [f"{self.base_dir}/toybox/out/", "toybox:uploads/"],
        )

        # 消す方向のフラグが1つも無いこと。混入すると原本またはリモートの
        # 既存ファイルが消え、被害が戻らない（計画書 5.4 / 1.7）。
        for flag in ("--delete", "--remove-source-files"):
            self.assertNotIn(flag, args)
        self.assertFalse([a for a in args if a.startswith("--delete")])

        # -X / -A は macOS の拡張属性・ACL を Linux へ持ち込んで rsync を
        # 失敗させる（計画書 1.7）。
        self.assertIn("-a", args)
        self.assertNotIn("-X", args)
        self.assertNotIn("-A", args)

        # Finder のゴミを運ばない。
        self.assertIn("--exclude=.DS_Store", args)
        self.assertIn("--exclude=._*", args)

    def test_extra_arguments_pass_through_to_rsync(self):
        self._seed_file("toybox")
        proc = self._run(DFUP, "-n", env={"DFXFER_HOSTS": "toybox"})
        args = self._logged_args()

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("-n", args)
        # 透過引数はパスより前。rsync は src/dst を末尾に取る。
        self.assertLess(args.index("-n"), len(args) - 2)

    def test_remote_dir_is_overridable(self):
        self._seed_file("toybox")
        proc = self._run(
            DFUP,
            env={"DFXFER_HOSTS": "toybox", "DFXFER_REMOTE_DIR": "inbox"},
        )

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("toybox:inbox/", self._logged_args())

    def test_creates_local_dirs_and_reports_when_there_is_nothing_to_send(self):
        """初回実行で mkdir を人間にさせない。中身が無いときは黙って
        終わらず、どこへ置けばよいかを言う。"""
        out_dir = self.base_dir / "toybox" / "out"
        self.assertFalse(out_dir.exists())

        proc = self._run(DFUP, env={"DFXFER_HOSTS": "toybox"})

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(out_dir.is_dir())
        self.assertIn(str(out_dir), proc.stdout)
        self.assertEqual(self._logged_args(), [])


if __name__ == "__main__":
    unittest.main()
