"""bin/dfup / bin/dfdown が組み立てる rsync 呼び出しの検証。

実転送は伴わない。`DFXFER_RSYNC` に「引数を記録するだけのスタブ」を差し込むことで、
組み立てられたコマンドライン全体を読み取る（計画書 DOC-2609172237「テスト方針」）。
dfdown が受信先を作るために叩く ssh も同様にスタブへ差し替え、実際のネットワーク
接続は一切発生しない。

ここで固定している regression は、どれも「静かに壊れて、壊れたことに
気づけない」類のものに絞ってある:

- 宛先が決まらないときに止まらず飛ぶと、意図しないホストへ送られる
- Linux ローカルで --iconv が付くと、NFC のファイル名が壊れる
- --delete / --remove-source-files が紛れ込むと、原本や宛先の既存ファイルが
  消える。しかも消えたことは転送ログを読み返さないと分からない
- dfdown の「Nothing came down」判定が受信先ディレクトリの現在の中身を見ていると、
  一度でも何か落ちてきた後は永遠に正しく判定できなくなる。しかも壊れ方が静かで、
  次に本当に何も来なかった回に気づけない
- rsync --stats の転送件数が1000件を超えると桁区切りのカンマが入り、素朴な数字抽出が
  複数行にマッチして `-eq` 比較がクラッシュする。転送自体は成功しているのに
  エラーメッセージが出て利用者を混乱させる
- リモートの受信先ディレクトリが無いまま dfdown が pull すると、rsync は
  push方向と違って自動でディレクトリを作らないため素のエラーで落ちる
- 旧 DFXFER_REMOTE_DIR が設定されたままだと、新しい up/down 変数名は読まれず、
  エラーも警告も無いまま既定値へ静かにフォールバックする
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DFUP = REPO_ROOT / "bin" / "dfup"
DFDOWN = REPO_ROOT / "bin" / "dfdown"

# 引数を1行1つで ARGS_LOG へ追記するだけのスタブ。--version だけは本物の
# rsync と同じ1行目を返す（dfxfer-lib.sh がメジャー番号を読むため）。--stats が
# 引数にあれば、実物の `rsync --stats` が出す転送件数の1行を標準出力へ返す
# （dfdown がこの行を見て「今回の転送で何か来たか」を判定するため）。件数は
# 環境変数 RSYNC_STUB_TRANSFERRED で差し込む（既定 0 = 何も転送しなかった体）。
#
# 件数行の文言は**名乗ったバージョンに合わせて変える**（%%(label)s に
# _stats_label() が差し込む）。rsync 3.1.0 でこの行は "Number of regular files
# transferred:" へ書き換えられており、2.6.9 / 3.0.x は "Number of files
# transferred:" を出す。スタブが常に新しい文言を返していると、古い rsync を
# 名乗らせたテストが「実物には出せない出力」を前提に緑になってしまう。
RSYNC_STUB = """#!/bin/sh
if [ "$1" = "--version" ]; then
  printf 'rsync  version %(version)s  protocol version 31\\n'
  exit 0
fi
for a in "$@"; do printf '%%s\\n' "$a"; done >>"$ARGS_LOG"
case " $* " in
  *" --stats "*)
    printf '%(label)s %%s\\n' "${RSYNC_STUB_TRANSFERRED:-0}"
    ;;
esac
"""

# 新しめの macOS が rsync の代わりに同梱する openrsync の模造。プロトコル
# バージョンしか名乗らない（= dfxfer_rsync_major() が空を返す）ことと、
# 知らないオプションを渡されたら転送せずエラー終了することの2点だけを再現する。
OPENRSYNC_STUB = """#!/bin/sh
if [ "$1" = "--version" ]; then
  printf 'openrsync: protocol version 29\\n'
  exit 0
fi
for a in "$@"; do
  case "$a" in
    --stats)
      printf 'openrsync: unknown option --stats\\n' >&2
      exit 1
      ;;
  esac
done
for a in "$@"; do printf '%s\\n' "$a"; done >>"$ARGS_LOG"
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

