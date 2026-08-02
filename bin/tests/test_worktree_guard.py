"""shared/helpers.sh の linked-worktree ガードのテスト。

背景: 各 deploy.sh はこのチェックアウトから $HOME へ symlink を張る。
チェックアウトが linked worktree（`git worktree add` / `ocw` が作るもの）だと、
worktree 削除時に ~/.zshrc や ~/.claude/skills/* が黙って壊れる。
実際にこの事故が起きたため、警告を出すガードを入れた。

ネットワーク・外部APIは一切使わない（一時ディレクトリ内のgitリポジトリのみ）。
"""

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HELPERS = REPO_ROOT / "shared" / "helpers.sh"

WARNING_MARKER = "Deploying from a linked git worktree"


def _git(*args, cwd):
    subprocess.run(
        ["git", *args],
        cwd=cwd,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


class WorktreeGuardTest(unittest.TestCase):
    """本物の git worktree を一時ディレクトリに作って挙動を確認する。"""

    @classmethod
    def setUpClass(cls):
        if shutil.which("git") is None:
            raise unittest.SkipTest("git が無い環境ではスキップ")

        cls.tmp = tempfile.mkdtemp(prefix="ocw-worktree-guard-")
        cls.main = Path(cls.tmp) / "main"
        cls.main.mkdir()

        _git("init", "-q", "-b", "main", cwd=cls.main)
        _git("config", "user.email", "test@example.com", cwd=cls.main)
        _git("config", "user.name", "test", cwd=cls.main)
        (cls.main / "seed.txt").write_text("seed\n", encoding="utf-8")
        _git("add", "-A", cwd=cls.main)
        _git("commit", "-qm", "seed", cwd=cls.main)

        cls.linked = Path(cls.tmp) / "linked"
        _git("worktree", "add", "-q", "-b", "wt", str(cls.linked), cwd=cls.main)

        # helpers.sh を両方のチェックアウトに配置する。ガードは "$0" の
        # ディレクトリを見るため、実行するスクリプトの場所が判定対象になる。
        for root in (cls.main, cls.linked):
            (root / "shared").mkdir(exist_ok=True)
            shutil.copy(HELPERS, root / "shared" / "helpers.sh")
            script = root / "deploy.sh"
            script.write_text(
                '#!/bin/sh\n. "$(dirname -- "$0")/shared/helpers.sh"\n'
                'printf "deployed\\n"\n',
                encoding="utf-8",
            )
            script.chmod(0o755)

    @classmethod
    def tearDownClass(cls):
        subprocess.run(
            ["git", "worktree", "remove", "--force", str(cls.linked)],
            cwd=cls.main,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def _run(self, root, env=None):
        environ = dict(os.environ)
        environ.pop("DOTFILES_WORKTREE_WARNED", None)
        environ.pop("DOTFILES_QUIET_WORKTREE_WARNING", None)
        environ["NO_COLOR"] = "1"
        if env:
            environ.update(env)
        return subprocess.run(
            ["sh", str(root / "deploy.sh")],
            capture_output=True,
            text=True,
            env=environ,
            cwd=root,
        )

    def test_linked_worktree_warns(self):
        result = self._run(self.linked)
        self.assertIn(WARNING_MARKER, result.stderr)
        self.assertEqual(result.returncode, 0, "警告であって失敗ではない")
        self.assertIn("deployed", result.stdout, "デプロイ自体は継続する")

    def test_linked_worktree_points_at_main_worktree(self):
        result = self._run(self.linked)
        self.assertIn(str(self.main), result.stderr, "復旧先のメインworktreeを案内する")

    def test_main_worktree_does_not_warn(self):
        result = self._run(self.main)
        self.assertNotIn(WARNING_MARKER, result.stderr)
        self.assertEqual(result.returncode, 0)

    def test_quiet_flag_silences_warning(self):
        result = self._run(self.linked, {"DOTFILES_QUIET_WORKTREE_WARNING": "1"})
        self.assertNotIn(WARNING_MARKER, result.stderr)

    def test_warns_only_once_per_process_tree(self):
        # deploy-all.sh が各 deploy.sh を呼ぶ状況の再現。
        # 親が既に警告済みなら子は繰り返さない。
        result = self._run(self.linked, {"DOTFILES_WORKTREE_WARNED": "1"})
        self.assertNotIn(WARNING_MARKER, result.stderr)

    def test_outside_git_repo_does_not_warn(self):
        outside = Path(self.tmp) / "outside"
        (outside / "shared").mkdir(parents=True)
        shutil.copy(HELPERS, outside / "shared" / "helpers.sh")
        script = outside / "deploy.sh"
        script.write_text(
            '#!/bin/sh\n. "$(dirname -- "$0")/shared/helpers.sh"\nprintf "deployed\\n"\n',
            encoding="utf-8",
        )
        script.chmod(0o755)

        result = self._run(outside)
        self.assertNotIn(WARNING_MARKER, result.stderr)
        self.assertEqual(result.returncode, 0, "gitリポジトリ外でも壊れない")


if __name__ == "__main__":
    unittest.main()
