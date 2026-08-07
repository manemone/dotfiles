"""Tests for bin/ocw's ocw-meter instrumentation.

孫2 (docs/planning/DOC-2608021229-a_ai-llm-cost-observability_計画.md §11/孫2 prompt):
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

import atexit
import json
import os
import pathlib
import re
import shlex
import shutil
import subprocess
import tempfile
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
OCW = REPO_ROOT / "bin" / "ocw"

# Standard-tool PATH only; deliberately excludes REPO_ROOT/bin so ocw-meter
# is absent unless a test opts in via meter_on_path=True. Non-Herdr ocw
# paths never shell out to python3, so it doesn't need to be on PATH here.
BASE_PATH_DIRS = ("/usr/bin", "/bin", "/usr/local/bin")

# bin/ocw's open_vscode() (bin/ocw:180-197) launches a real VS Code window
# whenever `command -v code` succeeds, which it does on any machine with VS
# Code installed — /usr/local/bin (part of BASE_PATH_DIRS above) commonly
# holds a `code` symlink to the real CLI. Every run_ocw(["widget-maker"],
# ...) call in this suite runs in non-Herdr mode (the only mode reachable
# without a live Herdr server), which is exactly the code path that calls
# open_vscode() — so without this shim, the whole suite pops a real VS Code
# window per call site (~20 of them). Built once at import time (the shim
# is stateless, so every test in this file can safely share it) and always
# placed ahead of BASE_PATH_DIRS in run_ocw()'s PATH, the same "shim
# directory ahead of the real tool" shape as write_git_shim_* below use for
# `git`.
#
# The shim also appends every invocation to _CODE_SHIM_LOG so tests can
# assert it was never actually called — not just that ocw's own exit code
# looked fine (a silent no-op and a real VS Code launch both return 0).
# VscodeAutoLaunchRegressionTests below is what exercises that.
_CODE_SHIM_DIR = tempfile.mkdtemp(prefix="ocw-test-code-shim-")
atexit.register(shutil.rmtree, _CODE_SHIM_DIR, ignore_errors=True)
_CODE_SHIM_LOG = pathlib.Path(_CODE_SHIM_DIR) / "invocations.log"
_code_shim_path = pathlib.Path(_CODE_SHIM_DIR) / "code"
_code_shim_path.write_text(
    f"#!/bin/sh\necho \"$@\" >> {shlex.quote(str(_CODE_SHIM_LOG))}\nexit 0\n",
    encoding="utf-8",
)
_code_shim_path.chmod(0o755)

RUN_LINE_RE = re.compile(r"^run:\s+(\S+)$", re.MULTILINE)
REPO_LINE_RE = re.compile(r"^repo:\s+(\S+)$", re.MULTILINE)
BRANCH_LINE_RE = re.compile(r"^branch:\s+(\S+)$", re.MULTILINE)


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


def make_bare_repo(root, name="proj.git"):
    """A bare repo at <root>/<name> with one commit on branch `main`, and
    (deliberately) no `origin` remote of its own — this mirrors what a
    real bare repo used as *someone else's* origin looks like from the
    inside (ADR DOC-2608062258 §2.2/§2.3): `git worktree list --porcelain`
    has exactly one entry (the bare dir itself, with a `bare` line instead
    of `branch`), and `git symbolic-ref HEAD` resolves to the default
    branch. With no `ocw.worktreeDir` override, ocw's default template
    (`{repo_parent}/{name}`) puts worktrees at dirname(repo_root)/<name> —
    i.e. right next to the bare directory, exercising the same "no
    `origin/HEAD` to fall back to" base_ref path bin/ocw's create_worktree
    has to survive (ADR §3.10).
    """
    bare_dir = pathlib.Path(root) / name
    _git(["init", "-q", "--bare", "-b", "main", str(bare_dir)], root)

    with tempfile.TemporaryDirectory() as scratch_root:
        scratch_dir = pathlib.Path(scratch_root) / "scratch"
        scratch_dir.mkdir()
        _git(["init", "-q", "-b", "main"], scratch_dir)
        _git(["config", "user.email", "test@example.invalid"], scratch_dir)
        _git(["config", "user.name", "Test"], scratch_dir)
        (scratch_dir / "README.md").write_text("test\n", encoding="utf-8")
        _git(["add", "README.md"], scratch_dir)
        _git(["commit", "-q", "-m", "initial"], scratch_dir)
        _git(["remote", "add", "origin", str(bare_dir)], scratch_dir)
        _git(["push", "-q", "-u", "origin", "main"], scratch_dir)

    return bare_dir


def set_config(repo_dir, key, value):
    _git(["config", key, value], repo_dir)


def make_repo_without_origin(root, dir_name="main"):
    """A minimal git repo at <root>/<dir_name> with one commit and no
    `origin` remote at all -- exercises repo_name's third resolution step
    (ADR DOC-2608062258 §3.6, the path-based guess), which make_repo()
    can never reach since it always configures an origin remote.
    """
    repo_dir = pathlib.Path(root) / dir_name
    repo_dir.mkdir(parents=True)
    _git(["init", "-q", "-b", "main"], repo_dir)
    _git(["config", "user.email", "test@example.invalid"], repo_dir)
    _git(["config", "user.name", "Test"], repo_dir)
    (repo_dir / "README.md").write_text("test\n", encoding="utf-8")
    _git(["add", "README.md"], repo_dir)
    _git(["commit", "-q", "-m", "initial"], repo_dir)
    return repo_dir


def run_ocw(args, cwd, meter_on_path=False, meter_home=None, extra_env=None, path_prepend=None, timeout=30):
    # _CODE_SHIM_DIR goes ahead of BASE_PATH_DIRS (see its module-level
    # comment) so the no-op `code` always wins over a real one that might
    # sit in /usr/local/bin. path_prepend (git shims) still takes priority
    # over both — those shim directories only ever contain `git`, so `code`
    # lookups fall through to _CODE_SHIM_DIR regardless.
    path_dirs = [_CODE_SHIM_DIR, *BASE_PATH_DIRS]
    if meter_on_path:
        path_dirs.insert(0, str(REPO_ROOT / "bin"))
    if path_prepend:
        path_dirs = list(path_prepend) + path_dirs
    env = {
        "PATH": ":".join(path_dirs),
        "HOME": os.environ.get("HOME", "/root"),
    }
    if meter_home is not None:
        env["OCW_METER_HOME"] = str(meter_home)
    if extra_env:
        env.update(extra_env)
    # Belt-and-suspenders alongside _CODE_SHIM_DIR above: bin/ocw's own
    # OCW_NO_VSCODE opt-out (open_vscode(), bin/ocw:180-197) is set
    # unconditionally and after extra_env so no test can accidentally clear
    # it. Two independent layers (a PATH that never resolves to a real
    # `code`, and ocw refusing to invoke it at all) mean a regression in
    # either one alone still can't launch a real VS Code window.
    env["OCW_NO_VSCODE"] = "1"
    # Also unconditional and after extra_env: bin/ocw now reads git config
    # `ocw.*` (ocw_config_get()), which resolves through the normal
    # system/global/local layering. Without this, a developer's own
    # `~/.gitconfig` (a real, plausible place to put `ocw.worktreeDir` per
    # ADR DOC-2608062258 §3.4's own "put a personal default in --global"
    # rationale) would leak into every test in this file and change where
    # worktrees get created — verified by reproducing a `[ocw]
    # worktreeDir = ...` block in a throwaway $HOME and watching
    # test_default_template_matches_current_layout fail. This is
    # independent of HOME: the tilde-expansion test overrides HOME via
    # extra_env, and GIT_CONFIG_GLOBAL/SYSTEM are what git actually reads
    # for global/system config regardless of $HOME.
    env["GIT_CONFIG_GLOBAL"] = "/dev/null"
    env["GIT_CONFIG_SYSTEM"] = "/dev/null"
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


def extract_repo_name(stdout):
    match = REPO_LINE_RE.search(stdout)
    assert match, f"no 'repo:' line found in stdout:\n{stdout}"
    return match.group(1)


def extract_branch(stdout):
    match = BRANCH_LINE_RE.search(stdout)
    assert match, f"no 'branch:' line found in stdout:\n{stdout}"
    return match.group(1)


def write_git_shim_failing_absolute_git_dir(shim_dir, worktree_dir):
    """A `git` wrapper that fails only `-C <worktree_dir> rev-parse
    --absolute-git-dir` (exactly bin/ocw's run_id-persistence lookup for
    that one worktree) and delegates everything else — including that
    same rev-parse for any *other* path, and every other subcommand ocw
    itself needs (worktree add/remove, show-ref, branch, symbolic-ref,
    merge-base, status) — to the real system git. This exercises the
    `|| worktree_git_dir=""` fail-open fallback in bin/ocw without a real
    disk-full/read-only-mount setup, which isn't reproducible from a
    plain user-permission test.
    """
    real_git_path = next(
        (p for p in ("/usr/bin/git", "/bin/git") if pathlib.Path(p).exists()),
        shutil.which("git"),
    )
    assert real_git_path, "no real git found to delegate to"
    target = shlex.quote(str(worktree_dir))
    shim = pathlib.Path(shim_dir) / "git"
    shim.write_text(
        "#!/usr/bin/env bash\n"
        f'if [ "$1" = "-C" ] && [ "$2" = {target} ] && '
        '[ "$3" = "rev-parse" ] && [ "$4" = "--absolute-git-dir" ]; then\n'
        "  exit 1\n"
        "fi\n"
        f'exec "{real_git_path}" "$@"\n',
        encoding="utf-8",
    )
    shim.chmod(0o755)


def write_git_shim_redirecting_absolute_git_dir(shim_dir, worktree_dir, redirect_to):
    """A `git` wrapper that makes `-C <worktree_dir> rev-parse
    --absolute-git-dir` *succeed*, but answer with `redirect_to` instead
    of the real git dir — everything else delegates to real git. Used to
    make bin/ocw's run-id `printf` target a caller-controlled (e.g.
    read-only) directory without needing a real disk-full/RO-mount, which
    isn't reproducible from a plain user-permission test.
    """
    real_git_path = next(
        (p for p in ("/usr/bin/git", "/bin/git") if pathlib.Path(p).exists()),
        shutil.which("git"),
    )
    assert real_git_path, "no real git found to delegate to"
    target = shlex.quote(str(worktree_dir))
    redirect = shlex.quote(str(redirect_to))
    shim = pathlib.Path(shim_dir) / "git"
    shim.write_text(
        "#!/usr/bin/env bash\n"
        f'if [ "$1" = "-C" ] && [ "$2" = {target} ] && '
        '[ "$3" = "rev-parse" ] && [ "$4" = "--absolute-git-dir" ]; then\n'
        f"  printf '%s\\n' {redirect}\n"
        "  exit 0\n"
        "fi\n"
        f'exec "{real_git_path}" "$@"\n',
        encoding="utf-8",
    )
    shim.chmod(0o755)


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


class RunIdPersistenceFailOpenTests(OcwTestCase):
    """The run_id persistence step itself (rev-parse + printf into the
    worktree's private git dir) must be fail-open: a failure there is not
    an ocw-meter failure (T18/T19 above), it's `bin/ocw`'s own git/bash
    logic, and it ran into the exact `set -euo pipefail` trap ocw-meter's
    own design notes warn about elsewhere in this codebase."""

    def test_create_succeeds_when_git_rev_parse_absolute_git_dir_fails(self):
        worktree_dir = self.repo_root.parent / "widget-maker"
        shim_dir = pathlib.Path(self.tmpdir.name) / "git-shim"
        shim_dir.mkdir()
        write_git_shim_failing_absolute_git_dir(shim_dir, worktree_dir)

        create = run_ocw(["widget-maker"], self.repo_root, path_prepend=[str(shim_dir)])
        self.assertEqual(create.returncode, 0, create.stderr)
        self.assertRegex(create.stdout, RUN_LINE_RE)
        self.assertTrue(worktree_dir.is_dir())

        remove = run_ocw(["rm", "widget-maker"], self.repo_root, path_prepend=[str(shim_dir)])
        self.assertEqual(remove.returncode, 0, remove.stderr)
        self.assertFalse(worktree_dir.exists())

    def test_create_succeeds_and_leaks_no_bash_error_when_run_id_write_fails(self):
        # Distinct from the rev-parse-failure case above: here rev-parse
        # *succeeds* (as it always does in real use — worktree add just
        # created that git dir), but the actual `printf >file` write into
        # it fails (permission denied). Left-to-right redirect ordering
        # (`2>/dev/null` before `>file`) is what's under test here.
        baseline = run_ocw(["baseline-widget"], self.repo_root)
        self.assertEqual(baseline.returncode, 0, baseline.stderr)
        baseline_run_id = extract_run_id(baseline.stdout)

        worktree_dir = self.repo_root.parent / "widget-maker"
        shim_dir = pathlib.Path(self.tmpdir.name) / "git-shim"
        shim_dir.mkdir()
        ro_dir = pathlib.Path(self.tmpdir.name) / "ro-git-dir"
        ro_dir.mkdir()
        os.chmod(ro_dir, 0o500)
        try:
            write_git_shim_redirecting_absolute_git_dir(shim_dir, worktree_dir, ro_dir)

            create = run_ocw(["widget-maker"], self.repo_root, path_prepend=[str(shim_dir)])
            self.assertEqual(create.returncode, 0, create.stderr)
            create_run_id = extract_run_id(create.stdout)
            self.assertFalse((ro_dir / "ocw-run-id").exists())

            # stderr identical (modulo the differing worktree slug, which
            # git's own "Preparing worktree" message echoes) to a fully-
            # working run proves the write failure produced no raw bash
            # diagnostic ("Permission denied" / its localized equivalent)
            # on ocw's real stderr.
            self.assertEqual(
                baseline.stderr.replace("baseline-widget", "widget-maker"),
                create.stderr,
            )
            self.assertEqual(
                baseline.stdout.replace(baseline_run_id, "<RUN_ID>").replace("baseline-widget", "widget-maker"),
                create.stdout.replace(create_run_id, "<RUN_ID>"),
            )
        finally:
            os.chmod(ro_dir, 0o700)


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
        # Message changed by 孫3's porcelain reverse-lookup rewrite
        # (ADR DOC-2608062258 §3.9): there's no longer a single
        # pre-computed dir path to report as missing, since resolution
        # now works backwards from `git worktree list --porcelain`.
        result = run_ocw(["rm", "does-not-exist"], self.repo_root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no worktree found", result.stderr)

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

    def test_remove_current_worktree_is_guarded(self):
        create = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)

        worktree_dir = self.repo_root.parent / "widget-maker"
        result = run_ocw(["rm", "widget-maker"], worktree_dir)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("do not remove the current worktree", result.stderr)

        # The worktree is still there (removal was refused) — force-remove
        # from main so this test doesn't leak a dangling worktree.
        force_remove = run_ocw(["rm", "-f", "widget-maker"], self.repo_root)
        self.assertEqual(force_remove.returncode, 0, force_remove.stderr)

    def test_remove_other_worktree_from_main_is_not_guarded(self):
        create = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)

        result = run_ocw(["rm", "widget-maker"], self.repo_root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("do not remove the current worktree", result.stderr)


class VscodeAutoLaunchRegressionTests(OcwTestCase):
    """Regression coverage for the incident where bin/ocw's open_vscode()
    (bin/ocw:180-197) launched a real VS Code window as a side effect of
    running this suite (and, separately, of a manual `bin/ocw` invocation
    made outside run_ocw() while investigating a test failure in this
    file). Two independent protections exist — _CODE_SHIM_DIR ahead of
    BASE_PATH_DIRS in run_ocw()'s PATH, and ocw's own OCW_NO_VSCODE opt-out
    — and this class proves each one actually suppresses an invocation,
    not just that ocw's exit code looks fine (a silent no-op and a real VS
    Code launch both return 0 here, so returncode alone can't tell them
    apart).
    """

    def setUp(self):
        super().setUp()
        if _CODE_SHIM_LOG.exists():
            _CODE_SHIM_LOG.unlink()

    def test_widget_maker_never_invokes_the_path_shim(self):
        # Exercises both protections together, exactly as every other test
        # in this file does via run_ocw(): _CODE_SHIM_DIR ahead of
        # BASE_PATH_DIRS, plus OCW_NO_VSCODE set unconditionally.
        create = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)
        run_ocw(["rm", "-f", "widget-maker"], self.repo_root)

        self.assertFalse(
            _CODE_SHIM_LOG.exists(),
            "open_vscode() invoked `code`: "
            + (_CODE_SHIM_LOG.read_text(encoding="utf-8") if _CODE_SHIM_LOG.exists() else ""),
        )

    def test_ocw_no_vscode_alone_prevents_invocation(self):
        # Isolates OCW_NO_VSCODE from _CODE_SHIM_DIR: puts a different,
        # single-use detecting shim ahead of PATH via path_prepend, which
        # takes priority over _CODE_SHIM_DIR (see run_ocw()'s comment on
        # PATH ordering) — so a real invocation would land here even if
        # _CODE_SHIM_DIR's PATH trick were doing all the work. A pass here
        # means OCW_NO_VSCODE's check in open_vscode() (which runs before
        # even the `command -v code` probe) is what's actually stopping it.
        detect_dir = pathlib.Path(self.tmpdir.name) / "code-detect-shim"
        detect_dir.mkdir()
        detect_log = detect_dir / "invoked"
        shim = detect_dir / "code"
        shim.write_text(f"#!/bin/sh\ntouch {shlex.quote(str(detect_log))}\nexit 0\n", encoding="utf-8")
        shim.chmod(0o755)

        create = run_ocw(["widget-maker"], self.repo_root, path_prepend=[str(detect_dir)])
        self.assertEqual(create.returncode, 0, create.stderr)
        run_ocw(["rm", "-f", "widget-maker"], self.repo_root, path_prepend=[str(detect_dir)])

        self.assertFalse(detect_log.exists(), "open_vscode() invoked `code` despite OCW_NO_VSCODE being set")

    def test_without_ocw_no_vscode_open_vscode_would_actually_invoke_code(self):
        # Negative control: proves the two tests above are exercising a
        # real protection, not passing vacuously because ocw never calls
        # `code` at all in this environment. Bypasses run_ocw() (which
        # always sets OCW_NO_VSCODE=1 unconditionally — see its comment)
        # to invoke ocw directly with a detecting shim on PATH and
        # OCW_NO_VSCODE left unset.
        detect_dir = pathlib.Path(self.tmpdir.name) / "code-negative-control-shim"
        detect_dir.mkdir()
        detect_log = detect_dir / "invoked"
        shim = detect_dir / "code"
        shim.write_text(f"#!/bin/sh\ntouch {shlex.quote(str(detect_log))}\nexit 0\n", encoding="utf-8")
        shim.chmod(0o755)

        env = {
            "PATH": f"{detect_dir}:{':'.join(BASE_PATH_DIRS)}",
            "HOME": os.environ.get("HOME", "/root"),
        }
        result = subprocess.run(
            [str(OCW), "widget-maker"],
            cwd=str(self.repo_root),
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(
            detect_log.exists(),
            "expected the negative control to invoke the detecting `code` shim "
            "(OCW_NO_VSCODE left unset) — if it didn't, the two tests above may "
            "be passing vacuously rather than because of a real protection",
        )

        # Best-effort cleanup of the worktree this negative-control call
        # created (it bypassed run_ocw(), so nothing else tracks it).
        subprocess.run(
            [str(OCW), "rm", "-f", "widget-maker"],
            cwd=str(self.repo_root),
            env=env,
            capture_output=True,
            text=True,
            timeout=30,
        )


class BareRepoTests(unittest.TestCase):
    """bare リポジトリ対応 (ADR DOC-2608062258 §2.1/§2.2/§2.3, 孫1 プロンプト項目2)."""

    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.bare_dir = make_bare_repo(self.tmpdir.name)

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_create_from_bare_repo_creates_sibling_worktree(self):
        result = run_ocw(["widget-maker"], self.bare_dir)
        self.assertEqual(result.returncode, 0, result.stderr)

        worktree_dir = self.bare_dir.parent / "widget-maker"
        self.assertTrue(worktree_dir.is_dir())
        # make_bare_repo() deliberately configures no origin remote of its
        # own, so there's no origin/HEAD to resolve base_ref from -- it
        # must fall back to repo_root's own HEAD (ADR §3.10) instead of
        # blowing up under set -euo pipefail.
        self.assertIn("base:        main", result.stdout)

    def test_ls_works_from_bare_repo(self):
        create = run_ocw(["widget-maker"], self.bare_dir)
        self.assertEqual(create.returncode, 0, create.stderr)

        result = run_ocw(["ls"], self.bare_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("(bare)", result.stdout)
        self.assertIn("widget-maker", result.stdout)

    def test_repo_name_strips_dot_git_suffix_for_bare_repo(self):
        # No ocw.repoName and no origin remote -> falls all the way to the
        # path-based guess, which for a bare repo strips ".git" off the
        # directory's own basename (ADR §3.6 step 3).
        result = run_ocw(["widget-maker"], self.bare_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(extract_repo_name(result.stdout), "proj")

    def test_rm_works_from_bare_repo(self):
        # A bare repo is the only place invocation_root comes back empty
        # (ADR §2.1/§3.10) -- this is the one black-box path that actually
        # exercises remove_worktree()'s guard-skip for that case, not just
        # create_worktree()'s bare handling covered above.
        create = run_ocw(["widget-maker"], self.bare_dir)
        self.assertEqual(create.returncode, 0, create.stderr)

        worktree_dir = self.bare_dir.parent / "widget-maker"
        self.assertTrue(worktree_dir.is_dir())

        remove = run_ocw(["rm", "widget-maker"], self.bare_dir)
        self.assertEqual(remove.returncode, 0, remove.stderr)
        self.assertFalse(worktree_dir.exists())


class RepoNameResolutionTests(OcwTestCase):
    """repo_name 解決順 (ADR DOC-2608062258 §3.6): ocw.repoName > origin URL
    の basename > パス推測。"""

    def test_ocw_repo_name_config_wins(self):
        set_config(self.repo_root, "ocw.repoName", "custom-name")

        result = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(extract_repo_name(result.stdout), "custom-name")

    def test_repo_name_derives_from_origin_url_when_unset(self):
        # make_repo()'s origin remote is <root>/origin.git -> basename with
        # ".git" stripped is "origin".
        result = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(extract_repo_name(result.stdout), "origin")


class RepoNamePathGuessTests(unittest.TestCase):
    """repo_name 解決順の第3段（パスからの推測、ADR DOC-2608062258 §3.6）の
    非 bare 側2分岐。make_repo() は常に origin remote を張るためどちらの
    分岐にも到達できず、専用に origin 無しリポジトリを使う。"""

    def test_main_named_dir_uses_parent_dir_name(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo_dir = make_repo_without_origin(tmp, dir_name="main")

            result = run_ocw(["widget-maker"], repo_dir)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(extract_repo_name(result.stdout), pathlib.Path(tmp).name)

    def test_non_special_dir_name_is_used_as_is(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo_dir = make_repo_without_origin(tmp, dir_name="myrepo")

            result = run_ocw(["widget-maker"], repo_dir)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(extract_repo_name(result.stdout), "myrepo")


class WorktreeDirTemplateTests(OcwTestCase):
    """ocw.worktreeDir の雛形展開・検証・掃除境界の逆算 (ADR DOC-2608062258
    §3.4 / §3.5 / §2.9)."""

    def test_default_template_matches_current_layout(self):
        # No ocw.worktreeDir set: the default `{repo_parent}/{name}` must
        # produce exactly the pre-孫1 hardcoded dirname(repo_root)/<slug>
        # path -- the completion condition's "unchanged default behavior"
        # made into its own explicit assertion.
        result = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(result.returncode, 0, result.stderr)

        worktree_dir = self.repo_root.parent / "widget-maker"
        self.assertTrue(worktree_dir.is_dir())

    def test_nested_template_changes_creation_location(self):
        set_config(self.repo_root, "ocw.worktreeDir", "{repo_root}/.worktrees/{name}")

        result = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(result.returncode, 0, result.stderr)

        worktree_dir = self.repo_root / ".worktrees" / "widget-maker"
        self.assertTrue(worktree_dir.is_dir())
        self.assertFalse((self.repo_root.parent / "widget-maker").exists())

    def test_nested_template_round_trips_through_remove(self):
        # remove_worktree() computes worktree_dir through the same template
        # expansion as create_worktree() (孫1 プロンプト項目5) -- this is
        # the one black-box test that would fail if that wiring were
        # reverted back to a hardcoded {repo_parent}/{name} path while
        # create_worktree() kept using the template.
        set_config(self.repo_root, "ocw.worktreeDir", "{repo_root}/.worktrees/{name}")

        create = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)

        worktree_dir = self.repo_root / ".worktrees" / "widget-maker"
        self.assertTrue(worktree_dir.is_dir())

        remove = run_ocw(["rm", "widget-maker"], self.repo_root)
        self.assertEqual(remove.returncode, 0, remove.stderr)
        self.assertFalse(worktree_dir.exists())

    def test_prefixed_name_template_places_worktree_correctly(self):
        # {name} isn't its own path component here -- exercises the
        # non-trivial cleanup-boundary recompute for this exact ADR §2.9
        # table row ({repo_parent}/{repo}-{name} -> boundary {repo_parent}).
        set_config(self.repo_root, "ocw.worktreeDir", "{repo_parent}/{repo}-{name}")

        result = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(result.returncode, 0, result.stderr)

        # repo_name derives from make_repo()'s origin remote (origin.git).
        worktree_dir = self.repo_root.parent / "origin-widget-maker"
        self.assertTrue(worktree_dir.is_dir())

    def test_tilde_expansion(self):
        # HOME is swapped to a tempdir for this one process invocation
        # only -- the real $HOME is never touched.
        fake_home = pathlib.Path(self.tmpdir.name) / "fake-home"
        fake_home.mkdir()
        set_config(self.repo_root, "ocw.worktreeDir", "~/.cache/ocw/{repo}/{name}")

        result = run_ocw(["widget-maker"], self.repo_root, extra_env={"HOME": str(fake_home)})
        self.assertEqual(result.returncode, 0, result.stderr)

        # repo_name derives from make_repo()'s origin remote (origin.git).
        worktree_dir = fake_home / ".cache" / "ocw" / "origin" / "widget-maker"
        self.assertTrue(worktree_dir.is_dir())

    def test_unknown_placeholder_dies_naming_the_key(self):
        set_config(self.repo_root, "ocw.worktreeDir", "{nope}/{name}")

        result = run_ocw(["widget-maker"], self.repo_root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("{nope}", result.stderr)
        self.assertFalse((self.repo_root.parent / "widget-maker").exists())

    def test_template_without_name_placeholder_dies(self):
        set_config(self.repo_root, "ocw.worktreeDir", "{repo_parent}/fixed")

        result = run_ocw(["widget-maker"], self.repo_root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("{name}", result.stderr)

    def test_relative_template_dies(self):
        set_config(self.repo_root, "ocw.worktreeDir", "relative/{name}")

        result = run_ocw(["widget-maker"], self.repo_root)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.repo_root.parent / "relative").exists())

    def test_name_alone_dies_with_no_boundary_message(self):
        # Distinct die branch from test_relative_template_dies above: with
        # no '/' anywhere before {name}, the cleanup boundary can't be
        # computed at all (ADR §2.9's "{name}" row) -- a different failure
        # than "expands to a relative path".
        set_config(self.repo_root, "ocw.worktreeDir", "{name}")

        result = run_ocw(["widget-maker"], self.repo_root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no '/' before {name}", result.stderr)

    def test_root_boundary_template_dies_with_specific_message(self):
        # "/{name}" is itself an absolute path, but its cleanup boundary
        # collapses to the filesystem root -- a different failure than
        # "not absolute", and must say so.
        set_config(self.repo_root, "ocw.worktreeDir", "/{name}")

        result = run_ocw(["widget-maker"], self.repo_root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("filesystem root", result.stderr)


class BranchNamingTests(OcwTestCase):
    """`ai/` 接頭辞の廃止とスラッシュ対応 (ADR DOC-2608062258 §3.1/§3.2/§3.3,
    孫2 プロンプト §1/§2/§4)."""

    def test_slash_branch_name_creates_nested_worktree(self):
        result = run_ocw(["feature/foo"], self.repo_root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(extract_branch(result.stdout), "feature/foo")

        worktree_dir = self.repo_root.parent / "feature" / "foo"
        self.assertTrue(worktree_dir.is_dir())
        self.assertIn(str(worktree_dir), result.stdout)

        branch_list = _git(["branch", "--list", "feature/foo"], self.repo_root).stdout
        self.assertIn("feature/foo", branch_list)

    def test_sibling_slash_branches_can_coexist(self):
        # git worktree add auto-creates the shared "feature/" parent (ADR
        # §2.4); the D/F conflict git itself enforces on refs is what makes
        # the two directories/branches non-colliding (ADR §2.5).
        first = run_ocw(["feature/foo"], self.repo_root)
        self.assertEqual(first.returncode, 0, first.stderr)

        second = run_ocw(["feature/bar"], self.repo_root)
        self.assertEqual(second.returncode, 0, second.stderr)

        self.assertTrue((self.repo_root.parent / "feature" / "foo").is_dir())
        self.assertTrue((self.repo_root.parent / "feature" / "bar").is_dir())

    def test_branch_has_no_ai_prefix(self):
        result = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(extract_branch(result.stdout), "widget-maker")

    def test_uppercase_and_spaces_are_normalized_as_before(self):
        # Pre-孫2 normalize_name() behavior, preserved by normalize_branch_name().
        result = run_ocw(["Fix The Thing"], self.repo_root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(extract_branch(result.stdout), "fix-the-thing")


class InvalidBranchNameRegressionTests(OcwTestCase):
    """ブランチ名検証の check-ref-format への委譲 (ADR DOC-2608062258
    §3.2/§2.6, 孫2 プロンプト §3)。

    ADR §2.6 の実測表に挙がる `feature//foo` / `-x`（先頭ハイフン）/ `HEAD`
    は、このリポジトリの normalize_branch_name()（連続スラッシュの1本化・
    前後の `/` `-` の除去・小文字化）を通過した時点でそれぞれ
    `feature/foo` / `x` / `head` という**有効な**ブランチ名になり、
    check-ref-format まで到達しない。これは意図した挙動（友好的な
    自動修正の対象であって拒否対象ではない）であり、下の
    test_friendly_* 系がそれを裏付ける。normalize_branch_name を通過しても
    なお残る無効パターン（`.lock` 終端・`..` を含むパス）で、
    check-ref-format への委譲そのものを検証する。
    """

    def test_dot_lock_suffix_dies_with_git_fatal_message(self):
        result = run_ocw(["foo.lock"], self.repo_root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("foo.lock", result.stderr)
        self.assertIn("fatal:", result.stderr)
        self.assertFalse((self.repo_root.parent / "foo.lock").exists())

    def test_dotdot_path_traversal_dies_and_creates_nothing(self):
        parent = self.repo_root.parent
        before = set(os.listdir(parent))

        result = run_ocw(["../escaped-worktree"], self.repo_root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("fatal:", result.stderr)

        after = set(os.listdir(parent))
        self.assertEqual(before, after)
        self.assertFalse((parent.parent / "escaped-worktree").exists())

    def test_empty_after_normalization_dies(self):
        # "---" normalizes to "" via normalize_branch_name()'s
        # leading/trailing '/'-'-' trim, before check-ref-format is ever
        # invoked.
        result = run_ocw(["---"], self.repo_root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("worktree name became empty", result.stderr)

    def test_friendly_double_slash_is_sanitized_not_rejected(self):
        result = run_ocw(["feature//foo"], self.repo_root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(extract_branch(result.stdout), "feature/foo")

    def test_friendly_leading_hyphen_is_sanitized_not_rejected(self):
        result = run_ocw(["-x"], self.repo_root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(extract_branch(result.stdout), "x")

    def test_friendly_head_is_sanitized_not_rejected(self):
        result = run_ocw(["HEAD"], self.repo_root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(extract_branch(result.stdout), "head")


class RmResolutionTests(OcwTestCase):
    """`ocw rm` の porcelain 逆引き解決 (ADR DOC-2608062258 §3.9, 孫3 プロンプト §1)."""

    def test_removes_by_branch_name(self):
        create = run_ocw(["feature/foo"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)
        worktree_dir = self.repo_root.parent / "feature" / "foo"
        self.assertTrue(worktree_dir.is_dir())

        remove = run_ocw(["rm", "feature/foo"], self.repo_root)
        self.assertEqual(remove.returncode, 0, remove.stderr)
        self.assertFalse(worktree_dir.exists())

    def test_removes_by_directory_basename(self):
        create = run_ocw(["feature/foo"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)
        worktree_dir = self.repo_root.parent / "feature" / "foo"

        # "foo" isn't the branch name ("feature/foo") or an absolute path --
        # only stage 2 (directory basename) can resolve it.
        remove = run_ocw(["rm", "foo"], self.repo_root)
        self.assertEqual(remove.returncode, 0, remove.stderr)
        self.assertFalse(worktree_dir.exists())

    def test_removes_by_absolute_path(self):
        create = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)
        worktree_dir = self.repo_root.parent / "widget-maker"

        remove = run_ocw(["rm", str(worktree_dir)], self.repo_root)
        self.assertEqual(remove.returncode, 0, remove.stderr)
        self.assertFalse(worktree_dir.exists())

    def test_legacy_ai_prefixed_worktree_is_removable_by_bare_slug(self):
        # Migration rescue (ADR §3.1/§3.9): a worktree still on a pre-孫2
        # `ai/<slug>` branch (created directly via `git worktree add`, the
        # way it would have existed before this umbrella, not through ocw
        # itself) must still resolve for `ocw rm <slug>`.
        legacy_dir = self.repo_root.parent / "legacy"
        _git(["worktree", "add", "-b", "ai/legacy", str(legacy_dir), "main"], self.repo_root)

        remove = run_ocw(["rm", "legacy"], self.repo_root)
        self.assertEqual(remove.returncode, 0, remove.stderr)
        self.assertFalse(legacy_dir.exists())

    def test_ambiguous_basename_dies_listing_both_candidates_and_removes_neither(self):
        first = run_ocw(["feature/foo"], self.repo_root)
        self.assertEqual(first.returncode, 0, first.stderr)
        second = run_ocw(["hotfix/foo"], self.repo_root)
        self.assertEqual(second.returncode, 0, second.stderr)

        feature_dir = self.repo_root.parent / "feature" / "foo"
        hotfix_dir = self.repo_root.parent / "hotfix" / "foo"

        remove = run_ocw(["rm", "foo"], self.repo_root)
        self.assertNotEqual(remove.returncode, 0)
        self.assertIn(str(feature_dir), remove.stderr)
        self.assertIn(str(hotfix_dir), remove.stderr)
        self.assertTrue(feature_dir.is_dir())
        self.assertTrue(hotfix_dir.is_dir())

    def test_main_worktree_is_never_a_removal_candidate(self):
        result = run_ocw(["rm", "main"], self.repo_root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no worktree found", result.stderr)
        self.assertTrue(self.repo_root.is_dir())

    def test_nonexistent_name_dies(self):
        result = run_ocw(["rm", "does-not-exist"], self.repo_root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("no worktree found", result.stderr)


class MergeDeterminationTests(OcwTestCase):
    """マージ済み判定の再定義 (ADR DOC-2608062258 §3.7, 孫3 プロンプト §2)."""

    def test_squash_merged_branch_is_removable_without_force(self):
        create = run_ocw(["feature/foo"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)

        worktree_dir = self.repo_root.parent / "feature" / "foo"
        (worktree_dir / "extra.txt").write_text("extra\n", encoding="utf-8")
        _git(["add", "extra.txt"], worktree_dir)
        _git(["commit", "-q", "-m", "extra commit"], worktree_dir)

        _git(["merge", "--squash", "feature/foo"], self.repo_root)
        _git(["commit", "-q", "-m", "squash merge feature/foo"], self.repo_root)

        remove = run_ocw(["rm", "feature/foo"], self.repo_root)
        self.assertEqual(remove.returncode, 0, remove.stderr)
        self.assertFalse(worktree_dir.exists())

    def test_unmerged_branch_still_requires_force(self):
        create = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)

        worktree_dir = self.repo_root.parent / "widget-maker"
        (worktree_dir / "extra.txt").write_text("unmerged\n", encoding="utf-8")
        _git(["add", "extra.txt"], worktree_dir)
        _git(["commit", "-q", "-m", "unmerged commit"], worktree_dir)

        remove = run_ocw(["rm", "widget-maker"], self.repo_root)
        self.assertNotEqual(remove.returncode, 0)
        self.assertIn("branch is not merged", remove.stderr)

        force_remove = run_ocw(["rm", "-f", "widget-maker"], self.repo_root)
        self.assertEqual(force_remove.returncode, 0, force_remove.stderr)

    def test_ordinary_ancestor_merge_is_still_removable(self):
        # The other existing tests' branches are trivial ancestors of main
        # (tip == base, no new commits) -- this one adds a real commit and
        # fast-forward merges it, exercising plain ancestry detection (not
        # squash detection) explicitly.
        create = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)

        worktree_dir = self.repo_root.parent / "widget-maker"
        (worktree_dir / "extra.txt").write_text("extra\n", encoding="utf-8")
        _git(["add", "extra.txt"], worktree_dir)
        _git(["commit", "-q", "-m", "extra commit"], worktree_dir)

        _git(["merge", "--ff-only", "widget-maker"], self.repo_root)

        remove = run_ocw(["rm", "widget-maker"], self.repo_root)
        self.assertEqual(remove.returncode, 0, remove.stderr)

    def test_ocw_merged_into_config_widens_the_candidate_set(self):
        set_config(self.repo_root, "ocw.mergedInto", "alt-target")
        _git(["branch", "alt-target"], self.repo_root)

        create = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)

        worktree_dir = self.repo_root.parent / "widget-maker"
        (worktree_dir / "extra.txt").write_text("extra\n", encoding="utf-8")
        _git(["add", "extra.txt"], worktree_dir)
        _git(["commit", "-q", "-m", "extra commit"], worktree_dir)

        # Merged only into alt-target, never into main.
        _git(["checkout", "-q", "alt-target"], self.repo_root)
        _git(["merge", "-q", "--ff-only", "widget-maker"], self.repo_root)
        _git(["checkout", "-q", "main"], self.repo_root)

        remove = run_ocw(["rm", "widget-maker"], self.repo_root)
        self.assertEqual(remove.returncode, 0, remove.stderr)

    def test_umbrella_style_base_ref_is_a_merge_candidate(self):
        # ADR §3.7 candidate 2: a worktree branched off an umbrella branch
        # (not main) is only ever an ancestor of that umbrella -- exactly
        # the shape umbrella-orchestrator worktrees have. Without the
        # creation-time base_ref persisted to ocw-base-ref, this would
        # require -f even though it's genuinely merged (into its actual
        # target, just not main).
        _git(["branch", "umbrella"], self.repo_root)

        create = run_ocw(["child", "umbrella"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)
        self.assertIn("base:        umbrella", create.stdout)

        worktree_dir = self.repo_root.parent / "child"
        (worktree_dir / "extra.txt").write_text("extra\n", encoding="utf-8")
        _git(["add", "extra.txt"], worktree_dir)
        _git(["commit", "-q", "-m", "child work"], worktree_dir)

        _git(["checkout", "-q", "umbrella"], self.repo_root)
        _git(["merge", "-q", "--no-ff", "child"], self.repo_root)
        _git(["checkout", "-q", "main"], self.repo_root)

        remove = run_ocw(["rm", "child"], self.repo_root)
        self.assertEqual(remove.returncode, 0, remove.stderr)

    def test_github_merge_check_opt_in_fails_open_without_gh_on_path(self):
        set_config(self.repo_root, "ocw.githubMergeCheck", "true")

        create = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)

        worktree_dir = self.repo_root.parent / "widget-maker"
        (worktree_dir / "extra.txt").write_text("unmerged\n", encoding="utf-8")
        _git(["add", "extra.txt"], worktree_dir)
        _git(["commit", "-q", "-m", "unmerged commit"], worktree_dir)

        # gh is absent from run_ocw()'s PATH (BASE_PATH_DIRS) -- this must
        # not crash or hang ocw, just fail to additionally confirm a merge,
        # leaving the branch correctly rejected as still unmerged.
        remove = run_ocw(["rm", "widget-maker"], self.repo_root)
        self.assertNotEqual(remove.returncode, 0)
        self.assertIn("branch is not merged", remove.stderr)
        self.assertNotIn("gh: command not found", remove.stderr)

        force_remove = run_ocw(["rm", "-f", "widget-maker"], self.repo_root)
        self.assertEqual(force_remove.returncode, 0, force_remove.stderr)

    def test_github_merge_check_is_evaluated_once_not_once_per_candidate(self):
        # Round-1 review finding: gh_merge_check() only takes $branch, never
        # $candidate, so it must run at most once regardless of how many
        # integration-ref candidates resolve -- looping it per candidate
        # was pure duplicated network round-trips with no new information.
        set_config(self.repo_root, "ocw.githubMergeCheck", "true")
        set_config(self.repo_root, "ocw.mergedInto", "alt-target")
        _git(["branch", "alt-target"], self.repo_root)

        create = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)

        worktree_dir = self.repo_root.parent / "widget-maker"
        (worktree_dir / "extra.txt").write_text("unmerged\n", encoding="utf-8")
        _git(["add", "extra.txt"], worktree_dir)
        _git(["commit", "-q", "-m", "unmerged commit"], worktree_dir)

        gh_shim_dir = pathlib.Path(self.tmpdir.name) / "gh-call-count-shim"
        gh_shim_dir.mkdir()
        gh_log = gh_shim_dir / "calls.log"
        gh_shim = gh_shim_dir / "gh"
        gh_shim.write_text(
            f"#!/bin/sh\necho \"$@\" >> {shlex.quote(str(gh_log))}\nexit 1\n",
            encoding="utf-8",
        )
        gh_shim.chmod(0o755)

        # ocw.mergedInto=alt-target, the persisted base_ref (main), HEAD,
        # and origin/HEAD are 4 distinct-looking candidates here (alt-target
        # is a separate branch from main, so this isn't exercising dedup --
        # see MergeDeterminationTests for that), all unmerged.
        remove = run_ocw(["rm", "widget-maker"], self.repo_root, path_prepend=[str(gh_shim_dir)])
        self.assertNotEqual(remove.returncode, 0)
        self.assertIn("branch is not merged", remove.stderr)

        calls = gh_log.read_text(encoding="utf-8").splitlines() if gh_log.exists() else []
        self.assertEqual(len(calls), 1, calls)


class NoResolvableCandidateRegressionTests(unittest.TestCase):
    """基準refが1つも解決できない経路 (ADR DOC-2608062258 §3.7, ラウンド1レビュー指摘7a)."""

    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_dies_without_force_and_dash_f_still_records_failure_outcome(self):
        bare_dir = make_bare_repo(self.tmpdir.name)

        create = run_ocw(["widget-maker"], bare_dir)
        self.assertEqual(create.returncode, 0, create.stderr)
        run_id = extract_run_id(create.stdout)

        # Delete the branch that create_worktree() resolved and persisted as
        # base_ref (candidate 2), and that `symbolic-ref --short HEAD`
        # (candidate 3, this repo is bare) also names -- HEAD's symref
        # still points at refs/heads/main afterwards, but that ref no
        # longer resolves to anything. ocw.mergedInto is unset (candidate
        # 1) and there's no origin for this repo to fall back to
        # (candidate 4), so all 4 candidates end up unresolvable.
        _git(["update-ref", "-d", "refs/heads/main"], bare_dir)

        without_force = run_ocw(["rm", "widget-maker"], bare_dir)
        self.assertNotEqual(without_force.returncode, 0)
        self.assertIn("cannot determine an integration ref", without_force.stderr)
        self.assertIn("-f", without_force.stderr)

        meter_home = pathlib.Path(self.tmpdir.name) / "ocw-meter-home"
        force_remove = run_ocw(
            ["rm", "-f", "widget-maker"], bare_dir, meter_on_path=True, meter_home=meter_home
        )
        self.assertEqual(force_remove.returncode, 0, force_remove.stderr)

        events = read_events(meter_home)
        ends = [e for e in events if e["event_type"] == "run.end" and e["run_id"] == run_id]
        self.assertEqual(len(ends), 1, events)
        self.assertEqual(ends[0]["outcome"], "failure")


class DetachedWorktreeTests(unittest.TestCase):
    """detached ワークツリー (ラウンド1レビュー指摘7b・指摘3)."""

    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.repo_root = make_repo(self.tmpdir.name)

    def tearDown(self):
        self.tmpdir.cleanup()

    def _add_detached_worktree(self, name):
        worktree_dir = self.repo_root.parent / name
        _git(["worktree", "add", "-q", "--detach", str(worktree_dir), "main"], self.repo_root)
        return worktree_dir

    def test_dies_with_a_detached_specific_message_without_force(self):
        worktree_dir = self._add_detached_worktree("detachedwt")

        result = run_ocw(["rm", "detachedwt"], self.repo_root)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("detached", result.stderr)
        self.assertIn("-f", result.stderr)
        # The branch: line must name the worktree, not trail off after
        # "branch: " with nothing (round-1 finding 3's exact repro).
        self.assertNotIn("branch:    \n", result.stdout)
        self.assertTrue(worktree_dir.is_dir())

    def test_is_removable_with_force(self):
        worktree_dir = self._add_detached_worktree("detachedwt")

        result = run_ocw(["rm", "-f", "detachedwt"], self.repo_root)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(worktree_dir.exists())


class UnbornBranchWorktreeRegressionTests(unittest.TestCase):
    """unborn ブランチのワークツリー（ラウンド1レビュー指摘1・ラウンド2レビュー
    新規指摘2）。

    `git worktree add --orphan` は Git 2.42 以降専用（macOS 同梱の git は
    2.39系）であり、これを使うと macOS では RuntimeError で落ちる（CI は
    Linux で新しい git を積んでいるため気づけない）。unborn ブランチは
    バージョン非依存の経路（コミット0件のbareリポジトリへの1本目の
    `worktree add`）でも作れるため、そちらを使う。
    """

    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_unborn_branch_worktree_is_removable_with_force_without_aborting(self):
        # A worktree whose branch has never been committed to reports a
        # real `branch refs/heads/<name>` line in porcelain output even
        # though that ref doesn't exist yet -- `git branch -D` on it fails
        # with "not found" (or "used by worktree" before the worktree
        # itself is removed), which under `set -e` used to abort
        # remove_worktree between `worktree remove` succeeding and
        # run.end ever firing (round-1 finding 1).
        bare_dir = pathlib.Path(self.tmpdir.name) / "proj.git"
        _git(["init", "-q", "--bare", "--initial-branch=main", str(bare_dir)], self.tmpdir.name)
        _git(["worktree", "add", "-q", "-b", "work", str(bare_dir.parent / "work")], bare_dir)

        worktree_dir = bare_dir.parent / "work"
        self.assertTrue(worktree_dir.is_dir())

        remove = run_ocw(["rm", "-f", "work"], bare_dir)
        self.assertEqual(remove.returncode, 0, remove.stderr)
        self.assertFalse(worktree_dir.exists())

        branch_list = _git(["branch", "--list", "work"], bare_dir).stdout
        self.assertNotIn("work", branch_list)


class RmEdgeCaseRegressionTests(OcwTestCase):
    """ラウンド1レビューで実測された異常系の回帰テスト（指摘5）。"""

    def test_missing_worktree_directory_does_not_leak_a_raw_git_fatal(self):
        create = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)

        worktree_dir = self.repo_root.parent / "widget-maker"
        (worktree_dir / "extra.txt").write_text("unmerged\n", encoding="utf-8")
        _git(["add", "extra.txt"], worktree_dir)
        _git(["commit", "-q", "-m", "unmerged commit"], worktree_dir)
        shutil.rmtree(worktree_dir)

        remove = run_ocw(["rm", "widget-maker"], self.repo_root)
        # Still correctly rejected (genuinely unmerged) -- a missing
        # directory must not be misread as "clean" and let through. The
        # warning must describe only what actually happened (the status
        # check was skipped), not promise a cleanup this same run then
        # doesn't perform (round-2 review finding: the die below means the
        # registration is NOT cleaned up here).
        self.assertNotEqual(remove.returncode, 0)
        self.assertIn("branch is not merged", remove.stderr)
        self.assertNotIn("fatal:", remove.stderr)
        self.assertIn("skipping the local-changes check", remove.stderr)

    def test_missing_worktree_directory_still_completes_removal_when_merged(self):
        create = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)

        worktree_dir = self.repo_root.parent / "widget-maker"
        shutil.rmtree(worktree_dir)

        remove = run_ocw(["rm", "widget-maker"], self.repo_root)
        self.assertEqual(remove.returncode, 0, remove.stderr)
        self.assertNotIn("fatal:", remove.stderr)
        branch_list = _git(["branch", "--list", "widget-maker"], self.repo_root).stdout
        self.assertNotIn("widget-maker", branch_list)


class OutcomeFromMergeDeterminationTests(OcwTestCase):
    """`run.end` の `outcome` がマージ判定の結果から決まること、`-f` の有無から
    決まるのではないこと (ADR DOC-2608062258 §3.8, 孫3 プロンプト §3)."""

    def test_squash_merged_force_remove_still_records_success_outcome(self):
        create = run_ocw(
            ["feature/foo"], self.repo_root, meter_on_path=True, meter_home=self.meter_home
        )
        self.assertEqual(create.returncode, 0, create.stderr)
        run_id = extract_run_id(create.stdout)

        worktree_dir = self.repo_root.parent / "feature" / "foo"
        (worktree_dir / "extra.txt").write_text("extra\n", encoding="utf-8")
        _git(["add", "extra.txt"], worktree_dir)
        _git(["commit", "-q", "-m", "extra commit"], worktree_dir)

        _git(["merge", "--squash", "feature/foo"], self.repo_root)
        _git(["commit", "-q", "-m", "squash merge feature/foo"], self.repo_root)

        # -f isn't required here (squash detection alone lets a plain `rm`
        # through), but this is the exact regression ADR §3.8 fixes: even
        # when -f *is* supplied, the outcome must follow the merge
        # determination, not -f's mere presence.
        remove = run_ocw(
            ["rm", "-f", "feature/foo"],
            self.repo_root,
            meter_on_path=True,
            meter_home=self.meter_home,
        )
        self.assertEqual(remove.returncode, 0, remove.stderr)

        events = read_events(self.meter_home)
        ends = [e for e in events if e["event_type"] == "run.end" and e["run_id"] == run_id]
        self.assertEqual(len(ends), 1, events)
        self.assertEqual(ends[0]["outcome"], "success")

    def test_truly_unmerged_force_remove_records_failure_outcome(self):
        create = run_ocw(
            ["widget-maker"], self.repo_root, meter_on_path=True, meter_home=self.meter_home
        )
        self.assertEqual(create.returncode, 0, create.stderr)
        run_id = extract_run_id(create.stdout)

        worktree_dir = self.repo_root.parent / "widget-maker"
        (worktree_dir / "extra.txt").write_text("unmerged\n", encoding="utf-8")
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


class EmptyDirectoryCleanupTests(OcwTestCase):
    """`ocw rm` 後の空ディレクトリ掃除 (ADR DOC-2608062258 §3.5, 孫3 プロンプト §4)."""

    def test_removing_last_nested_worktree_cleans_up_empty_parent(self):
        create = run_ocw(["feature/foo"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)

        feature_parent = self.repo_root.parent / "feature"
        self.assertTrue(feature_parent.is_dir())

        remove = run_ocw(["rm", "feature/foo"], self.repo_root)
        self.assertEqual(remove.returncode, 0, remove.stderr)
        self.assertFalse(feature_parent.exists())

    def test_sibling_nested_worktree_prevents_parent_cleanup(self):
        first = run_ocw(["feature/foo"], self.repo_root)
        self.assertEqual(first.returncode, 0, first.stderr)
        second = run_ocw(["feature/bar"], self.repo_root)
        self.assertEqual(second.returncode, 0, second.stderr)

        feature_parent = self.repo_root.parent / "feature"

        remove = run_ocw(["rm", "feature/foo"], self.repo_root)
        self.assertEqual(remove.returncode, 0, remove.stderr)
        self.assertFalse((feature_parent / "foo").exists())
        self.assertTrue(feature_parent.is_dir())
        self.assertTrue((feature_parent / "bar").is_dir())

    def test_cleanup_boundary_itself_is_never_removed(self):
        create = run_ocw(["widget-maker"], self.repo_root)
        self.assertEqual(create.returncode, 0, create.stderr)

        remove = run_ocw(["rm", "widget-maker"], self.repo_root)
        self.assertEqual(remove.returncode, 0, remove.stderr)
        # The cleanup boundary for the default template is repo_parent,
        # which also holds the still-live main worktree -- if cleanup ever
        # climbed past its own boundary this would delete it.
        self.assertTrue(self.repo_root.parent.is_dir())
        self.assertTrue(self.repo_root.is_dir())


class BareRepoMergeDeterminationTests(unittest.TestCase):
    """bare リポジトリでのマージ判定 (ADR DOC-2608062258 §3.7 候補3, 孫3 プロンプト §2)."""

    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        self.bare_dir = make_bare_repo(self.tmpdir.name)

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_rm_merge_check_works_from_bare_repo(self):
        create = run_ocw(["widget-maker"], self.bare_dir)
        self.assertEqual(create.returncode, 0, create.stderr)

        worktree_dir = self.bare_dir.parent / "widget-maker"
        _git(["config", "user.email", "test@example.invalid"], worktree_dir)
        _git(["config", "user.name", "Test"], worktree_dir)
        (worktree_dir / "extra.txt").write_text("extra\n", encoding="utf-8")
        _git(["add", "extra.txt"], worktree_dir)
        _git(["commit", "-q", "-m", "extra commit"], worktree_dir)

        # No working tree to run `git merge` in for a bare repo -- refs are
        # shared storage across all its linked worktrees, so fast-forwarding
        # main directly onto widget-maker's tip *is* "merging" it here.
        _git(["update-ref", "refs/heads/main", "refs/heads/widget-maker"], self.bare_dir)

        remove = run_ocw(["rm", "widget-maker"], self.bare_dir)
        self.assertEqual(remove.returncode, 0, remove.stderr)
        self.assertFalse(worktree_dir.exists())


if __name__ == "__main__":
    unittest.main()