# dfdown asks the remote to create its receive directory over ssh before
# pulling (dfxfer_ensure_remote_dir), and that function's own existing-vs-
# created distinction depends on what it finds in the remote's home. This
# stub never touches the network, but it must still behave like the real
# ssh(1) in one specific way: "the arguments will be appended to the
# command, separated by spaces" before the *remote* login shell parses that
# flattened string — argv boundaries after <host> do not survive the trip.
# An earlier version of this stub instead preserved argv boundaries with
# `exec "$@"`, which let a command that only worked by accident under
# preserved boundaries (`sh -c '<script>' _ <dir>`, syntactically broken
# once space-joined and reparsed) pass every test while failing against
# real ssh. Joining with `"$*"` and handing that one string to `sh -c`
# below is what makes this stub catch that class of bug again.
#
# It logs the host, then each remaining argv element on its own line, to
# SSH_ARGS_LOG before joining — so tests can still assert on the exact
# argv dfxfer_ensure_remote_dir passed, independent of the join/reparse
# step. It runs the joined command with SSH_STUB_REMOTE_HOME as cwd — a
# plain local directory standing in for "the remote's home" — so
# `[ -d ... ]` / `mkdir -p` behave exactly as they would for real, and
# tests can pre-seed that directory to get the "already exists" branch.
# SSH_STUB_EXIT_CODE (default 0) short-circuits before running anything,
# simulating an unreachable host. Kept in its own directory (not fake_bin)
# so it can sit on PATH unconditionally without also activating UNAME_STUB
# for tests that are not exercising the macOS branch.
SSH_STUB = """#!/bin/sh
host="$1"
shift
printf '%s\\n' "$host" >>"$SSH_ARGS_LOG"
for a in "$@"; do printf '%s\\n' "$a"; done >>"$SSH_ARGS_LOG"
[ "${SSH_STUB_EXIT_CODE:-0}" = "0" ] || exit "$SSH_STUB_EXIT_CODE"
cd "$SSH_STUB_REMOTE_HOME" || exit 1
joined="$*"
exec sh -c "$joined"
"""


