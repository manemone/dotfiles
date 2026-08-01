"""Tests for bin/ocw's ocw-meter instrumentation.

孫2 (docs/planning/DOC-003_ai-llm-cost-observability_計画.md §11/孫2 prompt):
ocw now issues a run_id per worktree, persists it under the worktree's
private git metadata dir, and emits run.start/run.end via ocw-meter
(fail-open). This file is black-box (subprocess, matching
test_ocw_meter.py's style): each test builds a throwaway git repo under a
tempdir and invokes the real bin/ocw executable against it, so nothing
here touches this repo or its worktrees.

Coverage:
  - run_id is generated, printed as a `run:` line, and persisted at
    the linked worktree's `<gitdir>/ocw-run-id` (NOT literally
    "<worktree>/.git/ocw-run-id" — `.git` in a linked worktree is a
    *file*, not a directory; see the comment in bin/ocw)
  - run.start / run.end are recorded via the real ocw-meter with the
    expected fields (T07-adjacent: run_id ties the two together)
  - T18 (meter absent from PATH): ocw's own output/exit codes for
    create and remove are unaffected
  - T19 (ocw-meter storage unwritable): same
  - pre-existing error paths (missing args, duplicate branch, `ocw ls`,
    unmerged-branch removal without -f) are unaffected by instrumentation

Herdr-mode env var passing (`--env OCW_ROLE=...` / `--env OCW_RUN_ID=...`
on `herdr workspace create` / `herdr pane split`) is not covered here: it
requires a running Herdr server and would spawn real terminal panes,
which is out of scope for a hermetic, no-side-effect unit suite. It was
verified manually against a live Herdr server (see PR description): a
throwaway workspace was created with `--env FOO=bar`, and `herdr pane run
... "echo $FOO"` confirmed the value reached the pane's shell.
"""

import json
import os
import pathlib
import re
import subprocess
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
OCW = REPO_ROOT / "bin" / "ocw"

# Standard-tool PATH only; deliberately excludes REPO_ROOT/bin so ocw-meter
# is absent unless a test opts in via meter_on_path=True. Non-Herdr ocw
# paths never shell out to python3, so it doesn't need to be on PATH here.
BASE_PATH_DIRS = ("/usr/bin", "/bin", "/usr/local/bin")

RUN_LINE_RE = re.compile(r"^run:\s+(\S+)$", re.MULTILINE)


def _git(args, cwd):
    result = subprocess.run(
        ["git", *args],
        cwd=str(cwd),
        capture_output=True,
        text=True,
        timeout=30,
    )
    if result.returncode != 0:
        raise RuntimeError(f"git {args} failed in {cwd}: {result.stderr}")
    return result


def make_repo(root):
    """A minimal git repo at <root>/main with one commit on branch `main`,
    plus a local bare "origin" remote with its HEAD symref set.

    ocw resolves the *main* worktree's parent directory as where sibling
    worktrees get created (repo_root = git worktree list's first entry;
    worktree_dir = dirname(repo_root)/<slug>) — mirroring how this repo's
    own worktrees sit next to `master/` under `.../dotfiles/`.

    The origin remote isn't optional scaffolding: ocw's own base_ref
    fallback (`git symbolic-ref refs/remotes/origin/HEAD`) is a real git
    command run under `set -euo pipefail`. Every real checkout ocw is
    used against has an origin with a HEAD symref (that's what `git
    clone` sets up), so without reproducing it here, these tests would be
    exercising a bare-repo shape ocw was never meant to run against,
    rather than the instrumentation this file is actually testing.
    """
    origin_dir = pathlib.Path(root) / "origin.git"
    _git(["init", "-q", "--bare", "-b", "main", str(origin_dir)], root)

    main_dir = pathlib.Path(root) / "main"
    main_dir.mkdir(parents=True)
    _git(["init", "-q", "-b", "main"], main_dir)
    _git(["config", "user.email", "test@example.invalid"], main_dir)
    _git(["config", "user.name", "Test"], main_dir)
    (main_dir / "README.md").write_text("test\n", encoding="utf-8")
    _git(["add", "README.md"], main_dir)
    _git(["commit", "-q", "-m", "initial"], main_dir)
    _git(["remote", "add", "origin", str(origin_dir)], main_dir)
    _git(["push", "-q", "-u", "origin", "main"], main_dir)
    _git(["remote", "set-head", "origin", "main"], main_dir)
    return main_dir