class DfxferTestBase(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="dfxfer-test-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

        self.args_log = self.tmp / "args.log"
        self.ssh_args_log = self.tmp / "ssh-args.log"
        self.base_dir = self.tmp / "dfxfer"

        self.fake_bin = self.tmp / "fakebin"
        self.fake_bin.mkdir()
        self._write_exec(self.fake_bin / "uname", UNAME_STUB)

        self.ssh_bin = self.tmp / "sshbin"
        self.ssh_bin.mkdir()
        self._write_exec(self.ssh_bin / "ssh", SSH_STUB)

        self.remote_home = self.tmp / "remote-home"
        self.remote_home.mkdir()

    def _write_exec(self, path, content):
        path.write_text(content, encoding="utf-8")
        path.chmod(0o755)
        return path

    @staticmethod
    def _stats_label(version):
        """そのバージョンの実物が --stats で出す件数行の文言を返す。
        rsync 3.1.0 での書き換え（NEWS for rsync 3.1.0, OUTPUT CHANGES）が境界。"""
        try:
            major, minor = (int(part) for part in version.split(".")[:2])
        except ValueError:
            return "Number of files transferred:"
        if (major, minor) >= (3, 1):
            return "Number of regular files transferred:"
        return "Number of files transferred:"

    def _rsync_stub(self, version="3.2.7"):
        return self._write_exec(
            self.tmp / f"rsync-{version}",
            RSYNC_STUB % {"version": version, "label": self._stats_label(version)},
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
            "DFXFER_REMOTE_UP_DIR",
            "DFXFER_REMOTE_DOWN_DIR",
            "DFXFER_RSYNC",
        ):
            run_env.pop(key, None)
        run_env["ARGS_LOG"] = str(self.args_log)
        run_env["SSH_ARGS_LOG"] = str(self.ssh_args_log)
        run_env["SSH_STUB_REMOTE_HOME"] = str(self.remote_home)
        run_env["DFXFER_DIR"] = str(self.base_dir)
        run_env["DFXFER_RSYNC"] = str(self._rsync_stub(rsync_version))
        run_env["PATH"] = f"{self.ssh_bin}:{run_env['PATH']}"
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

    def _logged_ssh_args(self):
        if not self.ssh_args_log.exists():
            return []
        return self.ssh_args_log.read_text(encoding="utf-8").splitlines()


class DestinationResolutionTest(DfxferTestBase):
    """計画書 1.3 の宛先決定規則。決まらないときは必ず止まる。"""

    def test_single_entry_list_needs_no_default(self):
        self._seed_file("toybox")
        proc = self._run(DFUP, env={"DFXFER_HOSTS": "toybox"})

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("toybox:dfxfer/inbox/", self._logged_args())

    def test_explicit_host_wins_and_needs_no_list(self):
        self._seed_file("work-box")
        proc = self._run(DFUP, env={"DFXFER_HOST": "work-box"})

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("work-box:dfxfer/inbox/", self._logged_args())

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
        self.assertIn("toybox:dfxfer/inbox/", self._logged_args())

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
            [f"{self.base_dir}/toybox/out/", "toybox:dfxfer/inbox/"],
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

    def test_creates_remote_send_dir_over_ssh_before_pushing(self):
        """regression: rsync が自動的に作る送り先ディレクトリは**最終要素1つだけ**
        で、中間の階層までは作らない。既定値がネストしたパス（dfxfer/inbox）に
        なったことで、リモートに `~/dfxfer` 自体がまだ無い宛先への初回 dfup は、
        rsync の素の「mkdir failed: No such file or directory」で失敗していた
        （既存のどのテストも fake ssh 経由の rsync スタブへ差し替えているため、
        rsync が実際に何階層まで作れるかは一切検証されておらず、この欠陥は
        どのテストにも捕まらなかった）。"""
        self._seed_file("toybox")
        self.assertFalse((self.remote_home / "dfxfer" / "inbox").exists())

        proc = self._run(DFUP, env={"DFXFER_HOSTS": "toybox"})

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(
            self._logged_ssh_args(),
            ["toybox", "sh", "-s", "--", "dfxfer/inbox"],
        )
        self.assertTrue((self.remote_home / "dfxfer" / "inbox").is_dir())
        self.assertIn("did not exist yet", proc.stdout)

    def test_dry_run_does_not_touch_the_remote(self):
        """regression: `-n` は「何も変更しない」という約束のはずが、dfdown の
        リモート受け皿作成と同じ理由で、dfup 側の作成もこの約束を破りうる。"""
        self._seed_file("toybox")
        proc = self._run(DFUP, "-n", env={"DFXFER_HOSTS": "toybox"})

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(self._logged_ssh_args(), [])
        self.assertFalse((self.remote_home / "dfxfer").exists())

    def test_remote_dir_is_overridable(self):
        self._seed_file("toybox")
        proc = self._run(
            DFUP,
            env={"DFXFER_HOSTS": "toybox", "DFXFER_REMOTE_UP_DIR": "custom-dir"},
        )

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("toybox:custom-dir/", self._logged_args())

    def test_legacy_remote_dir_var_is_rejected_with_guidance(self):
        """regression: DFXFER_REMOTE_DIR は up/down 分離前の変数名で、
        今の dfxfer_remote_dir() はどちらの方向でも読まない。黙って既定値
        （dfxfer/inbox）へフォールバックすると、これを設定したままの
        ~/.zshrc.local からは意図した宛先と違う場所へ静かに送られ続ける
        （利用者は exit 0 の成功表示しか見えない）。設定されていたら
        止めて、新しい変数名を案内する。

        regression（ラウンド2）: 最初の案内は「新しい変数を設定しろ」としか
        言わず、DFXFER_REMOTE_DIR を消せとは言っていなかった。案内どおり
        新変数を追加しても DFXFER_REMOTE_DIR は残ったままなので、
        一字一句同じメッセージで再び止まる。「削除しろ」まで言うこと。"""
        self._seed_file("toybox")
        proc = self._run(
            DFUP,
            env={"DFXFER_HOSTS": "toybox", "DFXFER_REMOTE_DIR": "handoff"},
        )

        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(self._logged_args(), [])
        self.assertIn("DFXFER_REMOTE_DIR", proc.stderr)
        self.assertIn("DFXFER_REMOTE_UP_DIR", proc.stderr)
        self.assertIn("DFXFER_REMOTE_DOWN_DIR", proc.stderr)
        self.assertIn("Remove it", proc.stderr)
        self.assertIn("~/.zshrc.local", proc.stderr)

        # 案内どおり新変数だけ追加しても、旧変数が残っている限り同じ
        # エラーで止まり続けること（「設定しろ」に従うだけでは直らない
        # のが今回のregressionそのものなので、実際に再現させて確認する）。
        self.args_log.unlink(missing_ok=True)
        proc2 = self._run(
            DFUP,
            env={
                "DFXFER_HOSTS": "toybox",
                "DFXFER_REMOTE_DIR": "handoff",
                "DFXFER_REMOTE_UP_DIR": "handoff",
            },
        )
        self.assertNotEqual(proc2.returncode, 0)
        self.assertEqual(self._logged_args(), [])
        self.assertIn("DFXFER_REMOTE_DIR", proc2.stderr)

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


class DfdownInvocationTest(DfxferTestBase):
    """dfdown 固有の差分だけを見る。宛先解決・rsync 探索・--iconv 判定は
    dfup 側で authoritative にテスト済みなので、ここでは再テストしない
    （計画書「検証方針」）。"""

    def test_pulls_remote_downloads_downward_without_destructive_flags(self):
        proc = self._run(DFDOWN, env={"DFXFER_HOSTS": "toybox"})
        args = self._logged_args()

        self.assertEqual(proc.returncode, 0, proc.stderr)

        # 向き: dfup とは逆に、リモートが src・ローカルの in/ が dst。取り違えると
        # ローカルの中身でリモートを上書きしに行く、静かに起きて戻せない事故になる。
        self.assertEqual(
            args[-2:],
            ["toybox:dfxfer/outbox/", f"{self.base_dir}/toybox/in/"],
        )

        # 消す方向のフラグが1つも無いこと。混入するとリモートの原本、または
        # ローカルの既存ファイルが消え、被害が戻らない（計画書 5.4 / 1.7）。
        for flag in ("--delete", "--remove-source-files"):
            self.assertNotIn(flag, args)
        self.assertFalse([a for a in args if a.startswith("--delete")])

    def test_creates_remote_receive_dir_over_ssh_before_pulling(self):
        """regression: rsync は push 方向（dfup）では送り先ディレクトリを
        自動的に作るが、pull 方向では送り元ディレクトリが無いと素の
        rsync エラーで落ちる。`~/dfxfer/outbox/` はこのPRで新設された名前で
        リモート上にまだ存在しないため、対策が無いと分離後の最初の
        dfdown が既存のどの宛先に対しても失敗する。"""
        self.assertFalse((self.remote_home / "dfxfer" / "outbox").exists())

        proc = self._run(DFDOWN, env={"DFXFER_HOSTS": "toybox"})

        self.assertEqual(proc.returncode, 0, proc.stderr)
        # host / sh / -s / -- / <dir>: the script itself travels over stdin
        # (a quoted heredoc), and <dir> is bound to $1 there via `-s --`,
        # rather than being interpolated into the script text — see
        # dfxfer_ensure_remote_dir's comment on why.
        self.assertEqual(
            self._logged_ssh_args(),
            ["toybox", "sh", "-s", "--", "dfxfer/outbox"],
        )
        self.assertTrue((self.remote_home / "dfxfer" / "outbox").is_dir())
        # 新規作成した回だけ、人間が気づけるよう一言出す（regression:
        # タイポで空ディレクトリが黙って生成される事故対策 — 後述の
        # test_typo_in_remote_dir_announces_the_new_directory 参照）。
        self.assertIn("did not exist yet", proc.stdout)

    def test_no_creation_notice_when_remote_dir_already_exists(self):
        """2回目以降の実行では、既に存在するディレクトリを再度
        「作った」と報告しない。"""
        (self.remote_home / "dfxfer" / "outbox").mkdir(parents=True)

        proc = self._run(DFDOWN, env={"DFXFER_HOSTS": "toybox"})

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn("did not exist yet", proc.stdout)

    def test_typo_in_remote_dir_announces_the_new_directory(self):
        """regression: この機能が入る前は、存在しないディレクトリを指せば
        rsync が exit 23 で落ちたためタイポは必ず露見した。今は
        dfxfer_ensure_remote_dir が代わりに空ディレクトリを作ってしまうため、
        新規作成時の通知が無いと `DFXFER_REMOTE_DOWN_DIR` のタイポが
        「サーバ側がまだ何も出していないだけ」に見えてしまい、
        気づけないまま exit 0 になる。"""
        proc = self._run(
            DFDOWN,
            env={"DFXFER_HOSTS": "toybox", "DFXFER_REMOTE_DOWN_DIR": "downlaods"},
        )

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("downlaods", proc.stdout)
        self.assertIn("did not exist yet", proc.stdout)

    def test_dry_run_does_not_touch_the_remote(self):
        """regression: `-n` は「何も変更しない」という約束のはずが、
        リモート受け皿ディレクトリの作成だけは無条件に実行されていた。
        dry-run では ssh 自体を一切呼ばない。"""
        proc = self._run(DFDOWN, "-n", env={"DFXFER_HOSTS": "toybox"})

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(self._logged_ssh_args(), [])
        self.assertFalse((self.remote_home / "dfxfer" / "outbox").exists())

    def test_rsync_filter_rule_value_is_not_mistaken_for_dry_run(self):
        """regression: dfxfer_has_dry_run_flag は「'-'で始まり'n'を含む」
        トークンを全て dry-run 扱いしていた。rsync のフィルタルールの値
        （`-f '- *.png'` のような除外指定）は慣習的に "- " で始まり、
        パターン自体に 'n' を含むことも普通にあるため、これも dry-run と
        誤判定されて通常転送中にリモートの mkdir がスキップされ、
        このPRが解消したはずの素の rsync エラーが復活してしまう。"""
        proc = self._run(
            DFDOWN,
            "-f",
            "- *.png",
            env={"DFXFER_HOSTS": "toybox"},
        )

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn("Dry run", proc.stdout)
        self.assertEqual(
            self._logged_ssh_args(),
            ["toybox", "sh", "-s", "--", "dfxfer/outbox"],
        )

    def test_remote_mkdir_failure_aborts_before_any_transfer(self):
        """ssh 経由の mkdir が失敗したら、rsync を一切起動せずに止まる
        （中途半端に転送を試みて分かりにくいエラーを重ねない）。"""
        proc = self._run(
            DFDOWN,
            env={"DFXFER_HOSTS": "toybox", "SSH_STUB_EXIT_CODE": "1"},
        )

        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(self._logged_args(), [])
        self.assertIn("toybox:dfxfer/outbox", proc.stderr)

    def test_creates_local_receive_dir_when_missing(self):
        """初回実行で mkdir を人間にさせない（計画書 1.2）。"""
        in_dir = self.base_dir / "toybox" / "in"
        self.assertFalse(in_dir.exists())

        proc = self._run(DFDOWN, env={"DFXFER_HOSTS": "toybox"})

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertTrue(in_dir.is_dir())

    def test_reports_when_nothing_came_down(self):
        """スタブは実際にファイルを落とさないので、in/ は空のまま残る —
        「動いたのか分からない」状態にならないよう一言出す（孫1の
        「Nothing to send」と対になる文言）。"""
        proc = self._run(DFDOWN, env={"DFXFER_HOSTS": "toybox"})

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Nothing came down", proc.stdout)

    def test_nothing_came_down_is_based_on_this_runs_transfer_count_not_dir_emptiness(
        self,
    ):
        """regression: 以前は受信先ディレクトリが「今すでに空かどうか」を見ていた。
        一度でも何か落ちてきていれば in/ はその後ずっと非空のままなので、次に
        リモートが本当に空だった回でも「Nothing came down」が出なくなり、
        利用者は今回何も来なかったことに気づけなかった。判定基準は
        必ず「今回の転送で何件動いたか」（rsync --stats の出力）でなければならない。"""
        in_dir = self.base_dir / "toybox" / "in"
        in_dir.mkdir(parents=True)
        (in_dir / "leftover-from-a-previous-pull.txt").write_text(
            "hello\n", encoding="utf-8"
        )

        # 今回は何も転送しなかった体（RSYNC_STUB_TRANSFERRED 未設定 = 0件）。
        # in/ 自体は非空だが、それでも「Nothing came down」が出ること。
        proc = self._run(DFDOWN, env={"DFXFER_HOSTS": "toybox"})
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("Nothing came down", proc.stdout)

        # 今回は1件転送した体。in/ が非空なのは変わらないが、今回何か来たので
        # 「Nothing came down」は出ないこと。
        proc = self._run(
            DFDOWN,
            env={"DFXFER_HOSTS": "toybox", "RSYNC_STUB_TRANSFERRED": "1"},
        )
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn("Nothing came down", proc.stdout)

    def test_thousands_separator_in_transfer_count_does_not_crash(self):
        """regression: rsync は 3.1.0 以降、--stats の件数を既定で "1,200" のように
        3桁区切りで出す（-h の有無とは無関係。NEWS for rsync 3.1.0 の
        "Output numbers in 3-digit groups by default"）。素朴に
        `grep -oE '[0-9]+'` で数字だけ拾うと "1" と "200" の2行にマッチし、
        後続の `-eq 0` 比較が「integer expression expected」で失敗する
        （転送自体は成功しているのに、利用者はこのエラーを見て不安になる）。"""
        proc = self._run(
            DFDOWN,
            env={"DFXFER_HOSTS": "toybox", "RSYNC_STUB_TRANSFERRED": "1,200"},
        )

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stderr, "")
        self.assertNotIn("Nothing came down", proc.stdout)

    def test_transfer_count_is_read_from_pre_3_1_stats_wording(self):
        """regression: 件数行の文言を rsync 3.1.0 以降のもの（"Number of regular
        files transferred:"）だけで拾っていたため、2.6.9 / 3.0.x — README が
        「ASCII のファイル名しか扱わないならそのままで実害はありません」と明記して
        許容している構成 — では**何件落ちてきても毎回**「Nothing came down」に
        なっていた。利用者は Troubleshooting の「リモートが空だったか差分が
        無かったか」を読み、実際には in/ に落ちている成果物を探しに行かない。

        既存テストで捕まらなかったのは、スタブが名乗ったバージョンに関係なく
        常に新しい文言を返していたため（実物の 2.6.9 が出せない出力を前提に
        緑になっていた）。"""
        proc = self._run(
            DFDOWN,
            env={"DFXFER_HOSTS": "toybox", "RSYNC_STUB_TRANSFERRED": "3"},
            rsync_version="2.6.9",
        )

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn("Nothing came down", proc.stdout)

    def test_openrsync_is_not_handed_stats_and_still_transfers(self):
        """regression: --stats を無条件に渡していたため、それを知らない
        openrsync（新しめの macOS が rsync の代わりに同梱する）では転送に入る前に
        エラー終了し、`set -e` で dfdown が丸ごと落ちていた。件数が読めないことは
        サマリー1行の問題でしかないのに、コマンド自体が使えなくなる。

        件数が読めない側では「Nothing came down」と断定せず、受信先を案内する。"""
        stub = self._write_exec(self.tmp / "openrsync", OPENRSYNC_STUB)
        proc = self._run(
            DFDOWN,
            env={"DFXFER_HOSTS": "toybox", "DFXFER_RSYNC": str(stub)},
        )
        args = self._logged_args()

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertNotIn("--stats", args)
        # 転送そのものは通常どおり組み立てられていること。
        self.assertEqual(
            args[-2:],
            ["toybox:dfxfer/outbox/", f"{self.base_dir}/toybox/in/"],
        )
        self.assertNotIn("Nothing came down", proc.stdout)
        self.assertIn(str(self.base_dir / "toybox" / "in"), proc.stdout)

    def test_extra_arguments_pass_through_to_rsync(self):
        proc = self._run(DFDOWN, "-n", env={"DFXFER_HOSTS": "toybox"})
        args = self._logged_args()

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("-n", args)
        # 透過引数はパスより前。rsync は src/dst を末尾に取る。
        self.assertLess(args.index("-n"), len(args) - 2)

    def test_remote_dir_is_overridable(self):
        proc = self._run(
            DFDOWN,
            env={"DFXFER_HOSTS": "toybox", "DFXFER_REMOTE_DOWN_DIR": "custom-dir"},
        )

        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("toybox:custom-dir/", self._logged_args())

    def test_shares_destination_resolution_with_dfup(self):
        """代表1本だけ: 宛先が決まらないときに dfdown も止まること
        （宛先決定の5規則そのものは DestinationResolutionTest が dfup 経由で
        authoritative にテスト済み。共通の bin/dfxfer-lib.sh を通っている
        ことの確認に留める）。"""
        proc = self._run(DFDOWN)

        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(self._logged_args(), [])
        self.assertIn("DFXFER_HOST", proc.stderr)
        self.assertIn("export", proc.stderr)

    def test_shares_legacy_remote_dir_rejection_with_dfup(self):
        """代表1本だけ: 旧 DFXFER_REMOTE_DIR が設定されていると dfdown も
        止まること（ガード自体は DfupInvocationTest が authoritative に
        テスト済み。共通の dfxfer_remote_dir() を通っていることの確認に
        留める）。"""
        proc = self._run(
            DFDOWN,
            env={"DFXFER_HOSTS": "toybox", "DFXFER_REMOTE_DIR": "handoff"},
        )

        self.assertNotEqual(proc.returncode, 0)
        self.assertEqual(self._logged_args(), [])
        self.assertIn("DFXFER_REMOTE_DIR", proc.stderr)


if __name__ == "__main__":
    unittest.main()