def run_ocw(args, cwd, meter_on_path=False, meter_home=None, extra_env=None, timeout=30):
    path_dirs = list(BASE_PATH_DIRS)
    if meter_on_path:
        path_dirs.insert(0, str(REPO_ROOT / "bin"))
    env = {
        "PATH": ":".join(path_dirs),
        "HOME": os.environ.get("HOME", "/root"),
    }
    if meter_home is not None:
        env["OCW_METER_HOME"] = str(meter_home)
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        [str(OCW), *args],
        cwd=str(cwd),
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def read_events(home):
    events = []
    events_dir = pathlib.Path(home) / "events"
    if not events_dir.exists():
        return events
    for path in sorted(events_dir.glob("*.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                events.append(json.loads(line))
    return events


def extract_run_id(stdout):
    match = RUN_LINE_RE.search(stdout)
    assert match, f"no 'run:' line found in stdout:\n{stdout}"
    return match.group(1)


class OcwTestCase(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.repo_root = make_repo(self.tmpdir.name)
        self.meter_home = pathlib.Path(self.tmpdir.name) / "ocw-meter-home"

    def tearDown(self):
        self.tmpdir.cleanup()


class RunIdAndMeterEventsTests(OcwTestCase):
    """run_id issuance/persistence + real ocw-meter recording (run.start/end)."""

    def test_create_prints_and_persists_run_id(self):
        result = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(result.returncode, 0, result.stderr)

        run_id = extract_run_id(result.stdout)
        self.assertRegex(run_id, r"^\d+-[0-9a-f]+$")

        worktree_dir = self.repo_root.parent / "widget-maker"
        self.assertTrue(worktree_dir.is_dir())

        git_dir = _git(["rev-parse", "--absolute-git-dir"], worktree_dir).stdout.strip()
        run_id_file = pathlib.Path(git_dir) / "ocw-run-id"
        self.assertTrue(run_id_file.is_file())
        self.assertEqual(run_id_file.read_text(encoding="utf-8").strip(), run_id)

    def test_create_then_remove_records_run_start_and_run_end(self):
        create = run_ocw(
            ["widget-maker"], self.repo_root, meter_on_path=True, meter_home=self.meter_home
        )
        self.assertEqual(create.returncode, 0, create.stderr)
        run_id = extract_run_id(create.stdout)

        events = read_events(self.meter_home)
        starts = [e for e in events if e["event_type"] == "run.start" and e["run_id"] == run_id]
        self.assertEqual(len(starts), 1, events)
        self.assertEqual(starts[0]["source"], "ocw")
        self.assertEqual(starts[0]["base_ref"], "main")
        self.assertIn("widget-maker", starts[0]["command"])

        remove = run_ocw(
            ["rm", "widget-maker"],
            self.repo_root,
            meter_on_path=True,
            meter_home=self.meter_home,
        )
        self.assertEqual(remove.returncode, 0, remove.stderr)

        events = read_events(self.meter_home)
        ends = [e for e in events if e["event_type"] == "run.end" and e["run_id"] == run_id]
        self.assertEqual(len(ends), 1, events)
        self.assertEqual(ends[0]["source"], "ocw")
        self.assertEqual(ends[0]["outcome"], "success")

    def test_force_remove_records_run_end_with_failure_outcome(self):
        # `ocw rm -f` discards a worktree without requiring it merged/clean
        # (usage's own "ocw rm -f failed-experiment" example) — a run that
        # didn't reach a mergeable result, so it must be distinguishable
        # from the successful-completion `run.end` above.
        create = run_ocw(
            ["widget-maker"], self.repo_root, meter_on_path=True, meter_home=self.meter_home
        )
        self.assertEqual(create.returncode, 0, create.stderr)
        run_id = extract_run_id(create.stdout)

        worktree_dir = self.repo_root.parent / "widget-maker"
        (worktree_dir / "extra.txt").write_text("unmerged change\n", encoding="utf-8")
        _git(["add", "extra.txt"], worktree_dir)
        _git(["commit", "-q", "-m", "unmerged commit"], worktree_dir)

        remove = run_ocw(
            ["rm", "-f", "widget-maker"],
            self.repo_root,
            meter_on_path=True,
            meter_home=self.meter_home,
        )
        self.assertEqual(remove.returncode, 0, remove.stderr)

        events = read_events(self.meter_home)
        ends = [e for e in events if e["event_type"] == "run.end" and e["run_id"] == run_id]
        self.assertEqual(len(ends), 1, events)
        self.assertEqual(ends[0]["outcome"], "failure")


class MeterAbsentRegressionTests(OcwTestCase):
    """T18: ocw-meter entirely absent from PATH must not change ocw's behavior."""

    def test_create_and_remove_succeed_without_ocw_meter_on_path(self):
        create = run_ocw(["widget-maker"], self.repo_root, meter_on_path=False)
        self.assertEqual(create.returncode, 0, create.stderr)
        self.assertRegex(create.stdout, RUN_LINE_RE)

        worktree_dir = self.repo_root.parent / "widget-maker"
        self.assertTrue(worktree_dir.is_dir())

        remove = run_ocw(["rm", "widget-maker"], self.repo_root, meter_on_path=False)
        self.assertEqual(remove.returncode, 0, remove.stderr)
        self.assertFalse(worktree_dir.exists())

    def test_stderr_has_no_ocw_meter_noise_when_absent(self):
        # `command -v` failing should be silent — no "command not found"
        # noise should leak onto stderr just because ocw-meter is missing.
        create = run_ocw(["widget-maker"], self.repo_root, meter_on_path=False)
        self.assertEqual(create.returncode, 0, create.stderr)
        self.assertNotIn("ocw-meter", create.stderr)


class MeterStorageUnwritableTests(OcwTestCase):
    """T19: ocw-meter present but unable to write must not affect ocw.

    ocw-meter's own contract (bin/ocw-meter's design + bin/README.md) is to
    print a one-line stderr warning on a write failure rather than stay
    silent about it ("never silent about failures" — verified directly
    below). So "ocw's behavior is unaffected" is checked on stdout, which
    is exactly what ocw itself prints; it deliberately is NOT checked by
    asserting stderr is empty, since a warning there is by design, not a
    regression.
    """

    def test_stdout_is_unaffected_when_storage_is_read_only(self):
        ro_parent = pathlib.Path(self.tmpdir.name) / "ro-parent"
        ro_parent.mkdir()
        os.chmod(ro_parent, 0o500)
        unwritable_home = ro_parent / "ocw-meter-home"
        working_home = pathlib.Path(self.tmpdir.name) / "working-home"
        try:
            baseline_create = run_ocw(
                ["widget-maker"], self.repo_root, meter_on_path=True, meter_home=working_home
            )
            self.assertEqual(baseline_create.returncode, 0, baseline_create.stderr)
            baseline_run_id = extract_run_id(baseline_create.stdout)
            baseline_remove = run_ocw(
                ["rm", "widget-maker"], self.repo_root, meter_on_path=True, meter_home=working_home
            )
            self.assertEqual(baseline_remove.returncode, 0, baseline_remove.stderr)

            create = run_ocw(
                ["widget-maker"], self.repo_root, meter_on_path=True, meter_home=unwritable_home
            )
            self.assertEqual(create.returncode, 0, create.stderr)
            create_run_id = extract_run_id(create.stdout)
            # Confirms the failure path was actually exercised (not a
            # silent no-op that would make the stdout comparison vacuous).
            self.assertIn("ocw-meter", create.stderr)

            # stdout identical modulo the run_id token (a fresh random
            # value each run) proves the read-only storage didn't add,
            # drop, or reorder a single line of ocw's own output.
            self.assertEqual(
                baseline_create.stdout.replace(baseline_run_id, "<RUN_ID>"),
                create.stdout.replace(create_run_id, "<RUN_ID>"),
            )

            remove = run_ocw(
                ["rm", "widget-maker"], self.repo_root, meter_on_path=True, meter_home=unwritable_home
            )
            self.assertEqual(remove.returncode, 0, remove.stderr)
            self.assertEqual(
                baseline_remove.stdout,
                remove.stdout,
            )
        finally:
            os.chmod(ro_parent, 0o700)


class ExistingBehaviorRegressionTests(OcwTestCase):
    """Pre-existing ocw error paths/subcommands must be untouched."""

    def test_create_missing_task_name_exits_nonzero(self):
        result = run_ocw([], self.repo_root)
        self.assertNotEqual(result.returncode, 0)

    def test_duplicate_branch_dies(self):
        first = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(first.returncode, 0, first.stderr)

        second = run_ocw(["widget-maker"], self.repo_root)
        self.assertNotEqual(second.returncode, 0)
        self.assertIn("branch already exists", second.stderr)

    def test_ls_lists_worktrees(self):
        create = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)

        result = run_ocw(["ls"], self.repo_root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("widget-maker", result.stdout)

    def test_remove_nonexistent_worktree_dies(self):
        result = run_ocw(["rm", "does-not-exist"], self.repo_root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("worktree dir does not exist", result.stderr)

    def test_remove_unmerged_branch_without_force_dies(self):
        create = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)

        worktree_dir = self.repo_root.parent / "widget-maker"
        (worktree_dir / "extra.txt").write_text("unmerged change\n", encoding="utf-8")
        _git(["add", "extra.txt"], worktree_dir)
        _git(["commit", "-q", "-m", "unmerged commit"], worktree_dir)

        remove = run_ocw(["rm", "widget-maker"], self.repo_root)
        self.assertNotEqual(remove.returncode, 0)
        self.assertIn("branch is not merged", remove.stderr)

        # Force-remove so this test doesn't leak a dangling worktree.
        force_remove = run_ocw(["rm", "-f", "widget-maker"], self.repo_root)
        self.assertEqual(force_remove.returncode, 0, force_remove.stderr)


if __name__ == "__main__":
    unittest.main()
