"""Tests for bin/ocw-meter.

These invoke the real executable as a subprocess (black-box) rather than
importing internals, because ocw-meter is a single deployable file (bash
skin + embedded python3), matching bin/ocw's style. Every test points
OCW_METER_HOME at a throwaway tempdir outside this repo, so nothing here
touches real state or the repo itself.

No network access. No secrets. See docs/planning/DOC-2608021229-a_..._計画.md §13
for the numbered test-case list (T01, T02, ...) this file implements.

Coverage of §13.2 across 孫1 + 孫3 + 孫4 (this file):

  implemented: T01 T02 T03 T04 T05 T06 T07 T08 T09 T10 T11
               T12 T13 T14 T16
               T17 T18 (regression guard) T19 T20 T21 T22
    T09 (孫4): SnapshotQuotaWindowTests / ReportFiveHourWindowCompletionTests
      — stale resets_at, same-window used_pct decrease, and the
      same-window PR-completion judgment in `report --pr`.
    T10 (孫4 half): SnapshotQuotaBasicsTests covers the rate_limits-
      absent (DeepSeek/claude-ds session) half; the usage-absence half
      was already covered by
      IngestTests.test_ingest_missing_usage_field_is_completeness_unknown,
      and the generic "missing required field -> quarantined" half by
      EventSchemaValidationTests.
    T11 (孫4 half): SnapshotQuotaBasicsTests covers the "known
      statusLine key disappears" half; the forward-compat "unknown
      field survives" half was already covered generically elsewhere.
  deferred, not implementable until a later phase exists to test:
    T15 - API error -> block.*/error_category is pr-review-loop
          instrumentation (孫2's scope, already covered there), not
          something `ingest` (a read-only transcript scanner) produces.

IngestTests below drives the real `ocw-meter ingest` subprocess against
synthetic transcript fixtures under a tempdir (OCW_METER_CLAUDE_PROJECTS_DIR),
not the developer's real ~/.claude/projects — nothing here reads real
transcripts. See docs/planning/DOC-2608021229-a_..._計画.md's 孫3プロンプト for the
completion criteria this maps to (idempotency, message.id dedup,
message.content non-exposure, cost formula, price-table versioning).
"""

import atexit
import concurrent.futures
import hashlib
import json
import os
import pathlib
import pty
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from datetime import datetime, timedelta, timezone

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
OCW_METER = REPO_ROOT / "bin" / "ocw-meter"

# ocw-meter's OWN fallback logic (emit_meter_error, the worktree-refusal
# suppression cache) derives paths from real $HOME whenever OCW_METER_HOME
# itself is refused (resolves inside a Git worktree) — not just from
# OCW_METER_HOME. A test that forgets to override $HOME too therefore
# silently writes into the developer's REAL ~/.local/state/ocw-meter
# whenever it exercises that path (found live on this machine — see
# docs/planning/DOC-2608081456_..._計画.md【4】: 37 stale worktree-refusal
# entries and 6 meter-error diagnostics, all test-shaped).
#
# run_meter/run_snapshot_quota default $HOME (whenever a caller doesn't
# explicitly pass its own via extra_env) to a directory keyed off `home`
# (the OCW_METER_HOME argument), under this ONE scratch root — not a
# single directory shared process-wide, and not a plain sibling of
# `home` either (孫1 round-1 review findings 7 and 9, plus a round-2
# fix for a bug the first attempt at finding 9 introduced):
#
# - **Independence** (finding 9): a single shared fallback directory let
#   one test's write silently satisfy another, unrelated test's
#   `idempotency_key`-deduped assertion (`emit_meter_error`'s dedup key
#   is `meter-error:<stage>:<YYYY-MM-DD>` — two tests hitting the same
#   stage on the same day only ever produce ONE line, written by
#   whichever ran first). Keying the fallback directory off `home`,
#   which is unique per call site in this file, means each test's own
#   write path is what actually gets exercised and asserted on.
# - **Cleanup** (finding 7): a single `atexit`-registered scratch root
#   covers every per-`home` subdirectory ever created, however many
#   distinct `home` values this file uses, instead of leaking one
#   never-cleaned directory per test run.
# - A first attempt at this made the fallback a plain SIBLING of `home`
#   (`<home>-home-env-fallback`) to piggyback on `self.tmpdir`'s own
#   cleanup. That breaks for exactly the tests worth having (the
#   worktree-refusal ones): when `home` sits inside a throwaway Git repo
#   (e.g. `repo_dir / "ocw-meter-home"`), a sibling of `home` sits
#   inside that SAME repo, so `default_storage_root()` built from it
#   resolves inside a Git worktree too — `emit_meter_error`'s own
#   `in_git_worktree(target_root)` guard then refuses to write the
#   diagnostic at all, silently defeating the very scenario under test.
#   Hashing `home` into a name under a fixed, git-free scratch root
#   sidesteps that entirely.
_HOME_FALLBACK_SCRATCH_ROOT = tempfile.mkdtemp(prefix="ocw-meter-test-home-fallbacks-")
atexit.register(shutil.rmtree, _HOME_FALLBACK_SCRATCH_ROOT, ignore_errors=True)


def _default_home_for(home):
    digest = hashlib.sha1(str(home).encode("utf-8")).hexdigest()[:16]
    return str(pathlib.Path(_HOME_FALLBACK_SCRATCH_ROOT) / digest)


def run_meter(args, home, extra_env=None, timeout=30, cwd=None):
    env = dict(os.environ)
    env["OCW_METER_HOME"] = str(home)
    # Isolate from whatever role/run/Herdr context this test happens to run
    # under, so assertions about "unset -> null" stay meaningful.
    for key in ("OCW_RUN_ID", "OCW_ROLE", "HERDR_WORKSPACE_ID", "HERDR_PANE_ID"):
        env.pop(key, None)
    if not extra_env or "HOME" not in extra_env:
        env["HOME"] = _default_home_for(home)
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        [str(OCW_METER), *args],
        cwd=str(cwd) if cwd is not None else str(REPO_ROOT),
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def run_snapshot_quota(stdin_text, home, extra_env=None, timeout=30):
    """Like run_meter, but feeds `stdin_text` to `ocw-meter snapshot-quota`
    on its own real stdin (via subprocess input=) — this is the one
    subcommand that reads real stdin data, not CLI flags."""
    env = dict(os.environ)
    env["OCW_METER_HOME"] = str(home)
    for key in ("OCW_RUN_ID", "OCW_ROLE", "HERDR_WORKSPACE_ID", "HERDR_PANE_ID"):
        env.pop(key, None)
    if not extra_env or "HOME" not in extra_env:
        env["HOME"] = _default_home_for(home)
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        [str(OCW_METER), "snapshot-quota"],
        cwd=str(REPO_ROOT),
        env=env,
        input=stdin_text,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def real_ocw_meter_home_contamination_fingerprint():
    """A NARROW fingerprint of the developer's REAL
    ~/.local/state/ocw-meter — deliberately NOT a full directory
    snapshot (孫1 round-1 review finding 5): Claude Code's own statusLine
    hook calls the real `ocw-meter snapshot-quota` roughly every 60s
    independently of this test run, touching
    events/YYYY-MM-DD.jsonl / state/quota-last-sample.json /
    state/seen-keys/YYYY-MM.txt on this developer's machine — legitimate
    activity a before/after full-tree equality check flags as a false
    positive. This instead looks only at what a HOME-isolation bug in
    THIS test file could plausibly cause: new test-shaped keys appearing
    in quota-worktree-refusal.json, or meter-errors.jsonl growing."""
    root = pathlib.Path(os.path.expanduser("~")) / ".local" / "state" / "ocw-meter"
    refusal_path = root / "state" / "quota-worktree-refusal.json"
    test_like_refusal_keys = set()
    if refusal_path.exists():
        try:
            data = json.loads(refusal_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            data = {}
        if isinstance(data, dict):
            test_like_refusal_keys = {k for k in data if "ocw-meter-home" in k}
    meter_errors_path = root / "state" / "meter-errors.jsonl"
    meter_errors_line_count = 0
    if meter_errors_path.exists():
        meter_errors_line_count = len(
            [line for line in meter_errors_path.read_text(encoding="utf-8").splitlines() if line.strip()]
        )
    return test_like_refusal_keys, meter_errors_line_count


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


def read_quarantine(home):
    lines = []
    qdir = pathlib.Path(home) / "quarantine"
    if not qdir.exists():
        return lines
    for path in sorted(qdir.glob("*.jsonl")):
        for line in path.read_text(encoding="utf-8").splitlines():
            if line.strip():
                lines.append(json.loads(line))
    return lines


def read_meter_errors(home):
    path = pathlib.Path(home) / "state" / "meter-errors.jsonl"
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


# ── ingest test helpers (孫3) ────────────────────────────────────────────

REPO_PRICE_DIR = REPO_ROOT / "bin" / "prices"


def assistant_line(session_id, message_id, *, model="deepseek-v4-pro", input_tokens=100,
                    cache_read_input_tokens=200, cache_creation_input_tokens=0, output_tokens=50,
                    stop_reason="end_turn", timestamp="2026-07-15T10:00:00.000Z",
                    git_branch="ai/test", cwd="/fixture/worktree", is_sidechain=False, effort="high",
                    usage=None):
    if usage is None:
        usage = {
            "input_tokens": input_tokens,
            "cache_read_input_tokens": cache_read_input_tokens,
            "cache_creation_input_tokens": cache_creation_input_tokens,
            "output_tokens": output_tokens,
            "service_tier": "standard",
        }
    return {
        "type": "assistant",
        "timestamp": timestamp,
        "sessionId": session_id,
        "version": "2.1.220",
        "gitBranch": git_branch,
        "cwd": cwd,
        "effort": effort,
        "isSidechain": is_sidechain,
        "message": {"id": message_id, "model": model, "stop_reason": stop_reason, "usage": usage},
    }


def write_transcript(projects_dir, slug, session_id, line_dicts):
    session_dir = pathlib.Path(projects_dir) / slug
    session_dir.mkdir(parents=True, exist_ok=True)
    path = session_dir / f"{session_id}.jsonl"
    path.write_text(
        "".join(json.dumps(d, ensure_ascii=False) + "\n" for d in line_dicts),
        encoding="utf-8",
    )
    return path


def write_price_table(price_dir, filename, table):
    price_dir = pathlib.Path(price_dir)
    price_dir.mkdir(parents=True, exist_ok=True)
    (price_dir / filename).write_text(json.dumps(table, ensure_ascii=False), encoding="utf-8")


def make_ocw_style_worktree(tmp_root, run_id):
    """Creates a throwaway git repo + linked worktree and writes
    `run_id` to `<worktree's git-dir>/ocw-run-id`, mirroring bin/ocw's
    OWN persistence exactly (`git -C "$worktree_dir" rev-parse
    --absolute-git-dir` then `printf '%s\\n' "$run_id" >"$git_dir/
    ocw-run-id"` — see bin/ocw around the `generate_run_id` call site).
    Returns the worktree's absolute path, for use as an assistant
    line's `cwd`."""
    counter = getattr(make_ocw_style_worktree, "_counter", 0) + 1
    make_ocw_style_worktree._counter = counter
    repo_dir = pathlib.Path(tmp_root) / f"ocw-repo-{counter}"
    worktree_dir = pathlib.Path(tmp_root) / f"ocw-worktree-{counter}"
    repo_dir.mkdir()
    subprocess.run(["git", "init", "-q", str(repo_dir)], check=True)
    subprocess.run(["git", "-C", str(repo_dir), "config", "user.email", "test@example.com"], check=True)
    subprocess.run(["git", "-C", str(repo_dir), "config", "user.name", "test"], check=True)
    (repo_dir / "README.md").write_text("x", encoding="utf-8")
    subprocess.run(["git", "-C", str(repo_dir), "add", "."], check=True)
    subprocess.run(["git", "-C", str(repo_dir), "commit", "-q", "-m", "init"], check=True)
    subprocess.run(
        ["git", "-C", str(repo_dir), "worktree", "add", "-q", "-b", f"feature-{counter}", str(worktree_dir)],
        check=True,
    )
    git_dir = subprocess.run(
        ["git", "-C", str(worktree_dir), "rev-parse", "--absolute-git-dir"],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    (pathlib.Path(git_dir) / "ocw-run-id").write_text(run_id + "\n", encoding="utf-8")
    return worktree_dir


def run_ingest(home, projects_dir, args=None, price_dir=None, extra_env=None, timeout=60):
    env = {
        "OCW_METER_CLAUDE_PROJECTS_DIR": str(projects_dir),
        "OCW_METER_PRICE_DIR": str(price_dir if price_dir is not None else REPO_PRICE_DIR),
        "OCW_METER_INGEST_USE_GH": "0",
    }
    if extra_env:
        env.update(extra_env)
    return run_meter(["ingest", *(args or [])], home, extra_env=env, timeout=timeout)


def run_report(home, projects_dir=None, args=None, price_dir=None, extra_env=None, timeout=60):
    """Like `run_ingest`, but drives `report` (whose automatic ingest —
    計画書 DOC-2608081456孫2 — is what most callers of this helper mean
    to exercise) instead of `ingest` directly."""
    env = {
        "OCW_METER_PRICE_DIR": str(price_dir if price_dir is not None else REPO_PRICE_DIR),
        "OCW_METER_INGEST_USE_GH": "0",
    }
    if projects_dir is not None:
        env["OCW_METER_CLAUDE_PROJECTS_DIR"] = str(projects_dir)
    if extra_env:
        env.update(extra_env)
    return run_meter(["report", *(args or [])], home, extra_env=env, timeout=timeout)


class OcwMeterTestCase(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        # tempfile defaults to the system tmpdir, which is never inside
        # this (or any) git worktree — required, since ocw-meter refuses
        # to operate on a storage root that is.
        self.home = pathlib.Path(self.tmpdir.name) / "ocw-meter-home"

    def tearDown(self):
        self.tmpdir.cleanup()


class HelpAndDispatchTests(OcwMeterTestCase):
    def test_help_exits_zero(self):
        result = run_meter(["help"], self.home)
        self.assertEqual(result.returncode, 0)
        self.assertIn("ocw-meter event", result.stdout)

    def test_no_subcommand_exits_nonzero(self):
        result = run_meter([], self.home)
        self.assertNotEqual(result.returncode, 0)

    def test_unknown_subcommand_exits_nonzero(self):
        result = run_meter(["frobnicate"], self.home)
        self.assertNotEqual(result.returncode, 0)


class EventBasicsTests(OcwMeterTestCase):
    def test_event_writes_one_line_with_full_envelope(self):
        result = run_meter(
            ["event", "run.start", "--idempotency-key", "k1", "--source", "ocw", "--base-ref", "origin/main", "--command", "claude"],
            self.home,
        )
        self.assertEqual(result.returncode, 0)
        # Success is silent on stdout: `event`/`bind-pr` are meant to be
        # embedded in other tools' output (ocw, pr-review-loop) behind a
        # `command -v ocw-meter && ocw-meter event ... || true` guard that
        # does not redirect stdout, so printing on success would corrupt
        # the caller's own terminal output.
        self.assertEqual(result.stdout, "")

        events = read_events(self.home)
        self.assertEqual(len(events), 1)
        event = events[0]
        self.assertEqual(event["event_type"], "run.start")
        self.assertEqual(event["schema_version"], 1)
        self.assertEqual(event["idempotency_key"], "k1")
        self.assertEqual(event["source"], "ocw")
        self.assertEqual(event["completeness"], "complete")
        # role/source are non-null "unknown" sentinels per plan §8.1, not
        # None, when nothing resolves them.
        self.assertEqual(event["role"], "unknown")
        # Fields nobody supplied a value for must be present and null,
        # never silently missing (T10-style robustness at envelope level).
        for field in ("session_id", "provider", "model", "phase", "round", "pr_number", "pr_url"):
            self.assertIn(field, event)
            self.assertIsNone(event[field])

    def test_role_and_source_default_to_unknown_not_null(self):
        result = run_meter(["event", "human.intervention", "--idempotency-key", "k1", "--reason", "test"], self.home)
        self.assertEqual(result.returncode, 0)
        event = read_events(self.home)[0]
        self.assertEqual(event["role"], "unknown")
        self.assertEqual(event["source"], "unknown")

    def test_event_requires_event_type_but_still_exits_zero(self):
        result = run_meter(["event"], self.home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(read_events(self.home), [])

    def test_unknown_flags_are_flattened_as_extra_fields(self):
        # T11 (forward-compat half): a caller-supplied field this schema
        # version doesn't know about must survive, not be dropped.
        result = run_meter(
            ["event", "run.start", "--idempotency-key", "k1", "--base-ref", "origin/main", "--command", "claude"],
            self.home,
        )
        self.assertEqual(result.returncode, 0)
        events = read_events(self.home)
        self.assertEqual(events[0]["base_ref"], "origin/main")
        self.assertEqual(events[0]["command"], "claude")

    def test_storage_permissions_are_locked_down(self):
        run_meter(["event", "run.start", "--idempotency-key", "k1"], self.home)
        home_mode = stat.S_IMODE(os.stat(self.home).st_mode)
        events_dir_mode = stat.S_IMODE(os.stat(self.home / "events").st_mode)
        self.assertEqual(home_mode, 0o700)
        self.assertEqual(events_dir_mode, 0o700)
        event_files = list((self.home / "events").glob("*.jsonl"))
        self.assertEqual(len(event_files), 1)
        self.assertEqual(stat.S_IMODE(os.stat(event_files[0]).st_mode), 0o600)


class DedupTests(OcwMeterTestCase):
    def test_duplicate_idempotency_key_counts_once(self):
        # T03
        for _ in range(2):
            result = run_meter(["event", "phase.start", "--idempotency-key", "dup-1"], self.home)
            self.assertEqual(result.returncode, 0)
        events = read_events(self.home)
        self.assertEqual(len(events), 1)

    def test_duplicate_message_id_style_key_dedupes(self):
        # T04: the real ingest phase (a later PR) will key usage.message
        # events as "msg:<message.id>" specifically because a single
        # response is re-recorded across multiple transcript lines.
        # Verify the core dedup primitive that guarantee rests on.
        run_meter(["event", "usage.message", "--idempotency-key", "msg:abc123", "--model", "deepseek-v4-pro"], self.home)
        run_meter(["event", "usage.message", "--idempotency-key", "msg:abc123", "--model", "deepseek-v4-pro"], self.home)
        events = read_events(self.home)
        self.assertEqual(len(events), 1)

    def test_different_keys_both_kept(self):
        run_meter(["event", "phase.start", "--idempotency-key", "k1"], self.home)
        run_meter(["event", "phase.start", "--idempotency-key", "k2"], self.home)
        self.assertEqual(len(read_events(self.home)), 2)


class BindPrTests(OcwMeterTestCase):
    def test_bind_pr_writes_pr_bind_event(self):
        result = run_meter(["bind-pr", "--run", "run-1", "--pr", "42", "--url", "https://example.invalid/pull/42"], self.home)
        self.assertEqual(result.returncode, 0)
        events = read_events(self.home)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["event_type"], "pr.bind")
        self.assertEqual(events[0]["run_id"], "run-1")
        self.assertEqual(events[0]["pr_number"], 42)

    def test_bind_pr_missing_args_writes_nothing_but_exits_zero(self):
        result = run_meter(["bind-pr", "--run", "run-1"], self.home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(read_events(self.home), [])

    def test_bind_pr_is_idempotent_for_same_run_and_pr(self):
        run_meter(["bind-pr", "--run", "run-1", "--pr", "42"], self.home)
        run_meter(["bind-pr", "--run", "run-1", "--pr", "42"], self.home)
        self.assertEqual(len(read_events(self.home)), 1)

    def test_report_resolves_pr_via_bound_run_id(self):
        # T07: a PR doesn't exist yet when a run starts; bind-pr arrives
        # later. `report --pr N` must still surface the earlier events
        # once the bind exists, via the shared run_id (plan §7.4).
        run_meter(["event", "phase.start", "--idempotency-key", "e1", "--run-id", "run-7", "--phase", "implement"], self.home)
        run_meter(
            ["event", "phase.end", "--idempotency-key", "e2", "--run-id", "run-7", "--phase", "implement", "--outcome", "success", "--duration-ms", "1000"],
            self.home,
        )
        result = run_meter(["report", "--pr", "99", "--json"], self.home)
        self.assertEqual(result.returncode, 0)
        summary = json.loads(result.stdout)
        self.assertEqual(summary["total_events"], 0)

        run_meter(["bind-pr", "--run", "run-7", "--pr", "99"], self.home)
        result = run_meter(["report", "--pr", "99", "--json"], self.home)
        summary = json.loads(result.stdout)
        # 2 phase events + the pr.bind event itself.
        self.assertEqual(summary["total_events"], 3)


class ValidateTests(OcwMeterTestCase):
    def _write_raw(self, filename, content):
        events_dir = self.home / "events"
        events_dir.mkdir(parents=True, exist_ok=True)
        path = events_dir / filename
        path.write_text(content, encoding="utf-8")
        return path

    def test_missing_required_fields_are_quarantined(self):
        # T01
        good = json.dumps({"schema_version": 1, "event_id": "e1", "event_type": "human.intervention", "idempotency_key": "k1", "ts": "2026-08-01T00:00:00.000Z", "reason": "test"})
        bad = json.dumps({"schema_version": 1, "event_id": "e2", "idempotency_key": "k2", "ts": "2026-08-01T00:00:00.000Z"})  # missing event_type
        self._write_raw("2026-08-01.jsonl", good + "\n" + bad + "\n")

        result = run_meter(["validate"], self.home)
        self.assertEqual(result.returncode, 0)

        remaining = (self.home / "events" / "2026-08-01.jsonl").read_text().splitlines()
        self.assertEqual(len(remaining), 1)
        self.assertEqual(json.loads(remaining[0])["event_id"], "e1")

        quarantined = read_quarantine(self.home)
        self.assertEqual(len(quarantined), 1)
        self.assertIn("event_type", quarantined[0]["reason"])

    def test_malformed_json_line_is_quarantined(self):
        # T02
        good = json.dumps({"schema_version": 1, "event_id": "e1", "event_type": "human.intervention", "idempotency_key": "k1", "ts": "2026-08-01T00:00:00.000Z", "reason": "test"})
        self._write_raw("2026-08-01.jsonl", good + "\nthis is not json\n")

        result = run_meter(["validate"], self.home)
        self.assertEqual(result.returncode, 0)

        remaining = (self.home / "events" / "2026-08-01.jsonl").read_text().splitlines()
        self.assertEqual(len(remaining), 1)
        quarantined = read_quarantine(self.home)
        self.assertEqual(len(quarantined), 1)
        self.assertEqual(quarantined[0]["raw_line"], "this is not json")

    def test_truncated_final_line_is_treated_as_crash_and_quarantined(self):
        # T05: earlier good lines must survive; only the truncated tail
        # goes to quarantine.
        good = json.dumps({"schema_version": 1, "event_id": "e1", "event_type": "human.intervention", "idempotency_key": "k1", "ts": "2026-08-01T00:00:00.000Z", "reason": "test"})
        truncated = '{"schema_version": 1, "event_id": "e2", "idempotency_key": "k2"'  # cut off mid-write, no trailing newline
        self._write_raw("2026-08-01.jsonl", good + "\n" + truncated)

        result = run_meter(["validate"], self.home)
        self.assertEqual(result.returncode, 0)

        remaining = (self.home / "events" / "2026-08-01.jsonl").read_text().splitlines()
        self.assertEqual(len(remaining), 1)
        self.assertEqual(json.loads(remaining[0])["event_id"], "e1")

        quarantined = read_quarantine(self.home)
        self.assertEqual(len(quarantined), 1)
        self.assertIn("crash", quarantined[0]["reason"])

    def test_validate_on_clean_data_is_a_noop(self):
        result = run_meter(["event", "run.start", "--idempotency-key", "k1", "--base-ref", "origin/main", "--command", "claude"], self.home)
        self.assertEqual(result.returncode, 0)
        result = run_meter(["validate"], self.home)
        self.assertEqual(result.returncode, 0)
        self.assertIn("lines quarantined: 0", result.stdout)
        self.assertEqual(len(read_events(self.home)), 1)


class ReportTests(OcwMeterTestCase):
    def test_report_on_empty_storage_does_not_fail(self):
        # T20
        result = run_meter(["report"], self.home)
        self.assertEqual(result.returncode, 0)
        self.assertIn("total events:  0", result.stdout)
        self.assertIn("coverage:", result.stdout)
        self.assertIn("quarantined:", result.stdout)

    def test_report_json_is_valid_and_has_required_footer_fields(self):
        run_meter(["event", "run.start", "--idempotency-key", "k1"], self.home)
        result = run_meter(["report", "--json"], self.home)
        self.assertEqual(result.returncode, 0)
        summary = json.loads(result.stdout)
        for field in ("total_events", "completeness", "quarantined_lines", "coverage", "price_table", "cost_basis"):
            self.assertIn(field, summary)


class SecretRedactionTests(OcwMeterTestCase):
    def test_api_key_like_values_are_redacted(self):
        # T17
        result = run_meter(
            [
                "event", "meter.error",
                "--idempotency-key", "k1",
                "--api-key", "sk-abcdefghijklmnopqrstuvwx",
                "--note", "Authorization: Bearer some-secret-value",
            ],
            self.home,
        )
        self.assertEqual(result.returncode, 0)
        events = read_events(self.home)
        raw = json.dumps(events[0])
        self.assertNotIn("sk-abcdefghijklmnopqrstuvwx", raw)
        self.assertNotIn("some-secret-value", raw)
        self.assertEqual(events[0]["api_key"], "[REDACTED]")

    def test_short_sk_prefixed_value_is_redacted(self):
        # Round-1 review: the original pattern required 10+ chars after
        # "sk-", so short keys like this slipped through unredacted.
        result = run_meter(
            ["event", "meter.error", "--idempotency-key", "k2", "--stage", "test", "--note", "key=sk-abc123"],
            self.home,
        )
        self.assertEqual(result.returncode, 0)
        raw = json.dumps(read_events(self.home)[-1])
        self.assertNotIn("sk-abc123", raw)

    def test_github_token_shaped_value_is_redacted(self):
        result = run_meter(
            ["event", "meter.error", "--idempotency-key", "k3", "--stage", "test", "--note", "github ghp_AbCdEf1234567890abcdef"],
            self.home,
        )
        self.assertEqual(result.returncode, 0)
        raw = json.dumps(read_events(self.home)[-1])
        self.assertNotIn("ghp_AbCdEf1234567890abcdef", raw)

    def test_token_count_fields_are_not_redacted(self):
        # Round-2 review, most severe finding: SECRET_KEY_RE's old
        # substring match on "token" caught input_tokens/output_tokens/
        # cache_*_tokens/reasoning_tokens — exactly the numbers this
        # whole project exists to measure.
        result = run_meter(
            [
                "event", "usage.message", "--idempotency-key", "u1", "--message-id", "msg_x",
                "--input-tokens", "4617", "--output-tokens", "329",
                "--cache-read-input-tokens", "27264", "--cache-creation-input-tokens", "0",
                "--reasoning-tokens", "12", "--cost-basis", "estimated",
            ],
            self.home,
        )
        self.assertEqual(result.returncode, 0)
        # Round-3 review: these must be real numbers (plan §8.4's cost
        # formula does arithmetic on them), not strings.
        event = read_events(self.home)[-1]
        self.assertEqual(event["input_tokens"], 4617)
        self.assertEqual(event["output_tokens"], 329)
        self.assertEqual(event["cache_read_input_tokens"], 27264)
        self.assertEqual(event["cache_creation_input_tokens"], 0)
        self.assertEqual(event["reasoning_tokens"], 12)

    def test_sk_pattern_does_not_match_mid_word(self):
        # Round-2 review: the un-anchored "sk-" pattern matched inside
        # ordinary words like "task-force" / "risk-assessment", and
        # `branch` is captured automatically from `git` — `ocw` names
        # branches `ai/<slug>` (plan §3.1), so `ocw task-foo` is a
        # realistic branch name this must not corrupt.
        result = run_meter(
            ["event", "run.start", "--idempotency-key", "u2", "--base-ref", "ai/task-force", "--command", "npm run task-build"],
            self.home,
        )
        self.assertEqual(result.returncode, 0)
        event = read_events(self.home)[-1]
        self.assertEqual(event["base_ref"], "ai/task-force")
        self.assertEqual(event["command"], "npm run task-build")


class ReadOnlyStorageTests(OcwMeterTestCase):
    def test_event_exits_zero_when_storage_cannot_be_created(self):
        # T19
        parent = pathlib.Path(self.tmpdir.name) / "ro-parent"
        parent.mkdir()
        os.chmod(parent, 0o500)
        try:
            result = run_meter(["event", "run.start", "--idempotency-key", "k1"], parent / "ocw-meter-home")
            self.assertEqual(result.returncode, 0)
        finally:
            os.chmod(parent, 0o700)


class GitWorktreeGuardTests(unittest.TestCase):
    def test_event_refuses_write_inside_repo_but_still_exits_zero(self):
        # T22 (fail-open side): the safety property is "never write into
        # the repo", not "return non-zero" — event's contract is always
        # exit 0, so the guard must manifest as a silent no-write here.
        #
        # Round-2 review: this test must also override HOME to a
        # throwaway tempdir. The refusal's meter.error self-diagnostic
        # falls back to $HOME/.local/state/ocw-meter (see
        # MeterErrorSelfDiagnosticTests) — without overriding HOME here,
        # every run of this test suite was writing a real event into the
        # developer's actual, non-test ocw-meter storage.
        home = REPO_ROOT / "tmp-test-ocw-meter-worktree-guard"
        fake_home = tempfile.mkdtemp()
        self.assertFalse(home.exists())
        try:
            result = run_meter(["event", "run.start", "--idempotency-key", "k1"], home, extra_env={"HOME": fake_home})
            self.assertEqual(result.returncode, 0)
            self.assertFalse(home.exists())
            # And it actually did land somewhere traceable (not just "no
            # real storage touched, no diagnostic either").
            fallback_diagnostics = read_meter_errors(pathlib.Path(fake_home) / ".local" / "state" / "ocw-meter")
            self.assertEqual(len(fallback_diagnostics), 1)
            self.assertEqual(fallback_diagnostics[0]["event_type"], "meter.error")
        finally:
            if home.exists():
                import shutil

                shutil.rmtree(home)
            import shutil as _shutil

            _shutil.rmtree(fake_home, ignore_errors=True)

    def test_validate_and_report_fail_loud_inside_repo(self):
        # T22 (fail-loud side): validate/report must not silently pretend
        # a misconfigured (in-repo) storage root is fine.
        home = REPO_ROOT / "tmp-test-ocw-meter-worktree-guard-2"
        self.assertFalse(home.exists())
        try:
            result = run_meter(["validate"], home)
            self.assertNotEqual(result.returncode, 0)
            result = run_meter(["report"], home)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(home.exists())
        finally:
            if home.exists():
                import shutil

                shutil.rmtree(home)


class TimezoneBucketingTests(OcwMeterTestCase):
    def test_events_are_bucketed_by_utc_date_not_local_date(self):
        # T21: 23:30 UTC and 00:30 UTC the next day must land in two
        # different daily files even though a JST reader (+9h) would see
        # both as "the same local morning".
        run_meter(["event", "run.start", "--idempotency-key", "k-late", "--ts", "2026-08-01T23:30:00.000Z"], self.home)
        run_meter(["event", "run.start", "--idempotency-key", "k-early", "--ts", "2026-08-02T00:30:00.000Z"], self.home)
        events_dir = self.home / "events"
        self.assertTrue((events_dir / "2026-08-01.jsonl").exists())
        self.assertTrue((events_dir / "2026-08-02.jsonl").exists())


class ConcurrencyTests(OcwMeterTestCase):
    def test_twenty_concurrent_writers_no_loss_or_corruption(self):
        # T06
        n = 20

        def worker(i):
            return run_meter(["event", "test.concurrent", "--idempotency-key", f"conc-{i}"], self.home)

        with concurrent.futures.ThreadPoolExecutor(max_workers=n) as pool:
            results = list(pool.map(worker, range(n)))

        for result in results:
            self.assertEqual(result.returncode, 0)

        events = read_events(self.home)
        self.assertEqual(len(events), n)
        keys = {e["idempotency_key"] for e in events}
        self.assertEqual(len(keys), n)


class HomeUnsetTests(unittest.TestCase):
    """`set -u` under bash means expanding an unset $HOME while computing
    the default OCW_METER_HOME kills the process before python is ever
    reached — the one gap in the "event always exits 0" contract found in
    round 1 review. Exercise it with both HOME and OCW_METER_HOME unset."""

    def _run_without_home(self, args):
        env = dict(os.environ)
        env.pop("HOME", None)
        env.pop("OCW_METER_HOME", None)
        return subprocess.run(
            [str(OCW_METER), *args],
            cwd=str(REPO_ROOT),
            env=env,
            capture_output=True,
            text=True,
            timeout=10,
        )

    def test_event_still_exits_zero_with_home_and_ocw_meter_home_unset(self):
        result = self._run_without_home(["event", "run.start", "--idempotency-key", "k1"])
        self.assertEqual(result.returncode, 0)

    def test_bind_pr_still_exits_zero_with_home_and_ocw_meter_home_unset(self):
        result = self._run_without_home(["bind-pr", "--run", "r1", "--pr", "1"])
        self.assertEqual(result.returncode, 0)

    def test_validate_fails_loud_with_home_and_ocw_meter_home_unset(self):
        result = self._run_without_home(["validate"])
        self.assertNotEqual(result.returncode, 0)

    def test_report_fails_loud_with_home_and_ocw_meter_home_unset(self):
        result = self._run_without_home(["report"])
        self.assertNotEqual(result.returncode, 0)


class ValidateFileScopeTests(OcwMeterTestCase):
    def test_validate_file_flag_refuses_a_path_outside_the_events_dir(self):
        # A `--file` pointing anywhere other than inside OCW_METER_HOME's
        # own events/ directory must be refused outright, not silently
        # rewritten down to only its "good" JSONL lines (which, for an
        # arbitrary non-JSONL file, is all of them -> total data loss).
        victim = pathlib.Path(self.tmpdir.name) / "victim.txt"
        original = "important line 1\nimportant line 2\nimportant line 3\n"
        victim.write_text(original, encoding="utf-8")

        result = run_meter(["validate", "--file", str(victim)], self.home)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(victim.read_text(encoding="utf-8"), original)


class QuarantineSeenKeysCleanupTests(OcwMeterTestCase):
    def test_quarantine_frees_idempotency_key_for_a_corrected_resend(self):
        # #3: a bad value (non-integer round) gets written, then
        # quarantined by `validate` — the seen-keys entry it left behind
        # must not permanently block a corrected resend under the same
        # idempotency_key.
        run_meter(
            ["event", "review.round", "--idempotency-key", "rk1", "--round", "abc", "--verdict", "approved", "--findings-count", "0"],
            self.home,
        )
        run_meter(["validate"], self.home)
        self.assertEqual(read_events(self.home), [])  # quarantined; nothing valid survives

        result = run_meter(
            ["event", "review.round", "--idempotency-key", "rk1", "--round", "1", "--verdict", "approved", "--findings-count", "0"],
            self.home,
        )
        self.assertEqual(result.returncode, 0)
        events = read_events(self.home)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["round"], 1)

    def test_invalid_round_downgrades_completeness_at_write_time(self):
        # Don't wait for someone to run `validate` to notice a type
        # mismatch — flag it the moment it happens.
        run_meter(
            ["event", "review.round", "--idempotency-key", "rk2", "--round", "not-a-number", "--verdict", "approved", "--findings-count", "0"],
            self.home,
        )
        events = read_events(self.home)
        self.assertEqual(events[0]["completeness"], "partial")

    def test_non_numeric_payload_field_is_quarantined_like_round_or_pr_number(self):
        # Round-3 review: a *present* value of the wrong type in a known
        # numeric payload field (findings_count here) is corruption, not
        # absence — same hard/quarantine treatment as round/pr_number,
        # not the soft downgrade payload_shape_issues gives to missing
        # fields.
        run_meter(
            ["event", "review.round", "--idempotency-key", "rk3", "--round", "1", "--verdict", "approved", "--findings-count", "not-a-number"],
            self.home,
        )
        run_meter(["validate"], self.home)
        self.assertEqual(read_events(self.home), [])
        quarantined = read_quarantine(self.home)
        self.assertEqual(len(quarantined), 1)
        self.assertIn("findings_count", quarantined[0]["reason"])


class ReplaceTrailingNewlineTests(OcwMeterTestCase):
    def test_replace_preserves_a_crash_truncated_final_line(self):
        # Round-3 review: last-write-wins rewrites the day's file via
        # `_replace_line_by_idempotency_key`. If that rewrite always
        # terminates every line with "\n", it silently "heals" a
        # crash-truncated final line (the only signal `validate_file`
        # has for T05) the next time ANY OTHER key in the same file
        # happens to get replaced.
        run_meter(["event", "phase.start", "--idempotency-key", "k1", "--phase", "implement"], self.home)

        events_dir = self.home / "events"
        today = sorted(events_dir.glob("*.jsonl"))[0]
        with open(today, "a", encoding="utf-8") as fh:
            fh.write('{"schema_version": 1, "event_id": "crashed", "idempotency_key": "crashed-key"')  # no closing brace, no newline

        # Trigger a replace on the *other* (complete) key, not the
        # crashed one.
        result = run_meter(["event", "phase.start", "--idempotency-key", "k1", "--phase", "implement", "--note", "resend"], self.home)
        self.assertEqual(result.returncode, 0)

        result = run_meter(["validate"], self.home)
        self.assertEqual(result.returncode, 0)
        quarantined = read_quarantine(self.home)
        self.assertEqual(len(quarantined), 1)
        self.assertIn("crash", quarantined[0]["reason"])


class ExceptionMessageRedactionTests(OcwMeterTestCase):
    def test_event_error_message_does_not_leak_secret_shaped_positional_arg(self):
        result = run_meter(["event", "run.start", "sk-live-ABCDEFG1234567890"], self.home)
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("sk-live-ABCDEFG1234567890", result.stderr)

    def test_bind_pr_error_message_does_not_leak_secret_shaped_pr_value(self):
        result = run_meter(["bind-pr", "--run", "r1", "--pr", "sk-secret-value-123456"], self.home)
        self.assertEqual(result.returncode, 0)
        self.assertNotIn("sk-secret-value-123456", result.stderr)


class EventSchemaValidationTests(OcwMeterTestCase):
    def _write_and_validate(self, event_type, extra_flags, idempotency_key="k1"):
        run_meter(["event", event_type, "--idempotency-key", idempotency_key, *extra_flags], self.home)
        run_meter(["validate"], self.home)
        return read_events(self.home), read_quarantine(self.home)

    def test_known_type_missing_required_payload_field_is_downgraded_not_deleted(self):
        # Round-2 review: a payload shape issue is advisory, not
        # corruption (plan §10.2 says to keep a best-effort record, not
        # discard it) — it downgrades completeness in place and is
        # NEVER quarantined/removed.
        events, quarantined = self._write_and_validate("run.start", ["--base-ref", "origin/main"])  # missing --command
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["completeness"], "partial")
        self.assertEqual(quarantined, [])

    def test_known_type_enum_violation_is_downgraded_not_deleted(self):
        events, quarantined = self._write_and_validate(
            "phase.end",
            ["--phase", "implement", "--outcome", "not-a-real-outcome"],
        )
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["completeness"], "partial")
        self.assertEqual(quarantined, [])

    def test_explicit_null_payload_field_is_not_treated_as_missing(self):
        # Round-2 review: an explicitly-recorded empty/null value (the
        # caller tried and confirmed the field is unavailable, e.g. a
        # DeepSeek session with no rate_limits — DOC-2608021229 §2.1) must NOT
        # be treated the same as the field never appearing at all.
        events, quarantined = self._write_and_validate(
            "quota.sample",
            ["--source", "statusline", "--plan-source", "statusline", "--five-hour-used-pct", ""],
        )
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["completeness"], "complete")
        # Round-3 review: "" must become a real JSON null, not survive as
        # an empty string — a CLI flag can't carry `null` directly, so ""
        # is how a caller spells it, but the *stored* value must be null.
        self.assertIsNone(events[0]["five_hour_used_pct"])
        self.assertEqual(quarantined, [])

    def test_best_effort_event_missing_advisory_field_stays_complete(self):
        # block.end's wait_ms and phase.end's outcome/duration_ms are
        # advisory (plan §8.2 "best-effort"), not required — omitting
        # them entirely must not downgrade completeness either.
        events, quarantined = self._write_and_validate("block.end", ["--cause", "rate_limit"])
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["completeness"], "complete")
        self.assertEqual(quarantined, [])

    def test_required_payload_field_present_but_null_is_also_downgraded(self):
        # Round-4 review: an unset shell variable passed through as
        # `--phase ""` (e.g. `ocw-meter event phase.start --phase
        # "$PHASE"` with $PHASE empty) makes the *required* `phase` key
        # present-but-null. That must downgrade completeness exactly
        # like the field being absent entirely — "complete" would be a
        # lie either way (plan §10.4).
        events, quarantined = self._write_and_validate("phase.start", ["--phase", ""])
        self.assertEqual(len(events), 1)
        self.assertIsNone(events[0]["phase"])
        self.assertEqual(events[0]["completeness"], "partial")
        self.assertEqual(quarantined, [])

    def test_unknown_event_type_is_forward_compatible_not_quarantined(self):
        # A future event_type this binary has never heard of must not be
        # treated as invalid — only *known* types get payload checks.
        events, quarantined = self._write_and_validate("future.event.type.not.yet.defined", ["--whatever", "value"])
        self.assertEqual(len(events), 1)
        self.assertEqual(quarantined, [])

    def test_bogus_completeness_value_is_quarantined(self):
        events, quarantined = self._write_and_validate("human.intervention", ["--reason", "test", "--completeness", "bogus"])
        self.assertEqual(events, [])
        self.assertEqual(len(quarantined), 1)
        self.assertIn("completeness", quarantined[0]["reason"])

    def test_bogus_source_value_is_quarantined(self):
        events, quarantined = self._write_and_validate("human.intervention", ["--reason", "test", "--source", "not-a-real-source"])
        self.assertEqual(events, [])
        self.assertEqual(len(quarantined), 1)
        self.assertIn("source", quarantined[0]["reason"])


class MeterErrorSelfDiagnosticTests(unittest.TestCase):
    def test_worktree_refusal_leaves_a_meter_error_trace_in_the_default_root(self):
        # #8: a misconfigured OCW_METER_HOME (pointing inside a Git
        # worktree) must not vanish without a trace. We refuse to write
        # into the misconfigured path itself, so the best-effort
        # meter.error instead lands in the *default* storage root under a
        # throwaway $HOME.
        fake_home = tempfile.mkdtemp()
        bad_target = REPO_ROOT / "tmp-test-ocw-meter-worktree-guard-diag"
        try:
            env = dict(os.environ)
            env["HOME"] = fake_home
            env["OCW_METER_HOME"] = str(bad_target)
            for key in ("OCW_RUN_ID", "OCW_ROLE", "HERDR_WORKSPACE_ID", "HERDR_PANE_ID"):
                env.pop(key, None)

            result = subprocess.run(
                [str(OCW_METER), "event", "run.start", "--idempotency-key", "k1"],
                cwd=str(REPO_ROOT),
                env=env,
                capture_output=True,
                text=True,
                timeout=10,
            )
            self.assertEqual(result.returncode, 0)
            self.assertFalse(bad_target.exists())
            # Round-2 review: the user must be told their configured
            # OCW_METER_HOME is being ignored, not just have data quietly
            # reappear somewhere else.
            self.assertIn("misconfigured", result.stderr)

            # Round-4 review: meter.error diagnostics live in their own
            # state/meter-errors.jsonl, not events/*.jsonl (that file is
            # reserved for observation events; keeping diagnostics out of
            # it is what lets emit_meter_error stay lock-free).
            default_root = pathlib.Path(fake_home) / ".local" / "state" / "ocw-meter"
            self.assertEqual(read_events(default_root), [])
            diagnostics = read_meter_errors(default_root)
            self.assertEqual(len(diagnostics), 1)
            self.assertEqual(diagnostics[0]["event_type"], "meter.error")
            self.assertEqual(diagnostics[0]["completeness"], "unknown")
            self.assertEqual(diagnostics[0]["stage"], "storage_home_inside_git_worktree")

            # Round-5 review: emit_meter_error may be the very first thing
            # to ever create this root (nothing else has run yet), so it
            # must chmod the root itself, not just state_dir — otherwise
            # the root sits at umask-default 755 until something else
            # happens to call ensure_storage.
            self.assertEqual(stat.S_IMODE(os.stat(default_root).st_mode), 0o700)

            # Round-2 review: a persistent misconfiguration must not grow
            # this file without bound — a second failure on the same day
            # must not add a second line.
            subprocess.run(
                [str(OCW_METER), "event", "run.start", "--idempotency-key", "k2"],
                cwd=str(REPO_ROOT), env=env, capture_output=True, text=True, timeout=10,
            )
            self.assertEqual(len(read_meter_errors(default_root)), 1)
        finally:
            import shutil

            shutil.rmtree(fake_home, ignore_errors=True)
            if bad_target.exists():
                shutil.rmtree(bad_target)

    def test_lock_contention_still_records_a_diagnostic(self):
        # Round-4 review: this is exactly the scenario round-3's fix
        # broke — write_event's own lock-timeout path calling
        # emit_meter_error, which used to need the *same* lock and would
        # therefore almost never actually record anything while the lock
        # was genuinely contended. A dedicated, lock-free diagnostic file
        # fixes that; verify it by holding the lock in a separate python
        # process (fcntl.flock — the same primitive ocw-meter itself
        # uses) while a separate `event` call times out acquiring it.
        #
        # Round-5 review: this used to shell out to the `flock(1)`
        # command, which doesn't exist on macOS (a supported platform
        # per the root README) and would ERROR the whole test suite
        # there, not just skip this one test.
        home = pathlib.Path(tempfile.mkdtemp()) / "ocw-meter-home"
        lock_file = home / "state" / ".lock"
        lock_file.parent.mkdir(parents=True, exist_ok=True)
        lock_file.touch()
        holder = subprocess.Popen([
            sys.executable, "-c",
            "import fcntl, sys, time\n"
            "f = open(sys.argv[1], 'w')\n"
            "fcntl.flock(f, fcntl.LOCK_EX)\n"
            "time.sleep(2)\n",
            str(lock_file),
        ])
        try:
            import time as _time

            _time.sleep(0.2)  # let the holder actually acquire the lock
            result = run_meter(["event", "phase.start", "--idempotency-key", "locked1", "--phase", "implement"], home, timeout=10)
            self.assertEqual(result.returncode, 0)
            diagnostics = read_meter_errors(home)
            self.assertEqual(len(diagnostics), 1)
            self.assertEqual(diagnostics[0]["stage"], "write_event_lock_timeout")
        finally:
            holder.wait(timeout=10)
            import shutil

            shutil.rmtree(home.parent, ignore_errors=True)


class PayloadTypeCoercionTests(OcwMeterTestCase):
    def test_cost_estimate_and_is_sidechain_are_coerced(self):
        # Round-4 review: these two were missed in the round-3 pass —
        # cost_estimate_usd is the actual cost figure plan §8.4's
        # formula produces, and is_sidechain as the string "false" is
        # truthy in Python, so `if event["is_sidechain"]` would treat
        # every message as a subagent message.
        result = run_meter(
            [
                "event", "usage.message", "--idempotency-key", "b1", "--message-id", "m",
                "--input-tokens", "4617", "--output-tokens", "329",
                "--cache-read-input-tokens", "27264", "--cache-creation-input-tokens", "0",
                "--cost-basis", "estimated", "--cost-estimate-usd", "0.0123", "--is-sidechain", "false",
            ],
            self.home,
        )
        self.assertEqual(result.returncode, 0)
        event = read_events(self.home)[-1]
        self.assertEqual(event["cost_estimate_usd"], 0.0123)
        self.assertIs(event["is_sidechain"], False)

    def test_is_sidechain_true_is_coerced(self):
        run_meter(
            ["event", "usage.message", "--idempotency-key", "b2", "--message-id", "m2", "--is-sidechain", "true"],
            self.home,
        )
        event = read_events(self.home)[-1]
        self.assertIs(event["is_sidechain"], True)

    def test_nan_and_infinity_are_rejected_not_written(self):
        # Round-4 review: NaN/Infinity are not valid JSON literals — jq
        # and most non-Python parsers reject them even though Python's
        # `json` module accepts them by default. A caller passing one
        # must not corrupt the events file with an unparseable line.
        run_meter(
            ["event", "quota.sample", "--idempotency-key", "c1", "--plan-source", "statusline", "--five-hour-used-pct", "nan"],
            self.home,
        )
        raw = (self.home / "events").glob("*.jsonl")
        text = next(raw).read_text(encoding="utf-8")
        self.assertNotIn("NaN", text)
        event = read_events(self.home)[-1]
        # Left as the original string and flagged, same as any other
        # coercion failure — not silently dropped, not written as NaN.
        self.assertEqual(event["completeness"], "partial")

        result = run_meter(["validate"], self.home)
        self.assertEqual(result.returncode, 0)


class TranscriptFixtureDedupTests(OcwMeterTestCase):
    FIXTURE = REPO_ROOT / "bin" / "tests" / "fixtures" / "transcript_duplicate_message_id.jsonl"

    def test_same_message_id_across_multiple_transcript_lines_dedupes_to_one(self):
        # T04: a single Claude Code response gets re-appended to the
        # transcript once per content block (plan §5.3) — message.id is
        # the only stable dedup key. This fixture is a redacted,
        # shape-accurate sample of exactly that situation (DOC-2608021229 §2.2
        # measured 59.4% of real assistant lines as such duplicates,
        # e.g. 179 raw lines -> 57 distinct message.id). The real
        # `ingest` step (孫3) will read lines like these from
        # ~/.claude/projects/*/*.jsonl and call this same primitive once
        # per row with idempotency_key=f"msg:{id}"; this test drives that
        # primitive directly against the fixture to prove it survives
        # the exact duplication pattern that inflates costs 3x+ if
        # missed.
        raw_lines = [json.loads(line) for line in self.FIXTURE.read_text(encoding="utf-8").splitlines() if line.strip()]
        self.assertGreater(len(raw_lines), 1)

        message_ids = [line["message"]["id"] for line in raw_lines]
        distinct_ids = set(message_ids)
        self.assertLess(len(distinct_ids), len(message_ids), "fixture must contain a real duplicate to be meaningful")

        for line in raw_lines:
            message = line["message"]
            usage = message["usage"]
            run_meter(
                [
                    "event", "usage.message",
                    "--idempotency-key", f"msg:{message['id']}",
                    "--message-id", message["id"],
                    "--model", message["model"],
                    "--input-tokens", str(usage["input_tokens"]),
                    "--output-tokens", str(usage["output_tokens"]),
                    "--cache-read-input-tokens", str(usage["cache_read_input_tokens"]),
                    "--cache-creation-input-tokens", str(usage["cache_creation_input_tokens"]),
                    "--cost-basis", "estimated",
                ],
                self.home,
            )

        events = read_events(self.home)
        self.assertEqual(len(events), len(distinct_ids))
        recorded_ids = {e["message_id"] for e in events}
        self.assertEqual(recorded_ids, distinct_ids)

        # Round-2 review: counting events and message_ids isn't enough —
        # the fixture's duplicate rows are output_tokens: 0 -> 150 -> 329
        # (a streaming response's progressively-complete usage). The
        # kept line must be the LAST one (last-write-wins), not the
        # first (which would silently under-count output tokens by
        # exactly the amount plan §8.4's cost formula multiplies).
        kept = next(e for e in events if e["message_id"] == "msg_fixture_dup_001")
        self.assertEqual(kept["output_tokens"], 329)
        # And the token-count fields themselves must be real numbers, not
        # "[REDACTED]" (round-2) and not strings (round-3).
        self.assertEqual(kept["input_tokens"], 4617)
        self.assertEqual(kept["cache_read_input_tokens"], 27264)

    def test_last_write_wins_generically_for_any_duplicate_key(self):
        run_meter(["event", "phase.start", "--idempotency-key", "lw1", "--phase", "implement", "--note", "first"], self.home)
        run_meter(["event", "phase.start", "--idempotency-key", "lw1", "--phase", "implement", "--note", "second"], self.home)
        events = read_events(self.home)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["note"], "second")


class IngestTests(OcwMeterTestCase):
    def setUp(self):
        super().setUp()
        self.projects_dir = pathlib.Path(self.tmpdir.name) / "claude-projects"
        self.projects_dir.mkdir(parents=True, exist_ok=True)

    def test_ingest_dedupes_content_block_split_lines_via_real_fixture(self):
        # T04/T12, driven through the actual `ingest` scan path (not the
        # `event` primitive directly, unlike TranscriptFixtureDedupTests
        # above) — this is the fixture DOC-2608021229 §2.2's 59.4%-duplicate
        # measurement is based on, reused as-is per the 孫3 prompt's "実
        # transcript由来の縮小fixture" test requirement.
        fixture = REPO_ROOT / "bin" / "tests" / "fixtures" / "transcript_duplicate_message_id.jsonl"
        session_dir = self.projects_dir / "fixture-project"
        session_dir.mkdir(parents=True)
        (session_dir / "00b2ac54-fixture.jsonl").write_text(fixture.read_text(encoding="utf-8"), encoding="utf-8")

        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)

        events = [e for e in read_events(self.home) if e["event_type"] == "usage.message"]
        self.assertEqual(len(events), 2)  # 4 raw assistant lines -> 2 distinct message_id
        by_id = {e["message_id"]: e for e in events}
        # The LAST occurrence of msg_fixture_dup_001 has output_tokens
        # 329 and a real stop_reason (the fixture's first two rows have
        # output_tokens 0/150 and stop_reason null — an in-progress
        # stream). Keeping an earlier row would silently under-count.
        self.assertEqual(by_id["msg_fixture_dup_001"]["output_tokens"], 329)
        self.assertEqual(by_id["msg_fixture_dup_001"]["stop_reason"], "end_turn")
        self.assertEqual(by_id["msg_fixture_dup_001"]["completeness"], "complete")
        self.assertEqual(by_id["msg_fixture_dup_002"]["output_tokens"], 77)

    def test_ingest_is_idempotent_across_repeated_runs(self):
        write_transcript(self.projects_dir, "proj", "sess-idem", [
            assistant_line("sess-idem", "m1"),
            assistant_line("sess-idem", "m2", timestamp="2026-07-15T10:05:00.000Z"),
        ])
        r1 = run_ingest(self.home, self.projects_dir)
        self.assertEqual(r1.returncode, 0, r1.stderr)
        self.assertIn("usage.message written (new):         2", r1.stdout)
        first_events = read_events(self.home)

        r2 = run_ingest(self.home, self.projects_dir)
        self.assertEqual(r2.returncode, 0, r2.stderr)
        self.assertIn("usage.message written (new):         0", r2.stdout)
        second_events = read_events(self.home)

        key = lambda e: e["message_id"]
        self.assertEqual(sorted(first_events, key=key), sorted(second_events, key=key))

    def test_ingest_incremental_only_processes_newly_appended_lines(self):
        path = write_transcript(self.projects_dir, "proj", "sess-inc", [assistant_line("sess-inc", "m1")])
        r1 = run_ingest(self.home, self.projects_dir)
        self.assertEqual(r1.returncode, 0, r1.stderr)
        self.assertEqual(len(read_events(self.home)), 1)

        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(assistant_line("sess-inc", "m2", timestamp="2026-07-15T11:00:00.000Z"), ensure_ascii=False) + "\n")

        r2 = run_ingest(self.home, self.projects_dir)
        self.assertEqual(r2.returncode, 0, r2.stderr)
        self.assertIn("usage.message written (new):         1", r2.stdout)
        events = read_events(self.home)
        self.assertEqual({e["message_id"] for e in events}, {"m1", "m2"})

    def test_ingest_rereads_from_scratch_on_file_rotation(self):
        path = write_transcript(self.projects_dir, "proj", "sess-rot", [assistant_line("sess-rot", "m1")])
        r1 = run_ingest(self.home, self.projects_dir)
        self.assertEqual(r1.returncode, 0, r1.stderr)
        self.assertEqual(len(read_events(self.home)), 1)

        # Simulate rotation: a brand-new file (new inode) replaces the
        # old one at the same path, containing the same message plus a
        # new one — this is what plan §1's "inode変化...を検出したら...
        # 頭から読み直す" guards against. os.replace onto an existing
        # path changes the inode even though the path string is the same.
        tmp_path = path.with_suffix(".jsonl.new")
        tmp_path.write_text(
            "".join(
                json.dumps(line, ensure_ascii=False) + "\n"
                for line in [assistant_line("sess-rot", "m1"), assistant_line("sess-rot", "m2", timestamp="2026-07-15T12:00:00.000Z")]
            ),
            encoding="utf-8",
        )
        os.replace(tmp_path, path)

        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        events = read_events(self.home)
        # m1 is absorbed by message_id dedup even though its bytes were
        # re-read from offset 0 — must not appear as a duplicate event.
        self.assertEqual({e["message_id"] for e in events}, {"m1", "m2"})
        self.assertEqual(len(events), 2)

    def test_ingest_leaves_an_unterminated_final_line_for_the_next_run(self):
        path = write_transcript(self.projects_dir, "proj", "sess-partial", [assistant_line("sess-partial", "m1")])
        with open(path, "a", encoding="utf-8") as fh:
            # No trailing newline: the writer may still be mid-write.
            fh.write(json.dumps(assistant_line("sess-partial", "m2", timestamp="2026-07-15T13:00:00.000Z"), ensure_ascii=False))

        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual({e["message_id"] for e in read_events(self.home)}, {"m1"})
        self.assertEqual(read_quarantine(self.home), [])

        with open(path, "a", encoding="utf-8") as fh:
            fh.write("\n")
        result2 = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result2.returncode, 0, result2.stderr)
        self.assertEqual({e["message_id"] for e in read_events(self.home)}, {"m1", "m2"})

    def test_ingest_quarantines_malformed_line_without_storing_its_bytes(self):
        session_dir = self.projects_dir / "proj"
        session_dir.mkdir(parents=True)
        path = session_dir / "sess-bad.jsonl"
        path.write_text(
            json.dumps(assistant_line("sess-bad", "m1"), ensure_ascii=False) + "\n"
            + '{"type":"assistant","message":{"id":"broken", THIS-IS-NOT-VALID-JSON\n',
            encoding="utf-8",
        )
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual({e["message_id"] for e in read_events(self.home)}, {"m1"})

        quarantined = read_quarantine(self.home)
        self.assertEqual(len(quarantined), 1)
        self.assertEqual(quarantined[0]["reason"], "malformed JSON")
        # No raw_line field at all — a broken line might contain a
        # garbled fragment of prompt/response content from a partial
        # write, so ingest's own quarantine (unlike validate's) never
        # stores the source bytes (plan §1: message.content不可触).
        self.assertNotIn("raw_line", quarantined[0])
        self.assertNotIn("THIS-IS-NOT-VALID-JSON", json.dumps(quarantined[0]))

    def test_ingest_since_does_not_duplicate_quarantine_records_on_repeat(self):
        # PR #27 review round 2 finding "新規2": a --since run never
        # advances the cursor (round 1 finding 1's fix), so it re-reads
        # the same broken line on every invocation. Quarantining it
        # every time would inflate `transcript lines quarantined` in
        # proportion to how many times --since was run, not how much
        # source data is actually broken.
        session_dir = self.projects_dir / "proj"
        session_dir.mkdir(parents=True)
        (session_dir / "sess-bad-since.jsonl").write_text(
            json.dumps(assistant_line("sess-bad-since", "m1", timestamp="2026-07-15T10:00:00.000Z"), ensure_ascii=False) + "\n"
            + "{broken json\n",
            encoding="utf-8",
        )
        for _ in range(3):
            result = run_ingest(self.home, self.projects_dir, args=["--since", "2026-01-01T00:00:00Z"])
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(read_quarantine(self.home)), 0)  # never persisted under --since

        # A --since-less run finally persists it, exactly once.
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(read_quarantine(self.home)), 1)
        result2 = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result2.returncode, 0, result2.stderr)
        self.assertEqual(len(read_quarantine(self.home)), 1)  # still just once

    def test_ingest_since_output_does_not_claim_quarantine_when_none_was_persisted(self):
        # PR #27 review round 3 finding "新規2": under --since, nothing
        # is actually written to quarantine/ingest-transcript.jsonl (see
        # the test above), but the old output label
        # "transcript lines quarantined: N" implied it had been. This
        # tool's own design principle (plan §10.4: 部分的な記録を完全と
        # 誤認しない) applies to its OWN stdout, not just stored data.
        session_dir = self.projects_dir / "proj"
        session_dir.mkdir(parents=True)
        (session_dir / "sess-bad-since2.jsonl").write_text(
            json.dumps(assistant_line("sess-bad-since2", "m1", timestamp="2026-07-15T10:00:00.000Z"), ensure_ascii=False) + "\n"
            + "{broken json\n",
            encoding="utf-8",
        )
        result = run_ingest(self.home, self.projects_dir, args=["--since", "2026-01-01T00:00:00Z"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("transcript lines quarantined:", result.stdout)
        self.assertIn("NOT persisted", result.stdout)
        self.assertEqual(len(read_quarantine(self.home)), 0)

    def test_ingest_tolerates_malformed_session_pr_links_state_file(self):
        # PR #27 review round 2 finding "新規3": a malformed entry in
        # state/session-pr-links.json (this meter's own state, but
        # future format changes could leave stale entries around) must
        # not crash `ingest` with an AttributeError — same
        # start-fresh-on-corruption policy as load_ingest_cursor.
        write_transcript(self.projects_dir, "proj", "sess-badstate", [assistant_line("sess-badstate", "m1")])
        run_ingest(self.home, self.projects_dir)  # creates state/ dir
        state_path = self.home / "state" / "session-pr-links.json"
        state_path.write_text(json.dumps({"some-session": "not-a-dict"}), encoding="utf-8")

        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_ingest_never_persists_message_content_anywhere(self):
        line = assistant_line("sess-content", "m1")
        line["message"]["content"] = [{"type": "text", "text": "THIS-IS-SECRET-PROMPT-CONTENT"}]
        write_transcript(self.projects_dir, "proj", "sess-content", [line])

        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)

        for path in pathlib.Path(self.home).rglob("*"):
            if path.is_file():
                self.assertNotIn("THIS-IS-SECRET-PROMPT-CONTENT", path.read_text(encoding="utf-8", errors="replace"))

    def test_ingest_missing_usage_field_is_completeness_unknown(self):
        # T13 (transcript-observable half of "stream interrupted"): a
        # `usage`-less assistant line is treated the same way as data
        # this meter genuinely cannot see — null fields, not a guess.
        line = assistant_line("sess-nousage", "m1")
        del line["message"]["usage"]
        write_transcript(self.projects_dir, "proj", "sess-nousage", [line])

        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = read_events(self.home)[0]
        self.assertEqual(event["completeness"], "unknown")
        self.assertIsNone(event["input_tokens"])
        self.assertIsNone(event["output_tokens"])
        self.assertIsNone(event["cost_estimate_usd"])

    def test_ingest_distinct_message_ids_both_kept_not_merged(self):
        # T14 (retry): a retry gets a NEW message.id from the provider —
        # it is a second, separately-billable event, not merged into the
        # first (only a REPEATED message.id gets deduped).
        write_transcript(self.projects_dir, "proj", "sess-retry", [
            assistant_line("sess-retry", "m1", output_tokens=10),
            assistant_line("sess-retry", "m2", output_tokens=20, timestamp="2026-07-15T14:00:00.000Z"),
        ])
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(read_events(self.home)), 2)

    def test_ingest_anthropic_model_is_subscription_not_estimated(self):
        write_transcript(self.projects_dir, "proj", "sess-anthropic", [
            assistant_line("sess-anthropic", "m1", model="claude-opus-5"),
        ])
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = read_events(self.home)[0]
        self.assertEqual(event["provider"], "anthropic")
        self.assertEqual(event["cost_basis"], "subscription")
        self.assertIsNone(event["cost_estimate_usd"])
        self.assertEqual(event["completeness"], "complete")

    def test_ingest_deepseek_cost_matches_plan_formula(self):
        # Uses the real bin/prices/deepseek-2026-08-01.json and the exact
        # July totals from plan §1 / DOC-2608021229 §2.2 — this is the $46.78
        # figure the 孫3 prompt's completion criteria checks against.
        write_transcript(self.projects_dir, "proj", "sess-cost", [
            assistant_line(
                "sess-cost", "m1", model="deepseek-v4-pro",
                input_tokens=38336862, cache_read_input_tokens=5428087040,
                cache_creation_input_tokens=0, output_tokens=11983028,
            ),
        ])
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = read_events(self.home)[0]
        self.assertEqual(event["cost_basis"], "estimated")
        self.assertAlmostEqual(event["cost_estimate_usd"], 46.7785848500, places=4)
        self.assertEqual(event["price_table_version"], "deepseek-2026-08-01")
        self.assertEqual(event["price_effective_date"], "2026-08-01")

    def test_ingest_unpriced_model_is_completeness_unknown(self):
        # A DeepSeek-shaped model name absent from bin/prices/*.json
        # (both real price entries, deepseek-v4-pro/-flash, are present
        # in the repo's committed price table — this exercises the
        # "genuinely unpriced" branch with a name that will never match).
        write_transcript(self.projects_dir, "proj", "sess-unpriced", [
            assistant_line("sess-unpriced", "m1", model="deepseek-v4-nonexistent"),
        ])
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = read_events(self.home)[0]
        self.assertIsNone(event["cost_estimate_usd"])
        self.assertEqual(event["cost_basis"], "estimated")
        self.assertEqual(event["completeness"], "unknown")

    def test_ingest_new_price_table_does_not_touch_already_ingested_events(self):
        # T16: adding a newer price_table_version must not retroactively
        # change cost_estimate_usd on events already written.
        price_dir = pathlib.Path(self.tmpdir.name) / "prices-v1"
        price_dir.mkdir()
        (price_dir / "deepseek-2026-08-01.json").write_text(json.dumps({
            "price_table_version": "deepseek-2026-08-01", "effective_date": "2026-08-01",
            "models": {"deepseek-v4-pro": {"cache_hit_in": 0.003625, "cache_miss_in": 0.435, "out": 0.87}},
        }), encoding="utf-8")
        write_transcript(self.projects_dir, "proj", "sess-pricever", [
            assistant_line("sess-pricever", "m1", model="deepseek-v4-pro",
                            input_tokens=1000, cache_read_input_tokens=2000, output_tokens=300),
        ])
        r1 = run_ingest(self.home, self.projects_dir, price_dir=price_dir)
        self.assertEqual(r1.returncode, 0, r1.stderr)
        before = read_events(self.home)[0]

        # A new, deliberately much more expensive price table shows up.
        (price_dir / "deepseek-2099-01-01.json").write_text(json.dumps({
            "price_table_version": "deepseek-2099-01-01", "effective_date": "2099-01-01",
            "models": {"deepseek-v4-pro": {"cache_hit_in": 99, "cache_miss_in": 99, "out": 99}},
        }), encoding="utf-8")

        result = run_ingest(self.home, self.projects_dir, price_dir=price_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("usage.message written (new):         0", result.stdout)
        self.assertIn("usage.message replaced (re-run/dup):  0", result.stdout)
        after = read_events(self.home)[0]

        self.assertEqual(before["cost_estimate_usd"], after["cost_estimate_usd"])
        self.assertEqual(before["price_table_version"], after["price_table_version"])

    def test_ingest_role_resolved_via_herdr_pane_list(self):
        # T08: role/pane/workspace attribution via a mocked Herdr CLI —
        # not implementable before `ingest` existed (孫1's docstring
        # deferred it here explicitly).
        session_id = "sess-herdr"
        write_transcript(self.projects_dir, "proj", session_id, [assistant_line(session_id, "m1")])

        pane_json = json.dumps({"panes": [{
            "pane_id": "w1:p2", "label": "implementer", "workspace_id": "w1",
            "agent_session": {"agent": "claude", "kind": "id", "value": session_id},
            "cwd": "/whatever",
        }]})
        fake_bin = pathlib.Path(self.tmpdir.name) / "fake-bin"
        fake_bin.mkdir()
        herdr_script = fake_bin / "herdr"
        herdr_script.write_text(
            "#!/usr/bin/env bash\n"
            'if [ "$1" = "status" ] && [ "$2" = "server" ]; then exit 0; fi\n'
            'if [ "$1" = "workspace" ] && [ "$2" = "list" ]; then echo \'{"workspaces":[{"workspace_id":"w1"}]}\'; exit 0; fi\n'
            f"if [ \"$1\" = \"pane\" ] && [ \"$2\" = \"list\" ]; then echo '{pane_json}'; exit 0; fi\n"
            "exit 1\n",
            encoding="utf-8",
        )
        herdr_script.chmod(0o755)

        path_with_fake_herdr_first = f"{fake_bin}:{os.environ.get('PATH', '')}"
        result = run_ingest(self.home, self.projects_dir, extra_env={"PATH": path_with_fake_herdr_first})
        self.assertEqual(result.returncode, 0, result.stderr)
        event = read_events(self.home)[0]
        self.assertEqual(event["role"], "implementer")
        self.assertEqual(event["workspace_id"], "w1")
        self.assertEqual(event["pane_id"], "w1:p2")

    def test_ingest_role_stays_unknown_when_herdr_unavailable(self):
        write_transcript(self.projects_dir, "proj", "sess-noherdr", [assistant_line("sess-noherdr", "m1")])
        # A PATH with no `herdr` on it at all (and no dev-machine Herdr
        # server to accidentally talk to) — role resolution must fail
        # closed to "unknown", never guess (plan §7.4: 推測で埋めない).
        result = run_ingest(self.home, self.projects_dir, extra_env={"PATH": "/usr/bin:/bin"})
        self.assertEqual(result.returncode, 0, result.stderr)
        event = read_events(self.home)[0]
        self.assertEqual(event["role"], "unknown")
        self.assertIsNone(event["workspace_id"])
        self.assertIsNone(event["pane_id"])

    def test_ingest_pr_number_resolved_from_pr_link_transcript_line(self):
        session_id = "sess-prlink"
        write_transcript(self.projects_dir, "proj", session_id, [
            assistant_line(session_id, "m1"),
            {"type": "pr-link", "sessionId": session_id, "prNumber": 42,
             "prUrl": "https://github.com/manemone/dotfiles/pull/42",
             "prRepository": "manemone/dotfiles", "timestamp": "2026-07-15T10:01:00.000Z"},
        ])
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = read_events(self.home)[0]
        self.assertEqual(event["pr_number"], 42)
        self.assertEqual(event["pr_url"], "https://github.com/manemone/dotfiles/pull/42")

    def test_ingest_pr_number_null_when_unresolvable_and_gh_disabled(self):
        write_transcript(self.projects_dir, "proj", "sess-nopr", [assistant_line("sess-nopr", "m1")])
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(read_events(self.home)[0]["pr_number"])

    def test_ingest_no_external_network_calls_by_default(self):
        # `gh` must never be invoked unless OCW_METER_INGEST_USE_GH=1 —
        # a fake `gh` that would fail loudly if actually called proves
        # ingest never shells out to it under default settings.
        write_transcript(self.projects_dir, "proj", "sess-nogh", [assistant_line("sess-nogh", "m1")])
        fake_bin = pathlib.Path(self.tmpdir.name) / "no-gh-bin"
        fake_bin.mkdir()
        poison_gh = fake_bin / "gh"
        poison_gh.write_text("#!/usr/bin/env bash\necho 'gh should not have been called' >&2\nexit 7\n", encoding="utf-8")
        poison_gh.chmod(0o755)
        result = run_ingest(
            self.home, self.projects_dir,
            extra_env={"PATH": f"{fake_bin}:{os.environ.get('PATH', '')}", "OCW_METER_INGEST_USE_GH": "0"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("gh should not have been called", result.stderr)

    def test_ingest_run_id_resolved_via_ocw_run_id_file(self):
        # PR #27 review round 1 finding 3: matching a locally stored
        # run.start event by (worktree, time range) does NOT work in
        # real usage, because bin/ocw never passes --worktree to
        # `ocw-meter event run.start` (it defaults to the ORIGIN
        # worktree ocw was invoked FROM, not the newly created one the
        # transcript's own `cwd` points at). The fix reads
        # <worktree's git-dir>/ocw-run-id directly — exactly what
        # bin/ocw itself writes right after `git worktree add` and reads
        # back in `ocw rm`. This test reproduces that real mechanism
        # with an actual git worktree instead of a fake --worktree value.
        worktree_dir = make_ocw_style_worktree(self.tmpdir.name, run_id="run-abc123")
        write_transcript(self.projects_dir, "proj", "sess-run", [
            assistant_line("sess-run", "m1", cwd=str(worktree_dir)),
        ])
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        usage_event = next(e for e in read_events(self.home) if e["event_type"] == "usage.message")
        self.assertEqual(usage_event["run_id"], "run-abc123")

    def test_ingest_run_id_is_null_when_ocw_run_id_file_absent(self):
        # No ocw-run-id file was ever written for this cwd (e.g. a
        # session outside any `ocw` worktree, or one whose worktree was
        # since removed — git prunes the file along with its metadata
        # dir). Must be null, not guessed.
        write_transcript(self.projects_dir, "proj", "sess-norun", [
            assistant_line("sess-norun", "m1", cwd="/nonexistent/not-a-worktree"),
        ])
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIsNone(read_events(self.home)[0]["run_id"])

    def test_ingest_run_id_not_misattributed_when_worktree_path_is_reused(self):
        # PR #27 review round 2 finding "新規1": `ocw rm <name>` followed
        # by `ocw new <name>` reuses the SAME worktree path for a brand
        # new run. The ocw-run-id file only knows "which run_id does
        # this PATH belong to now" — a message generated under the OLD
        # incarnation (never ingested before the path got reused) must
        # NOT be silently re-attributed to the NEW run_id.
        worktree_dir = make_ocw_style_worktree(self.tmpdir.name, run_id="RUN-OLD-111")
        run_meter(
            ["event", "run.start", "--idempotency-key", "old-run-start", "--run-id", "RUN-OLD-111",
             "--ts", "2026-07-01T00:00:00.000Z", "--base-ref", "origin/main", "--command", "claude"],
            self.home,
        )
        # The message predates RUN-OLD-111's own run.start? No — it's
        # AFTER RUN-OLD-111 started but the worktree path gets reused for
        # a NEW run whose run.start is even later, and the message
        # predates THAT new run.start — the same worktree path, but the
        # message belongs to the old incarnation.
        write_transcript(self.projects_dir, "proj", "sess-reuse", [
            assistant_line("sess-reuse", "old-run-msg", cwd=str(worktree_dir), timestamp="2026-07-15T00:00:00.000Z"),
        ])
        # Simulate `ocw rm` + `ocw new` reusing the same path: overwrite
        # ocw-run-id with a NEW run_id whose run.start is AFTER the
        # message's own timestamp.
        git_dir = subprocess.run(
            ["git", "-C", str(worktree_dir), "rev-parse", "--absolute-git-dir"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        (pathlib.Path(git_dir) / "ocw-run-id").write_text("RUN-NEW-999\n", encoding="utf-8")
        run_meter(
            ["event", "run.start", "--idempotency-key", "new-run-start", "--run-id", "RUN-NEW-999",
             "--ts", "2026-07-20T00:00:00.000Z", "--base-ref", "origin/main", "--command", "claude"],
            self.home,
        )

        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        # Two run.start events (different days) plus the usage.message
        # sort chronologically across day-files — pick the message
        # explicitly rather than assuming index 0.
        event = next(e for e in read_events(self.home) if e["event_type"] == "usage.message")
        # Must NOT be attributed to RUN-NEW-999 (the message predates its
        # run.start) — and RUN-OLD-111's own run.start ts isn't checked
        # against here since the file no longer points at it at all, so
        # the only safe answer is null.
        self.assertIsNone(event["run_id"])

    def test_ingest_run_id_accepted_when_message_is_after_its_run_start(self):
        # The cross-check must not become overly strict: a message
        # genuinely generated after its run_id's own run.start must
        # still resolve normally (this is the common, correct case).
        worktree_dir = make_ocw_style_worktree(self.tmpdir.name, run_id="run-normal")
        run_meter(
            ["event", "run.start", "--idempotency-key", "normal-run-start", "--run-id", "run-normal",
             "--ts", "2026-07-01T00:00:00.000Z", "--base-ref", "origin/main", "--command", "claude"],
            self.home,
        )
        write_transcript(self.projects_dir, "proj", "sess-normal", [
            assistant_line("sess-normal", "m1", cwd=str(worktree_dir), timestamp="2026-07-15T00:00:00.000Z"),
        ])
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        # The run.start event (ts 2026-07-01) sorts into an earlier
        # day-file than the usage.message (2026-07-15), so index [0]
        # would trivially be the run.start event itself (whose own
        # run_id field is "run-normal" regardless of what the message
        # resolved to) — select the usage.message explicitly.
        usage_event = next(e for e in read_events(self.home) if e["event_type"] == "usage.message")
        self.assertEqual(usage_event["run_id"], "run-normal")

    def test_ingest_pr_number_resolved_via_run_id_bind_using_ocw_run_id_file(self):
        # End-to-end: pr.bind's run_id must line up with what the fixed
        # run_id resolution (finding 3) actually produces, since PR
        # attribution priority ① depends on it (plan §7.4).
        worktree_dir = make_ocw_style_worktree(self.tmpdir.name, run_id="run-xyz789")
        run_meter(
            ["event", "pr.bind", "--idempotency-key", "bind1", "--run-id", "run-xyz789",
             "--pr-number", "99", "--pr-url", "https://github.com/manemone/dotfiles/pull/99"],
            self.home,
        )
        write_transcript(self.projects_dir, "proj", "sess-run-pr", [
            assistant_line("sess-run-pr", "m1", cwd=str(worktree_dir)),
        ])
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = next(e for e in read_events(self.home) if e["event_type"] == "usage.message")
        self.assertEqual(event["run_id"], "run-xyz789")
        self.assertEqual(event["pr_number"], 99)

    def test_ingest_survives_a_run_start_with_an_offset_less_timestamp(self):
        # PR #27 review round 3 finding "新規1": `event --ts` accepts an
        # offset-less (naive) ISO 8601 value — `hard_line_errors` doesn't
        # reject it, so it can genuinely end up stored. Round 2's run_id
        # staleness cross-check ("新規1" there) then compared it against
        # a timezone-AWARE message timestamp, raising TypeError and
        # taking down `ingest` entirely, with no recovery path (this
        # naive `ts` isn't rejected by `validate` either).
        worktree_dir = make_ocw_style_worktree(self.tmpdir.name, run_id="run-naive-ts")
        run_meter(
            ["event", "run.start", "--idempotency-key", "naive-run-start", "--run-id", "run-naive-ts",
             "--ts", "2026-07-01T00:00:00", "--base-ref", "origin/main", "--command", "claude"],
            self.home,
        )
        write_transcript(self.projects_dir, "proj", "sess-naive-ts", [
            assistant_line("sess-naive-ts", "m1", cwd=str(worktree_dir), timestamp="2026-07-15T00:00:00.000Z"),
        ])
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = next(e for e in read_events(self.home) if e["event_type"] == "usage.message")
        self.assertEqual(event["run_id"], "run-naive-ts")

    def test_ingest_repo_resolved_from_cwd_git_remote(self):
        # PR #27 review round 1 finding 9: `repo` was hardcoded null.
        worktree_dir = pathlib.Path(self.tmpdir.name) / "repo-with-remote"
        subprocess.run(["git", "init", "-q", str(worktree_dir)], check=True)
        subprocess.run(
            ["git", "-C", str(worktree_dir), "remote", "add", "origin", "https://github.com/manemone/dotfiles.git"],
            check=True,
        )
        write_transcript(self.projects_dir, "proj", "sess-repo", [
            assistant_line("sess-repo", "m1", cwd=str(worktree_dir)),
        ])
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(read_events(self.home)[0]["repo"], "manemone/dotfiles")

    def test_ingest_refuses_to_operate_inside_a_git_worktree(self):
        write_transcript(self.projects_dir, "proj", "sess-refuse", [assistant_line("sess-refuse", "m1")])
        result = run_ingest(REPO_ROOT / "tmp-test-ocw-meter-ingest-worktree-guard", self.projects_dir)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((REPO_ROOT / "tmp-test-ocw-meter-ingest-worktree-guard").exists())

    def test_ingest_normalizes_context_window_suffix_in_model_name(self):
        write_transcript(self.projects_dir, "proj", "sess-1m", [
            assistant_line("sess-1m", "m1", model="deepseek-v4-pro[1m]",
                            input_tokens=1000, cache_read_input_tokens=2000, output_tokens=300),
        ])
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = read_events(self.home)[0]
        self.assertEqual(event["model"], "deepseek-v4-pro")
        # The [1m] suffix must not have blocked the price lookup either.
        self.assertIsNotNone(event["cost_estimate_usd"])
        self.assertEqual(event["price_table_version"], "deepseek-2026-08-01")

    def test_ingest_picks_price_table_by_message_timestamp_not_run_date(self):
        # PR #27 review round 1 finding 4 (plan §17 R5): a price table
        # added AFTER a message's own date must not retroactively apply
        # to that message the first time it's ingested.
        price_dir = pathlib.Path(self.tmpdir.name) / "prices-dated"
        price_dir.mkdir()
        (price_dir / "deepseek-2026-07-01.json").write_text(json.dumps({
            "price_table_version": "deepseek-2026-07-01", "effective_date": "2026-07-01",
            "models": {"deepseek-v4-pro": {"cache_hit_in": 0.003625, "cache_miss_in": 0.435, "out": 0.87}},
        }), encoding="utf-8")
        (price_dir / "deepseek-2026-07-20.json").write_text(json.dumps({
            "price_table_version": "deepseek-2026-07-20", "effective_date": "2026-07-20",
            "models": {"deepseek-v4-pro": {"cache_hit_in": 999, "cache_miss_in": 999, "out": 999}},
        }), encoding="utf-8")
        write_transcript(self.projects_dir, "proj", "sess-dated", [
            # Message is from BEFORE the 07-20 table's effective_date —
            # the 07-01 table must be applied, not 07-20's.
            assistant_line("sess-dated", "m1", timestamp="2026-07-15T10:00:00.000Z",
                            input_tokens=1000, cache_read_input_tokens=2000, output_tokens=300),
        ])
        result = run_ingest(self.home, self.projects_dir, price_dir=price_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = read_events(self.home)[0]
        self.assertEqual(event["price_table_version"], "deepseek-2026-07-01")
        self.assertLess(event["cost_estimate_usd"], 1.0)  # sanity: not the 999/1M-priced table

    def test_ingest_since_does_not_permanently_lose_older_messages(self):
        # PR #27 review round 1 finding 1: a --since run must not
        # advance the persisted cursor, or the filtered-out range
        # becomes permanently unreachable even by a later run with no
        # --since at all.
        write_transcript(self.projects_dir, "proj", "sess-since", [
            assistant_line("sess-since", "old", timestamp="2026-06-01T00:00:00.000Z"),
            assistant_line("sess-since", "new", timestamp="2026-07-15T00:00:00.000Z"),
        ])
        r1 = run_ingest(self.home, self.projects_dir, args=["--since", "2026-07-01T00:00:00Z"])
        self.assertEqual(r1.returncode, 0, r1.stderr)
        self.assertEqual({e["message_id"] for e in read_events(self.home)}, {"new"})

        r2 = run_ingest(self.home, self.projects_dir)  # no --since this time
        self.assertEqual(r2.returncode, 0, r2.stderr)
        self.assertEqual({e["message_id"] for e in read_events(self.home)}, {"old", "new"})

    def test_ingest_pr_link_survives_across_incremental_runs(self):
        # PR #27 review round 1 finding 2: a session's `pr-link` must
        # still apply to messages ingested in a LATER run, even though
        # the cursor has already moved past the pr-link line itself.
        session_id = "sess-prlink-incremental"
        path = write_transcript(self.projects_dir, "proj", session_id, [
            assistant_line(session_id, "m1"),
            {"type": "pr-link", "sessionId": session_id, "prNumber": 7,
             "prUrl": "https://github.com/manemone/dotfiles/pull/7",
             "prRepository": "manemone/dotfiles", "timestamp": "2026-07-15T10:01:00.000Z"},
        ])
        r1 = run_ingest(self.home, self.projects_dir)
        self.assertEqual(r1.returncode, 0, r1.stderr)

        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(assistant_line(session_id, "m2", timestamp="2026-07-15T11:00:00.000Z"), ensure_ascii=False) + "\n")
        r2 = run_ingest(self.home, self.projects_dir)
        self.assertEqual(r2.returncode, 0, r2.stderr)

        m2_event = next(e for e in read_events(self.home) if e["message_id"] == "m2")
        self.assertEqual(m2_event["pr_number"], 7)

    def test_ingest_appending_after_truncated_day_file_preserves_new_data_and_records_diagnostic(self):
        # PR #27 review round 1 finding 7. A pure REPLACE (no new keys)
        # must preserve the file's original trailing-newline state
        # exactly; this covers the harder case, appending brand new
        # events after an already-truncated tail, which must not corrupt
        # either the old or the new data and must leave a visible trace
        # instead of silently "healing" the crash marker.
        write_transcript(self.projects_dir, "proj", "sess-trunc", [
            assistant_line("sess-trunc", "m1", timestamp="2026-07-15T10:00:00.000Z"),
        ])
        r1 = run_ingest(self.home, self.projects_dir)
        self.assertEqual(r1.returncode, 0, r1.stderr)
        events_file = self.home / "events" / "2026-07-15.jsonl"
        # Truncate the stored file mid-write, simulating a crash.
        original = events_file.read_text(encoding="utf-8")
        events_file.write_text(original.rstrip("\n")[:-5], encoding="utf-8")

        write_transcript(self.projects_dir, "proj", "sess-trunc", [
            assistant_line("sess-trunc", "m1", timestamp="2026-07-15T10:00:00.000Z"),
            assistant_line("sess-trunc", "m2", timestamp="2026-07-15T12:00:00.000Z"),
        ])
        r2 = run_ingest(self.home, self.projects_dir)
        self.assertEqual(r2.returncode, 0, r2.stderr)

        # The new event (m2) must be intact, valid JSON — not merged
        # into the truncated garbage.
        validate_result = run_meter(["validate"], self.home)
        self.assertEqual(validate_result.returncode, 0)
        m2_events = [e for e in read_events(self.home) if e.get("message_id") == "m2"]
        self.assertEqual(len(m2_events), 1)

        # The tradeoff (old truncated line can no longer be classified
        # as "possible crash" once something follows it) is recorded,
        # not silent.
        meter_errors = read_meter_errors(self.home)
        self.assertTrue(any(e.get("stage") == "ingest_appended_after_truncated_day_file" for e in meter_errors))

    def test_ingest_pure_replace_preserves_original_trailing_newline_state(self):
        # The other half of finding 7: re-ingesting the SAME message
        # (no new keys, just a replace) on a day file that already lacks
        # a trailing newline must not add one.
        write_transcript(self.projects_dir, "proj", "sess-trunc2", [
            assistant_line("sess-trunc2", "dup1", output_tokens=1, timestamp="2026-07-16T10:00:00.000Z"),
        ])
        r1 = run_ingest(self.home, self.projects_dir)
        self.assertEqual(r1.returncode, 0, r1.stderr)
        events_file = self.home / "events" / "2026-07-16.jsonl"
        self.assertTrue(events_file.read_text(encoding="utf-8").endswith("\n"))
        # Strip the trailing newline to simulate an already-truncated
        # file whose last (and only) line is otherwise valid JSON.
        text = events_file.read_text(encoding="utf-8")
        events_file.write_text(text.rstrip("\n"), encoding="utf-8")

        # Force a re-ingest of the exact same message.id by resetting
        # the transcript cursor's offset (simulating file rotation).
        cursor_path = self.home / "state" / "ingest-cursor.json"
        cursor = json.loads(cursor_path.read_text(encoding="utf-8"))
        for entry in cursor["files"].values():
            entry["offset"] = 0
            entry["inode"] = -1  # force the rotation/reread path
        cursor_path.write_text(json.dumps(cursor), encoding="utf-8")

        r2 = run_ingest(self.home, self.projects_dir)
        self.assertEqual(r2.returncode, 0, r2.stderr)
        self.assertFalse(events_file.read_text(encoding="utf-8").endswith("\n"))


class TimeOfDayPricingTests(OcwMeterTestCase):
    """計画書 DOC-2608081456孫3: time-of-day price table extension. All
    windows below use `tz_offset: "+08:00"` (Beijing time, matching
    DeepSeek's own announced windows) with a deliberately simple
    base/window price pair (1.0 / 2.0 per token) so cost assertions
    don't need to reproduce the real formula's arithmetic.

    `time_of_day_basis` uses basis-neutral values (`in_window` /
    `base_rate`, not `peak` / `off_peak` — レビュー指摘4: this schema
    can't know which side is actually more expensive)."""

    def setUp(self):
        super().setUp()
        self.projects_dir = pathlib.Path(self.tmpdir.name) / "claude-projects"
        self.projects_dir.mkdir(parents=True, exist_ok=True)
        self.price_dir = pathlib.Path(self.tmpdir.name) / "prices-tod"

    def _tod_table(self, version="deepseek-2026-08-01-tod"):
        return {
            "price_table_version": version,
            "effective_date": "2026-08-01",
            "models": {
                "deepseek-v4-pro": {"cache_hit_in": 0, "cache_miss_in": 1.0, "out": 0},
            },
            "time_of_day_pricing": {
                "tz_offset": "+08:00",
                "boundary": "start_inclusive_end_exclusive",
                "windows": [
                    {"start": "09:00", "end": "12:00",
                     "models": {"deepseek-v4-pro": {"cache_hit_in": 0, "cache_miss_in": 2.0, "out": 0}}},
                    {"start": "14:00", "end": "18:00",
                     "models": {"deepseek-v4-pro": {"cache_hit_in": 0, "cache_miss_in": 2.0, "out": 0}}},
                ],
            },
        }

    def _ingest_one(self, timestamp, table=None, session="sess-tod"):
        write_price_table(self.price_dir, "deepseek-tod.json", table or self._tod_table())
        write_transcript(self.projects_dir, "proj", session, [
            assistant_line(session, "m1", model="deepseek-v4-pro", timestamp=timestamp,
                            input_tokens=1_000_000, cache_read_input_tokens=0,
                            cache_creation_input_tokens=0, output_tokens=0),
        ])
        result = run_ingest(self.home, self.projects_dir, price_dir=self.price_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        return read_events(self.home)[0]

    # -- backward compatibility --------------------------------------------

    def test_table_without_time_of_day_pricing_is_unaffected(self):
        # Uses the real, unmodified bin/prices/deepseek-2026-08-01.json —
        # the primary evidence this feature is backward compatible (孫3
        # プロンプト §テスト "既存のテストが無改変で通ることが主要な根拠").
        write_transcript(self.projects_dir, "proj", "sess-compat", [
            assistant_line("sess-compat", "m1", model="deepseek-v4-pro",
                            timestamp="2026-08-05T02:00:00.000Z",  # Beijing 10:00 — would be "in_window" if defined
                            input_tokens=1000, cache_read_input_tokens=2000, output_tokens=300),
        ])
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = read_events(self.home)[0]
        self.assertEqual(event["time_of_day_basis"], "not_applicable")
        self.assertIsNotNone(event["cost_estimate_usd"])

    # -- in_window / base_rate -----------------------------------------------

    def test_timestamp_inside_window_gets_window_price(self):
        # Beijing 10:00 (UTC 02:00) is inside the 09:00-12:00 window.
        event = self._ingest_one("2026-08-05T02:00:00.000Z")
        self.assertEqual(event["time_of_day_basis"], "in_window")
        self.assertAlmostEqual(event["cost_estimate_usd"], 2.0)

    def test_timestamp_outside_every_window_gets_base_price(self):
        # Beijing 13:00 (UTC 05:00) is between the two windows.
        event = self._ingest_one("2026-08-05T05:00:00.000Z")
        self.assertEqual(event["time_of_day_basis"], "base_rate")
        self.assertAlmostEqual(event["cost_estimate_usd"], 1.0)

    # -- boundary handling -----------------------------------------------

    def test_window_start_boundary_is_inclusive(self):
        # Beijing 09:00:00 exactly (UTC 01:00:00) -- start of the window.
        event = self._ingest_one("2026-08-05T01:00:00.000Z")
        self.assertEqual(event["time_of_day_basis"], "in_window")
        self.assertAlmostEqual(event["cost_estimate_usd"], 2.0)

    def test_window_end_boundary_is_exclusive(self):
        # Beijing 12:00:00 exactly (UTC 04:00:00) -- end of the window.
        event = self._ingest_one("2026-08-05T04:00:00.000Z")
        self.assertEqual(event["time_of_day_basis"], "base_rate")
        self.assertAlmostEqual(event["cost_estimate_usd"], 1.0)

    def test_boundary_field_mismatching_the_only_supported_rule_is_unusable(self):
        # レビュー指摘5: `boundary` is a real, validated field now, not a
        # documented-but-ignored one -- a table that claims a boundary
        # rule this file doesn't implement must be treated as unusable,
        # not silently computed with the (opposite) hardcoded rule.
        table = self._tod_table()
        table["time_of_day_pricing"]["boundary"] = "start_exclusive_end_inclusive"
        event = self._ingest_one("2026-08-05T02:00:00.000Z", table=table)  # otherwise squarely in-window
        self.assertEqual(event["time_of_day_basis"], "not_applicable")
        self.assertAlmostEqual(event["cost_estimate_usd"], 1.0)

    # -- UTC -> Beijing conversion, including a date rollover --------------

    def test_utc_timestamp_is_converted_to_beijing_window_across_date_boundary(self):
        # A window entirely inside "the day after" from UTC's point of
        # view: Beijing 00:00-03:00 (UTC+8) only exists as UTC 16:00-
        # 19:00 of the PREVIOUS calendar date -- exactly the "UTC 深夜 =
        # 北京の朝" case 孫3プロンプト's test list requires. If the
        # implementation ever forgot to actually convert timezones (e.g.
        # read `ts_dt.hour` instead of `ts_dt.astimezone(tz).hour`), this
        # message (2026-07-14 UTC) would be judged against the WRONG
        # calendar date's window matching (still base_rate by accident,
        # since the naive UTC hour 16 isn't in 00:00-03:00 either) —
        # the assertion below instead pins the actual local hour (00:30)
        # produced by a correct astimezone() conversion.
        table = self._tod_table()
        table["time_of_day_pricing"]["windows"] = [{
            "start": "00:00", "end": "03:00",
            "models": {"deepseek-v4-pro": {"cache_hit_in": 0, "cache_miss_in": 2.0, "out": 0}},
        }]
        # 2026-07-14T16:30:00Z + 08:00 = 2026-07-15T00:30:00 (next date).
        event = self._ingest_one("2026-07-14T16:30:00.000Z", table=table)
        self.assertEqual(event["time_of_day_basis"], "in_window")
        self.assertAlmostEqual(event["cost_estimate_usd"], 2.0)

    # -- missing timestamp -------------------------------------------------

    def test_missing_timestamp_falls_back_to_base_price_without_crashing(self):
        write_price_table(self.price_dir, "deepseek-tod.json", self._tod_table())
        line = assistant_line("sess-notime", "m1", model="deepseek-v4-pro",
                               input_tokens=1_000_000, cache_read_input_tokens=0,
                               cache_creation_input_tokens=0, output_tokens=0)
        line["timestamp"] = None
        write_transcript(self.projects_dir, "proj", "sess-notime", [line])
        result = run_ingest(self.home, self.projects_dir, price_dir=self.price_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = read_events(self.home)[0]
        self.assertEqual(event["time_of_day_basis"], "unknown_timestamp")
        self.assertAlmostEqual(event["cost_estimate_usd"], 1.0)  # base price, not guessed in/out of window

    # -- a model absent from every window is unaffected ---------------------

    def test_model_not_listed_in_any_window_is_not_applicable(self):
        table = self._tod_table()
        table["models"]["deepseek-v4-flash"] = {"cache_hit_in": 0, "cache_miss_in": 1.0, "out": 0}
        write_price_table(self.price_dir, "deepseek-tod.json", table)
        write_transcript(self.projects_dir, "proj", "sess-flash", [
            # Beijing 10:00 -- inside the pro-only window, but this
            # message uses -flash, which has no window override.
            assistant_line("sess-flash", "m1", model="deepseek-v4-flash", timestamp="2026-08-05T02:00:00.000Z",
                            input_tokens=1_000_000, cache_read_input_tokens=0,
                            cache_creation_input_tokens=0, output_tokens=0),
        ])
        result = run_ingest(self.home, self.projects_dir, price_dir=self.price_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = read_events(self.home)[0]
        self.assertEqual(event["time_of_day_basis"], "not_applicable")
        self.assertAlmostEqual(event["cost_estimate_usd"], 1.0)

    # -- malformed time_of_day_pricing never crashes ingest -----------------

    def test_missing_tz_offset_does_not_crash_ingest(self):
        table = self._tod_table()
        # No tz_offset at all -- the whole block must be treated as
        # unusable (not_applicable), not raise.
        del table["time_of_day_pricing"]["tz_offset"]
        event = self._ingest_one("2026-08-05T02:00:00.000Z", table=table)
        self.assertEqual(event["time_of_day_basis"], "not_applicable")
        self.assertAlmostEqual(event["cost_estimate_usd"], 1.0)

    def test_out_of_range_tz_offset_does_not_crash_ingest(self):
        # レビュー指摘1の回帰テスト: `timezone()` raises ValueError for a
        # >=24h magnitude offset. This used to propagate all the way up
        # through `_time_of_day_spec` -> `_select_prices_for_model` ->
        # `compute_cost` -> the list comprehension in the ingest routine
        # that calls `build_usage_event` for every candidate, with no
        # try/except anywhere in that chain -- `ingest` exited 1 and
        # wrote ZERO events (including unrelated messages), directly
        # violating `compute_cost`'s own "Never raises" docstring.
        table = self._tod_table()
        table["time_of_day_pricing"]["tz_offset"] = "+25:00"
        event = self._ingest_one("2026-08-05T02:00:00.000Z", table=table)
        self.assertEqual(event["time_of_day_basis"], "not_applicable")
        self.assertAlmostEqual(event["cost_estimate_usd"], 1.0)

    def test_out_of_range_minutes_in_tz_offset_does_not_silently_normalize(self):
        # "+08:75" must not silently become UTC+09:15 -- minutes are
        # range-checked exactly like `_parse_hhmm_to_minutes` already
        # checks window boundaries.
        table = self._tod_table()
        table["time_of_day_pricing"]["tz_offset"] = "+08:75"
        event = self._ingest_one("2026-08-05T02:00:00.000Z", table=table)
        self.assertEqual(event["time_of_day_basis"], "not_applicable")
        self.assertAlmostEqual(event["cost_estimate_usd"], 1.0)

    def test_tz_database_name_is_rejected_not_crashed_on(self):
        # zoneinfo names are deliberately unsupported (孫3プロンプト §1:
        # tzdata isn't guaranteed present) -- must fall back cleanly.
        table = self._tod_table()
        table["time_of_day_pricing"]["tz_offset"] = "Asia/Shanghai"
        event = self._ingest_one("2026-08-05T02:00:00.000Z", table=table)
        self.assertEqual(event["time_of_day_basis"], "not_applicable")
        self.assertAlmostEqual(event["cost_estimate_usd"], 1.0)

    def test_non_list_windows_does_not_crash_ingest(self):
        table = self._tod_table()
        table["time_of_day_pricing"]["windows"] = {"start": "09:00", "end": "12:00"}
        event = self._ingest_one("2026-08-05T02:00:00.000Z", table=table)
        self.assertEqual(event["time_of_day_basis"], "not_applicable")
        self.assertAlmostEqual(event["cost_estimate_usd"], 1.0)

    def test_non_dict_time_of_day_pricing_does_not_crash_ingest(self):
        table = self._tod_table()
        table["time_of_day_pricing"] = ["not", "a", "dict"]
        event = self._ingest_one("2026-08-05T02:00:00.000Z", table=table)
        self.assertEqual(event["time_of_day_basis"], "not_applicable")
        self.assertAlmostEqual(event["cost_estimate_usd"], 1.0)

    def test_malformed_hhmm_window_bounds_never_match_but_do_not_crash(self):
        table = self._tod_table()
        table["time_of_day_pricing"]["windows"] = [{
            "start": "9:00", "end": "12:00",  # single-digit hour: not "HH:MM"
            "models": {"deepseek-v4-pro": {"cache_hit_in": 0, "cache_miss_in": 2.0, "out": 0}},
        }]
        event = self._ingest_one("2026-08-05T02:00:00.000Z", table=table)  # would be in-window if parsed
        self.assertEqual(event["time_of_day_basis"], "base_rate")
        self.assertAlmostEqual(event["cost_estimate_usd"], 1.0)

    def test_cross_midnight_window_never_matches_but_does_not_crash(self):
        table = self._tod_table()
        table["time_of_day_pricing"]["windows"] = [{
            "start": "22:00", "end": "02:00",  # start >= end after normalization: unsupported
            "models": {"deepseek-v4-pro": {"cache_hit_in": 0, "cache_miss_in": 2.0, "out": 0}},
        }]
        event = self._ingest_one("2026-08-05T15:30:00.000Z", table=table)  # Beijing 23:30
        self.assertEqual(event["time_of_day_basis"], "base_rate")
        self.assertAlmostEqual(event["cost_estimate_usd"], 1.0)

    # -- present-but-unusable time_of_day_pricing is diagnosed, not silent --

    def test_present_but_unusable_time_of_day_pricing_emits_a_meter_error(self):
        # レビュー指摘3: a table that predates this feature (no
        # `time_of_day_pricing` key at all) and one that tried and got
        # the shape wrong must not be indistinguishable -- the latter
        # records a `meter.error` diagnostic (already surfaced in
        # `report`'s footer), the former does not.
        table = self._tod_table()
        del table["time_of_day_pricing"]["tz_offset"]
        self._ingest_one("2026-08-05T02:00:00.000Z", table=table)
        errors = read_meter_errors(self.home)
        stages = [e.get("stage") for e in errors]
        self.assertIn("price_table_time_of_day_pricing_unusable", stages)

    def test_table_without_any_time_of_day_pricing_key_does_not_emit_a_meter_error(self):
        write_transcript(self.projects_dir, "proj", "sess-no-tod-key", [
            assistant_line("sess-no-tod-key", "m1", model="deepseek-v4-pro", timestamp="2026-08-05T10:00:00.000Z"),
        ])
        result = run_ingest(self.home, self.projects_dir)  # real REPO_PRICE_DIR table: no time_of_day_pricing key
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(read_meter_errors(self.home), [])


class PriceTableFallbackWarningTests(OcwMeterTestCase):
    """計画書 DOC-2608081456孫3 §3 / 罠5: 該当する価格表が無い期間を黙らせない。"""

    def setUp(self):
        super().setUp()
        self.projects_dir = pathlib.Path(self.tmpdir.name) / "claude-projects"
        self.projects_dir.mkdir(parents=True, exist_ok=True)
        self.price_dir = pathlib.Path(self.tmpdir.name) / "prices-fallback"
        write_price_table(self.price_dir, "deepseek-2026-08-01.json", {
            "price_table_version": "deepseek-2026-08-01", "effective_date": "2026-08-01",
            "models": {"deepseek-v4-pro": {"cache_hit_in": 0.003625, "cache_miss_in": 0.435, "out": 0.87}},
        })

    def test_footer_warns_when_price_table_took_effect_after_the_message(self):
        # July message, only an August table exists -> fallback.
        write_transcript(self.projects_dir, "proj", "sess-july", [
            assistant_line("sess-july", "m1", model="deepseek-v4-pro", timestamp="2026-07-15T10:00:00.000Z"),
        ])
        result = run_report(self.home, self.projects_dir, args=["--json"], price_dir=self.price_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["price_table_fallback_count"], 1)
        self.assertIn("took effect AFTER their own message date", data["price_table"])

    def test_footer_does_not_warn_when_price_table_covers_the_message(self):
        # August message, August table applies as intended -> no fallback.
        write_transcript(self.projects_dir, "proj", "sess-aug", [
            assistant_line("sess-aug", "m1", model="deepseek-v4-pro", timestamp="2026-08-05T10:00:00.000Z"),
        ])
        result = run_report(self.home, self.projects_dir, args=["--json"], price_dir=self.price_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["price_table_fallback_count"], 0)
        self.assertNotIn("took effect AFTER", data["price_table"])

    def test_month_report_flags_price_table_effective_after_the_month(self):
        write_transcript(self.projects_dir, "proj", "sess-july2", [
            assistant_line("sess-july2", "m1", model="deepseek-v4-pro", timestamp="2026-07-15T10:00:00.000Z"),
        ])
        result = run_report(self.home, self.projects_dir, args=["--month", "2026-07", "--json"], price_dir=self.price_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        applied = data["cash_cost"]["price_tables_applied"]
        self.assertEqual(len(applied), 1)
        self.assertEqual(applied[0]["price_table_version"], "deepseek-2026-08-01")
        self.assertEqual(applied[0]["effective_date"], "2026-08-01")
        self.assertTrue(applied[0]["is_fallback"])

    def test_month_report_does_not_flag_price_table_covering_the_month(self):
        write_transcript(self.projects_dir, "proj", "sess-aug2", [
            assistant_line("sess-aug2", "m1", model="deepseek-v4-pro", timestamp="2026-08-05T10:00:00.000Z"),
        ])
        result = run_report(self.home, self.projects_dir, args=["--month", "2026-08", "--json"], price_dir=self.price_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        applied = data["cash_cost"]["price_tables_applied"]
        self.assertEqual(len(applied), 1)
        self.assertFalse(applied[0]["is_fallback"])

    def test_month_report_flags_a_same_month_fallback(self):
        # レビュー指摘2の回帰テスト: the sole price table is effective
        # 2026-08-15 -- LATER in the SAME month as the message it's
        # applied to (2026-08-05). Month-granularity comparison
        # (`"2026-08" > "2026-08"`) missed this; day-granularity
        # (reusing `_price_table_predates_message`) must catch it, and
        # must agree with the footer's own (day-granularity) verdict in
        # the same JSON response.
        price_dir = pathlib.Path(self.tmpdir.name) / "prices-same-month-fallback"
        write_price_table(price_dir, "deepseek-2026-08-15.json", {
            "price_table_version": "deepseek-2026-08-15", "effective_date": "2026-08-15",
            "models": {"deepseek-v4-pro": {"cache_hit_in": 0.003625, "cache_miss_in": 0.435, "out": 0.87}},
        })
        write_transcript(self.projects_dir, "proj", "sess-samemonth", [
            assistant_line("sess-samemonth", "m1", model="deepseek-v4-pro", timestamp="2026-08-05T10:00:00.000Z"),
        ])
        result = run_report(self.home, self.projects_dir, args=["--month", "2026-08", "--json"], price_dir=price_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        applied = data["cash_cost"]["price_tables_applied"]
        self.assertEqual(len(applied), 1)
        self.assertTrue(applied[0]["is_fallback"])
        # Must agree with the footer's own (independently computed) verdict.
        self.assertEqual(data["price_table_fallback_count"], 1)

    def test_month_report_text_output_shows_the_fallback_marker(self):
        # レビュー指摘6: only --json was ever asserted on for this view;
        # the text renderer builds its marker string independently
        # (bin/ocw-meter's _report_month_standalone) and could silently
        # diverge from the JSON without any test catching it.
        write_transcript(self.projects_dir, "proj", "sess-july3", [
            assistant_line("sess-july3", "m1", model="deepseek-v4-pro", timestamp="2026-07-15T10:00:00.000Z"),
        ])
        result = run_report(self.home, self.projects_dir, args=["--month", "2026-07"], price_dir=self.price_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("price_tables_applied:", result.stdout)
        self.assertIn("deepseek-2026-08-01 (effective 2026-08-01)", result.stdout)
        self.assertIn("フォールバック", result.stdout)

    def test_month_report_text_output_has_no_fallback_marker_when_covered(self):
        write_transcript(self.projects_dir, "proj", "sess-aug3", [
            assistant_line("sess-aug3", "m1", model="deepseek-v4-pro", timestamp="2026-08-05T10:00:00.000Z"),
        ])
        result = run_report(self.home, self.projects_dir, args=["--month", "2026-08"], price_dir=self.price_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("deepseek-2026-08-01 (effective 2026-08-01)", result.stdout)
        self.assertNotIn("フォールバック", result.stdout)


class ReportAutoIngestTests(OcwMeterTestCase):
    """計画書 DOC-2608081456孫2: `report` auto-runs `ingest` at the top of
    every view (DOC-2608021229-a:440 documented this from the start, but
    `cmd_report` never actually called it — 4 days / 11.4% of events
    silently missing on the real machine)."""

    def setUp(self):
        super().setUp()
        self.projects_dir = pathlib.Path(self.tmpdir.name) / "claude-projects"
        self.projects_dir.mkdir(parents=True, exist_ok=True)

    def test_report_auto_ingests_transcripts_without_an_explicit_ingest_call(self):
        write_transcript(self.projects_dir, "proj", "sess-auto", [assistant_line("sess-auto", "m1")])
        self.assertEqual(read_events(self.home), [])

        result = run_report(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        usage_events = [e for e in read_events(self.home) if e["event_type"] == "usage.message"]
        self.assertEqual(len(usage_events), 1)

    def test_no_ingest_flag_skips_the_automatic_ingest(self):
        write_transcript(self.projects_dir, "proj", "sess-skip", [assistant_line("sess-skip", "m1")])
        result = run_report(self.home, self.projects_dir, args=["--no-ingest"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(read_events(self.home), [])
        self.assertIn("ingest (this run): skipped (--no-ingest)", result.stdout)
        # PR #57 review round 2 finding "新規2": the "no events yet"
        # messages must not assert anything about whether ingest ran —
        # round 1's own fix for finding 1 made them unconditionally claim
        # "ingest already ran automatically", which is false right here
        # under --no-ingest. Whether it ran is the freshness footer's
        # `ingest (this run):` line's job alone (asserted above).
        self.assertNotIn("ingest already ran automatically", result.stdout)
        self.assertIn("no usage.message events found in transcripts", result.stdout)

        reconcile_result = run_report(self.home, self.projects_dir, args=["--reconcile", "--no-ingest"])
        self.assertEqual(reconcile_result.returncode, 0, reconcile_result.stderr)
        self.assertNotIn("ingest already ran automatically", reconcile_result.stdout)

    def test_invalid_month_fails_before_running_the_automatic_ingest(self):
        # PR #57 review round 1 finding 7: argument validation (a
        # malformed --month) used to run AFTER the automatic ingest call,
        # so a request that was always going to fail loud still wrote a
        # live ingest-cursor.json/events first.
        write_transcript(self.projects_dir, "proj", "sess-bad-month", [assistant_line("sess-bad-month", "m1")])
        result = run_report(self.home, self.projects_dir, args=["--reconcile", "--month", "2026-13"])
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.home / "state" / "ingest-cursor.json").exists())
        self.assertEqual(read_events(self.home), [])

    def test_auto_ingest_runs_for_every_report_view(self):
        # 計画書「1つでも漏れると、そのビューだけ古いデータを見る」: each
        # view gets its OWN isolated home/projects_dir so a prior view's
        # ingest can't accidentally satisfy this one's assertion.
        view_cases = [
            [], ["--phase"], ["--model"], ["--role"], ["--window"],
            ["--month", "2026-07"], ["--reconcile", "--month", "2026-07"],
        ]
        for i, view_args in enumerate(view_cases):
            with self.subTest(view=view_args):
                home = pathlib.Path(self.tmpdir.name) / f"view-home-{i}"
                projects_dir = pathlib.Path(self.tmpdir.name) / f"view-projects-{i}"
                projects_dir.mkdir()
                write_transcript(projects_dir, "proj", f"sess-view-{i}", [
                    assistant_line(f"sess-view-{i}", "m1", timestamp="2026-07-15T10:00:00.000Z"),
                ])
                result = run_report(home, projects_dir, args=view_args)
                self.assertEqual(result.returncode, 0, result.stderr)
                usage_events = [e for e in read_events(home) if e["event_type"] == "usage.message"]
                self.assertEqual(len(usage_events), 1, f"view {view_args} did not auto-ingest: {result.stdout}")

    def test_ingest_failure_does_not_crash_report_and_is_shown_in_the_footer(self):
        # An empty HOME makes claude_projects_dir() unable to resolve a
        # projects directory (and OCW_METER_CLAUDE_PROJECTS_DIR is
        # deliberately not passed) — perform_ingest's own "could not
        # determine" refusal, exercised without needing a git-worktree
        # storage root (report's own top-level worktree guard would
        # short-circuit before auto-ingest ever runs for that case).
        run_meter(["event", "run.start", "--idempotency-key", "k1"], self.home)
        result = run_meter(["report"], self.home, extra_env={"HOME": ""})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("total events:  1", result.stdout)
        self.assertIn("ingest (this run): failed: could not determine the Claude projects directory", result.stdout)

    def test_json_output_stays_pure_json_even_when_auto_ingest_runs(self):
        write_transcript(self.projects_dir, "proj", "sess-json", [assistant_line("sess-json", "m1")])
        result = run_report(self.home, self.projects_dir, args=["--json"])
        self.assertEqual(result.returncode, 0, result.stderr)
        summary = json.loads(result.stdout)  # raises if anything besides JSON hit stdout
        self.assertEqual(summary["total_events"], 1)

    def test_footer_shows_last_ingest_timestamp_after_a_successful_run(self):
        write_transcript(self.projects_dir, "proj", "sess-fresh", [assistant_line("sess-fresh", "m1")])
        result = run_report(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("last_ingest_at: unknown", result.stdout)
        cursor = json.loads((self.home / "state" / "ingest-cursor.json").read_text(encoding="utf-8"))
        self.assertIn("last_ingest_at", cursor)
        # The raw RFC3339 the footer's --json field (last_ingest_at_rfc3339)
        # must carry, unmodified, for a machine consumer (PR #57 review
        # round 1 finding 6) — round-trips through the text footer too.
        self.assertIn(f"last_ingest_at_rfc3339: {cursor['last_ingest_at']}", result.stdout)

    def test_old_format_ingest_cursor_without_last_ingest_at_shows_unknown(self):
        state_dir = self.home / "state"
        state_dir.mkdir(parents=True, exist_ok=True)
        (state_dir / "ingest-cursor.json").write_text(json.dumps({"files": {}}), encoding="utf-8")
        result = run_meter(["report", "--no-ingest"], self.home)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("last_ingest_at: unknown", result.stdout)
        self.assertIn("last_ingest_at_rfc3339: unknown", result.stdout)

    def test_freshness_warning_only_appears_past_the_staleness_threshold(self):
        # PR #57 review round 1 finding 4: the threshold comparison is
        # `>=` (inclusive — see ingest_freshness_footer's comment, chosen
        # because the plan's own wording "一定時間以上経っていたら" is
        # inclusive). This test cannot pin the literal single-instant
        # edge (age_seconds == INGEST_STALE_THRESHOLD_SECONDS exactly):
        # this is a black-box subprocess test built on real wall-clock
        # `datetime.now()`, and the round trip between writing the
        # fixture timestamp here and `ingest_freshness_footer` reading
        # "now" always adds strictly positive latency — so any nominal
        # age computed here always reads back slightly HIGHER once the
        # subprocess evaluates it, which makes `>` and `>=` behave
        # identically in practice (verified: reverting to `>` still
        # passes every case below). Matches this file's existing
        # precedent for other 24h-based staleness checks
        # (WorktreeRefusalPruningTests uses a 1h/25h margin, not an
        # exact-instant one, for the same reason).
        state_dir = self.home / "state"
        state_dir.mkdir(parents=True, exist_ok=True)

        def cursor_at_age(**age_kwargs):
            ts = (datetime.now(timezone.utc) - timedelta(**age_kwargs)).strftime("%Y-%m-%dT%H:%M:%S.000Z")
            (state_dir / "ingest-cursor.json").write_text(
                json.dumps({"files": {}, "last_ingest_at": ts}), encoding="utf-8",
            )
            return run_meter(["report", "--no-ingest"], self.home)

        fresh_result = cursor_at_age(minutes=5)
        self.assertEqual(fresh_result.returncode, 0, fresh_result.stderr)
        self.assertIn("ingest_freshness_warning: (none)", fresh_result.stdout)

        just_under_result = cursor_at_age(hours=23, minutes=59)
        self.assertEqual(just_under_result.returncode, 0, just_under_result.stderr)
        self.assertIn("ingest_freshness_warning: (none)", just_under_result.stdout)

        just_over_result = cursor_at_age(hours=24, minutes=1)
        self.assertEqual(just_over_result.returncode, 0, just_over_result.stderr)
        self.assertNotIn("ingest_freshness_warning: (none)", just_over_result.stdout)
        self.assertIn("経過しています", just_over_result.stdout)

        stale_result = cursor_at_age(hours=25)
        self.assertEqual(stale_result.returncode, 0, stale_result.stderr)
        self.assertNotIn("ingest_freshness_warning: (none)", stale_result.stdout)
        self.assertIn("経過しています", stale_result.stdout)

    def test_json_output_includes_freshness_footer_keys_for_every_view(self):
        # PR #57 review round 1 finding 3: `footer_freshness` is `**`-
        # expanded into 4 separate JSON summary dicts
        # (cmd_report/_print_grouped_report/_report_month_standalone/
        # _report_reconcile) — a dropped `**footer_freshness` in any ONE
        # of them would otherwise go undetected, since every other
        # existing test only checks the text footer's print lines.
        write_transcript(self.projects_dir, "proj", "sess-json-fresh", [
            assistant_line("sess-json-fresh", "m1", timestamp="2026-07-15T10:00:00.000Z"),
        ])
        freshness_keys = {"last_ingest_at", "last_ingest_at_rfc3339", "ingest_this_run", "ingest_freshness_warning"}
        view_cases = [
            [], ["--phase"], ["--model"], ["--role"], ["--window"],
            ["--month", "2026-07"], ["--reconcile", "--month", "2026-07"],
        ]
        for view_args in view_cases:
            with self.subTest(view=view_args):
                result = run_report(self.home, self.projects_dir, args=[*view_args, "--json"])
                self.assertEqual(result.returncode, 0, result.stderr)
                summary = json.loads(result.stdout)
                missing = freshness_keys - summary.keys()
                self.assertFalse(missing, f"view {view_args} --json is missing freshness keys: {missing}")


class SymlinkInvocationTests(OcwMeterTestCase):
    """ADR DOC-2608040229 §2.6: deploy.sh installs this script as a
    symlink (e.g. ~/bin/ocw-meter). `dirname` on an unresolved
    BASH_SOURCE[0] would then point at the SYMLINK's own directory, not
    where bin/prices/*.json actually lives, so `ingest` would silently
    find zero price tables (empty price_table_dir -> completeness
    "unknown" and cost_estimate_usd null, even for a model that IS
    priced in the real bin/prices/*.json). These tests invoke the
    script only through a symlink and deliberately do NOT set
    OCW_METER_PRICE_DIR, so a regression of the BASH_SOURCE[0]
    resolution shows up as a completeness/cost_estimate_usd mismatch
    rather than a hard failure."""

    def setUp(self):
        super().setUp()
        self.projects_dir = pathlib.Path(self.tmpdir.name) / "claude-projects"
        self.projects_dir.mkdir(parents=True, exist_ok=True)

    def _run_ingest_via(self, exe_path):
        env = dict(os.environ)
        env["OCW_METER_HOME"] = str(self.home)
        env["OCW_METER_CLAUDE_PROJECTS_DIR"] = str(self.projects_dir)
        env["OCW_METER_INGEST_USE_GH"] = "0"
        env.pop("OCW_METER_PRICE_DIR", None)
        for key in ("OCW_RUN_ID", "OCW_ROLE", "HERDR_WORKSPACE_ID", "HERDR_PANE_ID"):
            env.pop(key, None)
        return subprocess.run(
            [str(exe_path), "ingest"],
            cwd=str(REPO_ROOT),
            env=env,
            capture_output=True,
            text=True,
            timeout=60,
        )

    def test_ingest_resolves_price_dir_through_absolute_symlink(self):
        link_dir = pathlib.Path(self.tmpdir.name) / "bin-abs"
        link_dir.mkdir()
        link_path = link_dir / "ocw-meter"
        link_path.symlink_to(OCW_METER)

        write_transcript(self.projects_dir, "proj", "sess-symlink-abs", [
            assistant_line("sess-symlink-abs", "m1", model="deepseek-v4-pro",
                            input_tokens=1000, cache_read_input_tokens=2000, output_tokens=300),
        ])
        result = self._run_ingest_via(link_path)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = read_events(self.home)[0]
        self.assertEqual(event["price_table_version"], "deepseek-2026-08-01")
        self.assertEqual(event["cost_basis"], "estimated")
        self.assertEqual(event["completeness"], "complete")
        self.assertIsNotNone(event["cost_estimate_usd"])

    def test_ingest_resolves_price_dir_through_chained_relative_symlink(self):
        # Two hops, the first a RELATIVE target, to exercise the
        # resolution loop walking more than once and resolving a
        # relative link target against the directory of the link being
        # read, not the final destination's directory.
        hop1_dir = pathlib.Path(self.tmpdir.name) / "hop1"
        hop2_dir = pathlib.Path(self.tmpdir.name) / "hop2"
        hop1_dir.mkdir()
        hop2_dir.mkdir()
        hop1_link = hop1_dir / "ocw-meter"
        # `os.path.relpath` must be computed against hop1_dir's
        # symlink-resolved physical location, not its as-given path:
        # on macOS `$TMPDIR` sits under `/var/...`, itself a symlink to
        # `/private/var/...`, so the two differ by one path component.
        # The kernel resolves a relative symlink target against the
        # physical directory it lives in, so an unresolved hop1_dir
        # yields a target one `../` short and this link ends up
        # pointing nowhere.
        hop1_link.symlink_to(os.path.relpath(OCW_METER, hop1_dir.resolve()))
        hop2_link = hop2_dir / "ocw-meter"
        hop2_link.symlink_to(hop1_link)

        write_transcript(self.projects_dir, "proj", "sess-symlink-chain", [
            assistant_line("sess-symlink-chain", "m1", model="deepseek-v4-pro",
                            input_tokens=1000, cache_read_input_tokens=2000, output_tokens=300),
        ])
        result = self._run_ingest_via(hop2_link)
        self.assertEqual(result.returncode, 0, result.stderr)
        event = read_events(self.home)[0]
        self.assertEqual(event["price_table_version"], "deepseek-2026-08-01")
        self.assertEqual(event["completeness"], "complete")
        self.assertIsNotNone(event["cost_estimate_usd"])


class ReportReconcileTests(OcwMeterTestCase):
    def setUp(self):
        super().setUp()
        self.projects_dir = pathlib.Path(self.tmpdir.name) / "claude-projects"
        self.projects_dir.mkdir(parents=True, exist_ok=True)

    def _seed_deepseek_message(self, message_id="m1", timestamp="2026-07-15T10:00:00.000Z", **kwargs):
        write_transcript(self.projects_dir, "proj", f"sess-{message_id}", [
            assistant_line(f"sess-{message_id}", message_id, timestamp=timestamp, **kwargs),
        ])
        result = run_ingest(self.home, self.projects_dir)
        assert result.returncode == 0, result.stderr

    def test_reconcile_reports_tokens_cost_and_known_gaps(self):
        self._seed_deepseek_message(input_tokens=1000, cache_read_input_tokens=2000,
                                     cache_creation_input_tokens=0, output_tokens=300)
        result = run_meter(["report", "--reconcile", "--month", "2026-07", "--json"], self.home,
                            extra_env={"OCW_METER_CLAUDE_PROJECTS_DIR": str(self.projects_dir), "OCW_METER_INGEST_USE_GH": "0"})
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data["cost_basis"], "estimated — not an invoice")
        self.assertIn("known_gaps", data)
        self.assertIn("deepseek-v4-flash", data["known_gaps"])
        model = data["models"]["deepseek-v4-pro"]
        self.assertEqual(model["input_tokens"], 1000)
        self.assertEqual(model["cache_read_input_tokens"], 2000)
        self.assertEqual(model["output_tokens"], 300)
        self.assertIsNotNone(model["cost_estimate_usd"])
        self.assertIsNone(model["provider_total_tokens"])
        self.assertIsNone(model["coverage_ratio"])

    def test_reconcile_provider_total_computes_coverage_ratio(self):
        self._seed_deepseek_message(input_tokens=1000, cache_read_input_tokens=9000, output_tokens=0)
        result = run_meter(
            ["report", "--reconcile", "--month", "2026-07", "--provider-total", "deepseek-v4-pro=20000", "--json"],
            self.home,
            extra_env={"OCW_METER_CLAUDE_PROJECTS_DIR": str(self.projects_dir), "OCW_METER_INGEST_USE_GH": "0"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        model = json.loads(result.stdout)["models"]["deepseek-v4-pro"]
        self.assertEqual(model["provider_total_tokens"], 20000)
        self.assertAlmostEqual(model["coverage_ratio"], 10000 / 20000)

    def test_reconcile_provider_total_for_model_absent_from_transcript_still_shown(self):
        # PR #27 review round 1 finding 5: this is the exact "0%
        # coverage" case (plan §5.10 / DOC-2608021229 §2.2, deepseek-v4-flash)
        # the whole flag exists to surface — it must not be the one case
        # that silently disappears from the report.
        self._seed_deepseek_message()  # only deepseek-v4-pro exists in transcript
        result = run_meter(
            ["report", "--reconcile", "--month", "2026-07",
             "--provider-total", "deepseek-v4-flash=107000000", "--json"],
            self.home,
            extra_env={"OCW_METER_CLAUDE_PROJECTS_DIR": str(self.projects_dir), "OCW_METER_INGEST_USE_GH": "0"},
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        models = json.loads(result.stdout)["models"]
        self.assertIn("deepseek-v4-flash", models)
        flash = models["deepseek-v4-flash"]
        self.assertEqual(flash["messages"], 0)
        self.assertEqual(flash["transcript_total_tokens"], 0)
        self.assertEqual(flash["provider_total_tokens"], 107000000)
        self.assertEqual(flash["coverage_ratio"], 0.0)
        self.assertIsNone(flash["cost_estimate_usd"])

    def test_reconcile_rejects_malformed_month(self):
        # PR #27 review round 1 finding 6a (round 2 "持ち越し6a" extended
        # this to out-of-range month numbers, which the first fix's
        # digit-count-only regex still let through as a silent 0-result
        # match): report is the fail-loud half of this CLI (plan §10.1)
        # — a garbage --month must not silently aggregate a whole year
        # or silently match nothing.
        for bad_month in ("2026", "07-2026", "2026-13x", "not-a-month", "2026-13", "2026-00"):
            result = run_meter(["report", "--reconcile", "--month", bad_month], self.home)
            self.assertNotEqual(result.returncode, 0, f"--month {bad_month!r} should have been rejected")

    def test_reconcile_accepts_boundary_valid_months(self):
        for good_month in ("2026-01", "2026-12"):
            result = run_meter(["report", "--reconcile", "--month", good_month], self.home)
            self.assertEqual(result.returncode, 0, f"--month {good_month!r} should have been accepted")

    def test_reconcile_known_gaps_mentions_utc_month_boundary_caveat(self):
        # PR #27 review round 1 finding 6b (plan §17 R8): month
        # boundaries are UTC-fixed; the report must say so rather than
        # implying exact alignment with a provider's own (e.g. Beijing
        # time) monthly billing boundary.
        result = run_meter(["report", "--reconcile", "--month", "2026-07", "--json"], self.home)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("UTC", json.loads(result.stdout)["known_gaps"])

    def test_report_quarantine_counts_are_separated_from_ingest_transcript_quarantine(self):
        # PR #27 review round 1 finding 10.
        session_dir = self.projects_dir / "proj"
        session_dir.mkdir(parents=True)
        (session_dir / "sess-bad.jsonl").write_text(
            json.dumps(assistant_line("sess-bad", "m1"), ensure_ascii=False) + "\n"
            + "{not valid json\n",
            encoding="utf-8",
        )
        result = run_ingest(self.home, self.projects_dir)
        self.assertEqual(result.returncode, 0, result.stderr)
        report = run_meter(["report", "--json"], self.home)
        self.assertEqual(report.returncode, 0, report.stderr)
        data = json.loads(report.stdout)
        self.assertEqual(data["transcript_lines_quarantined"], 1)
        self.assertEqual(data["quarantined_lines"], 0)

    def test_reconcile_with_month_works_outside_any_git_repo(self):
        # PR #57 review round 2 finding "新規1": moving the repo-
        # resolution-needed check earlier (round 1 finding 7, to run
        # before the automatic-ingest side effect) accidentally exposed
        # `--reconcile --month` to it for the first time — previously
        # `_report_reconcile`'s early return made the check dead code on
        # this path. `_report_reconcile` never takes (or needs) a `repo`
        # argument at all, so this combination must keep working from
        # outside any git repo, exactly like it always has (this is a
        # documented workflow — docs/reference/DOC-2608021229-b_...).
        no_git_dir = pathlib.Path(self.tmpdir.name) / "not-a-git-repo-reconcile"
        no_git_dir.mkdir()
        result = run_meter(["report", "--reconcile", "--month", "2026-07"], self.home, cwd=no_git_dir)
        self.assertEqual(result.returncode, 0, result.stderr)


CLAUDE_STATUSLINE_SAMPLE = {
    "session_id": "756f06ff-28b8-412d-92db-cbd9dcece939",
    "cwd": "/tmp",
    "model": {"id": "claude-opus-5", "display_name": "Opus 5"},
    "cost": {"total_cost_usd": 4.56},
    "rate_limits": {
        "five_hour": {"used_percentage": 37, "resets_at": 99999999999},
        "seven_day": {"used_percentage": 12, "resets_at": 99999999999},
    },
    "context_window": {
        "total_input_tokens": 24000, "total_output_tokens": 100,
        "context_window_size": 100000, "used_percentage": 24,
    },
}


class SnapshotQuotaBasicsTests(OcwMeterTestCase):
    """孫4: `ocw-meter snapshot-quota`. See docs/planning/DOC-2608021229-a_..._
    計画.md §8.5 / 孫4プロンプト and DOC-2608021229 §2.1/§8."""

    def test_empty_stdin_prints_blank_and_exits_zero(self):
        result = run_snapshot_quota("", self.home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "\n")
        self.assertEqual(read_events(self.home), [])

    def test_malformed_json_prints_blank_and_exits_zero(self):
        result = run_snapshot_quota("not json {{{", self.home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "\n")
        self.assertEqual(read_events(self.home), [])

    def test_json_array_not_object_is_treated_as_no_data(self):
        result = run_snapshot_quota("[1, 2, 3]", self.home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "\n")
        self.assertEqual(read_events(self.home), [])

    def test_huge_input_does_not_crash(self):
        # Defends against a pathologically large payload (plan §1: this
        # must never hang or crash the caller's status bar).
        huge = json.dumps({"junk": "x" * 5_000_000})
        result = run_snapshot_quota(huge, self.home, timeout=30)
        self.assertEqual(result.returncode, 0)

    def test_claude_session_prints_display_and_records_complete_sample(self):
        result = run_snapshot_quota(json.dumps(CLAUDE_STATUSLINE_SAMPLE), self.home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "5h:37% 7d:12% ctx:24%")

        events = read_events(self.home)
        self.assertEqual(len(events), 1)
        event = events[0]
        self.assertEqual(event["event_type"], "quota.sample")
        self.assertEqual(event["completeness"], "complete")
        self.assertEqual(event["source"], "statusline")
        self.assertEqual(event["plan_source"], "statusline")
        self.assertEqual(event["provider"], "anthropic")
        self.assertEqual(event["model"], "claude-opus-5")
        self.assertEqual(event["session_id"], "756f06ff-28b8-412d-92db-cbd9dcece939")
        self.assertEqual(event["five_hour_used_pct"], 37)
        self.assertEqual(event["five_hour_resets_at"], 99999999999)
        self.assertEqual(event["seven_day_used_pct"], 12)
        self.assertEqual(event["window_id"], "99999999999")
        self.assertEqual(event["context_used_pct"], 24)
        # Regression guard for the to_number() float-truncation bug found
        # while implementing this: build_envelope() previously turned an
        # already-float 4.56 into 4 because int(4.56) succeeds instead
        # of raising. Must survive as a real float, not silently
        # truncated with no completeness downgrade to show for it.
        self.assertEqual(event["session_cost_usd"], 4.56)
        self.assertIsNone(event["raw_ref"])

    def test_deepseek_session_missing_rate_limits_is_completeness_unknown(self):
        # T10 (quota half) / DOC-2608021229 §2.1: every claude-ds session (58/58
        # real samples) — a documented, expected shape, not an error.
        obj = {
            "session_id": "ds-session",
            "cwd": "/tmp",
            "model": {"id": "deepseek-v4-pro[1m]"},
            "cost": {"total_cost_usd": 0.02},
        }
        result = run_snapshot_quota(json.dumps(obj), self.home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")  # no rate_limits, no context_window -> nothing to show

        event = read_events(self.home)[0]
        self.assertEqual(event["completeness"], "unknown")
        self.assertIsNone(event["five_hour_used_pct"])
        self.assertIsNone(event["five_hour_resets_at"])
        self.assertIsNone(event["window_id"])
        self.assertEqual(event["provider"], "deepseek")
        self.assertEqual(event["model"], "deepseek-v4-pro")  # [1m] suffix stripped
        self.assertEqual(event["session_cost_usd"], 0.02)

    def test_context_used_pct_falls_back_to_token_ratio_when_null(self):
        # DOC-2608021229 §2.1: used_percentage was null in 7/66 real samples;
        # total_input_tokens/context_window_size were "常に取得可能".
        # DOC-2608021229 §8 instruction 7 draws a line between the RECORDED
        # value (fallback estimate is fine) and the DISPLAYED string
        # (hide `ctx` entirely when the raw used_percentage is null,
        # rather than show a number the instruction says to omit —
        # round-1 review finding: these were conflated pre-fix).
        obj = {
            "rate_limits": {"five_hour": {"used_percentage": 5, "resets_at": 99999999999}},
            "context_window": {"total_input_tokens": 25000, "context_window_size": 100000, "used_percentage": None},
        }
        result = run_snapshot_quota(json.dumps(obj), self.home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "5h:5%")
        event = read_events(self.home)[0]
        self.assertEqual(event["context_used_pct"], 25.0)

    def test_context_used_pct_displayed_when_raw_value_present(self):
        obj = {
            "rate_limits": {"five_hour": {"used_percentage": 5, "resets_at": 99999999999}},
            "context_window": {"used_percentage": 25},
        }
        result = run_snapshot_quota(json.dumps(obj), self.home)
        self.assertEqual(result.stdout.strip(), "5h:5% ctx:25%")

    def test_context_used_pct_null_when_no_fallback_possible(self):
        obj = {"rate_limits": {"five_hour": {"used_percentage": 5, "resets_at": 99999999999}}}
        result = run_snapshot_quota(json.dumps(obj), self.home)
        self.assertEqual(result.stdout.strip(), "5h:5%")
        event = read_events(self.home)[0]
        self.assertIsNone(event["context_used_pct"])

    def test_unknown_top_level_and_nested_keys_do_not_break_parsing(self):
        # T11 forward-compat half: a future statusLine schema version
        # adding fields must not break this at all.
        obj = dict(CLAUDE_STATUSLINE_SAMPLE)
        obj["some_future_field"] = {"nested": ["stuff", 1, 2]}
        obj["rate_limits"] = dict(obj["rate_limits"])
        obj["rate_limits"]["some_new_window"] = {"used_percentage": 99}
        result = run_snapshot_quota(json.dumps(obj), self.home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "5h:37% 7d:12% ctx:24%")
        self.assertEqual(read_events(self.home)[0]["completeness"], "complete")

    def test_known_keys_missing_does_not_crash(self):
        # T11 "known key disappears" half: a future statusLine schema
        # version could drop rate_limits/context_window/cost entirely
        # without warning (they are all documented as optional/absent
        # in some session types already — DOC-2608021229 §2.1).
        result = run_snapshot_quota(json.dumps({"session_id": "x"}), self.home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "")
        event = read_events(self.home)[0]
        self.assertEqual(event["completeness"], "unknown")

    def test_raw_capture_is_off_by_default(self):
        run_snapshot_quota(json.dumps(CLAUDE_STATUSLINE_SAMPLE), self.home)
        self.assertFalse((self.home / "raw").exists())
        self.assertIsNone(read_events(self.home)[0]["raw_ref"])

    def test_raw_capture_redacts_secrets_when_enabled(self):
        # T17.
        obj = dict(CLAUDE_STATUSLINE_SAMPLE)
        obj["api_key"] = "sk-should-not-survive-1234567890"
        result = run_snapshot_quota(json.dumps(obj), self.home, extra_env={"OCW_METER_RAW": "1"})
        self.assertEqual(result.returncode, 0)

        raw_files = list((self.home / "raw").glob("*/*.json"))
        self.assertEqual(len(raw_files), 1)
        raw_text = raw_files[0].read_text(encoding="utf-8")
        self.assertNotIn("sk-should-not-survive-1234567890", raw_text)
        self.assertIn("[REDACTED]", raw_text)

        event = read_events(self.home)[0]
        self.assertEqual(event["raw_ref"], str(raw_files[0]))

    def test_git_worktree_home_refuses_write_but_still_prints_display(self):
        # 孫1 (計画書 DOC-2608081456【4】): this test deliberately does NOT
        # pass its own extra_env={"HOME": ...} — it exists specifically to
        # exercise run_snapshot_quota's DEFAULT isolation (see
        # _default_home_for above). Before that fix, the meter.error
        # fallback this triggers landed in this developer's real
        # ~/.local/state/ocw-meter every single test run.
        real_home_before = real_ocw_meter_home_contamination_fingerprint()
        repo_dir = pathlib.Path(self.tmpdir.name) / "repo"
        subprocess.run(["git", "init", "-q", str(repo_dir)], check=True)
        bad_home = repo_dir / "ocw-meter-home"
        result = run_snapshot_quota(json.dumps(CLAUDE_STATUSLINE_SAMPLE), bad_home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "5h:37% 7d:12% ctx:24%")
        self.assertIn("resolves inside a Git worktree", result.stderr)
        self.assertFalse((bad_home / "events").exists())

        # The refusal's meter.error self-diagnostic must land under the
        # isolated $HOME the helper substituted for THIS call (derived
        # from bad_home — round-1 review finding 9's per-call
        # isolation), not the real one.
        fallback_root = pathlib.Path(_default_home_for(bad_home)) / ".local" / "state" / "ocw-meter"
        diagnostics = read_meter_errors(fallback_root)
        self.assertTrue(
            any(d["stage"] == "storage_home_inside_git_worktree" for d in diagnostics),
            "expected the worktree-refusal meter.error under the isolated $HOME fallback",
        )
        self.assertEqual(real_ocw_meter_home_contamination_fingerprint(), real_home_before)


class HomeIsolationContractTests(OcwMeterTestCase):
    """孫1 (計画書 DOC-2608081456【4】): a contract test for run_meter/
    run_snapshot_quota themselves, not for ocw-meter — any test in this
    file that forgets to override $HOME must still never touch the
    developer's real ~/.local/state/ocw-meter, because the helpers
    default it to a throwaway directory unless a test opts out."""

    def test_run_snapshot_quota_never_touches_the_real_home_without_an_explicit_override(self):
        before = real_ocw_meter_home_contamination_fingerprint()
        repo_dir = pathlib.Path(self.tmpdir.name) / "repo-for-home-isolation-contract"
        subprocess.run(["git", "init", "-q", str(repo_dir)], check=True)
        bad_home = repo_dir / "ocw-meter-home"
        # Triggers the one code path (worktree-refusal fallback) that
        # ever reads $HOME at all — anything less would pass trivially.
        result = run_snapshot_quota(json.dumps(CLAUDE_STATUSLINE_SAMPLE), bad_home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(real_ocw_meter_home_contamination_fingerprint(), before)

    def test_run_meter_never_touches_the_real_home_without_an_explicit_override(self):
        before = real_ocw_meter_home_contamination_fingerprint()
        repo_dir = pathlib.Path(self.tmpdir.name) / "repo-for-home-isolation-contract-2"
        subprocess.run(["git", "init", "-q", str(repo_dir)], check=True)
        bad_home = repo_dir / "ocw-meter-home"
        result = run_meter(["event", "run.start", "--idempotency-key", "k1"], bad_home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(real_ocw_meter_home_contamination_fingerprint(), before)


def _iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{dt.microsecond // 1000:03d}Z"


def _write_worktree_refusal_state(home, entries):
    # The refusal cache lives at the DEFAULT storage root
    # ($HOME/.local/state/ocw-meter), not at $HOME itself — mirrors
    # default_storage_root() in bin/ocw-meter.
    state_dir = pathlib.Path(home) / ".local" / "state" / "ocw-meter" / "state"
    state_dir.mkdir(parents=True, exist_ok=True)
    path = state_dir / "quota-worktree-refusal.json"
    path.write_text(json.dumps(entries), encoding="utf-8")
    return path


class WorktreeRefusalPruningTests(OcwMeterTestCase):
    """孫1 (計画書 DOC-2608081456【6】): quota-worktree-refusal.json used to
    only drop entries older than QUOTA_SESSION_STATE_MAX_AGE_SECONDS (24h)
    at the moment a NEW refusal was recorded — once refusals stopped
    happening, stale entries sat in the file forever (37 of them, all
    >24h old, found on this machine's real store). Pruning must now also
    happen on every READ, so a normal (non-refusing) `snapshot-quota`
    call cleans them up too."""

    def _fresh_default_home(self):
        # The refusal cache always lives at the DEFAULT ($HOME-derived)
        # root, never at OCW_METER_HOME itself (see
        # load_and_prune_worktree_refusal_state's docstring in
        # bin/ocw-meter) — this must be a directory distinct from
        # self.home (OCW_METER_HOME) for that caching code path to
        # engage at all.
        default_home = pathlib.Path(self.tmpdir.name) / "fake-home-for-pruning"
        default_home.mkdir()
        return default_home

    def _call(self, default_home):
        return run_snapshot_quota(
            json.dumps(CLAUDE_STATUSLINE_SAMPLE),
            self.home,
            extra_env={"HOME": str(default_home), "OCW_METER_QUOTA_INTERVAL": "0"},
        )

    def test_stale_entries_are_pruned_when_ocw_meter_home_is_unset_matching_the_default_root(self):
        # round-1 review finding 1: THE single most common real
        # configuration is OCW_METER_HOME unset entirely, in which case
        # bin/ocw-meter's own bash wrapper defaults it to
        # `$HOME/.local/state/ocw-meter` — i.e. `storage_root() ==
        # default_storage_root()`. An earlier version of the read-time
        # pruning fix additionally required the two to DIFFER before
        # even loading (and therefore pruning) the file, which silently
        # skipped pruning in exactly this configuration — the one this
        # machine's real 37 stale entries needed. This reproduces that
        # configuration directly (OCW_METER_HOME left unset, unlike
        # every other test in this class, which always sets it via
        # run_snapshot_quota's `home` argument).
        home = pathlib.Path(self.tmpdir.name) / "home-for-unset-ocw-meter-home"
        home.mkdir()
        old_ts = _iso(datetime.now(timezone.utc) - timedelta(hours=25))
        state_path = _write_worktree_refusal_state(home, {"/some/old/bad/root": old_ts})

        env = dict(os.environ)
        env.pop("OCW_METER_HOME", None)
        env["HOME"] = str(home)
        env["OCW_METER_QUOTA_INTERVAL"] = "0"
        for key in ("OCW_RUN_ID", "OCW_ROLE", "HERDR_WORKSPACE_ID", "HERDR_PANE_ID"):
            env.pop(key, None)
        result = subprocess.run(
            [str(OCW_METER), "snapshot-quota"],
            cwd=str(REPO_ROOT),
            env=env,
            input=json.dumps(CLAUDE_STATUSLINE_SAMPLE),
            capture_output=True,
            text=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(state_path.read_text(encoding="utf-8")), {})

    def test_stale_entries_are_pruned_on_a_normal_non_refusing_call(self):
        default_home = self._fresh_default_home()
        old_ts = _iso(datetime.now(timezone.utc) - timedelta(hours=25))
        state_path = _write_worktree_refusal_state(default_home, {"/some/old/bad/root": old_ts})

        result = self._call(default_home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(json.loads(state_path.read_text(encoding="utf-8")), {})

    def test_entries_within_24h_are_kept(self):
        default_home = self._fresh_default_home()
        recent_ts = _iso(datetime.now(timezone.utc) - timedelta(hours=1))
        state_path = _write_worktree_refusal_state(default_home, {"/some/recent/bad/root": recent_ts})

        result = self._call(default_home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(
            json.loads(state_path.read_text(encoding="utf-8")),
            {"/some/recent/bad/root": recent_ts},
        )

    def test_stale_and_fresh_entries_mixed_only_stale_ones_are_dropped(self):
        default_home = self._fresh_default_home()
        old_ts = _iso(datetime.now(timezone.utc) - timedelta(hours=25))
        recent_ts = _iso(datetime.now(timezone.utc) - timedelta(hours=1))
        state_path = _write_worktree_refusal_state(
            default_home, {"/old/root": old_ts, "/recent/root": recent_ts}
        )

        result = self._call(default_home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(
            json.loads(state_path.read_text(encoding="utf-8")),
            {"/recent/root": recent_ts},
        )

    def test_mtime_is_unchanged_when_nothing_needs_pruning(self):
        # No wasted write-back on the common case: snapshot-quota is
        # called on essentially every statusLine tick (~60s throttle), so
        # a machine with zero or all-fresh refusal entries must not pay
        # for a rewrite on every single call.
        default_home = self._fresh_default_home()
        recent_ts = _iso(datetime.now(timezone.utc) - timedelta(hours=1))
        state_path = _write_worktree_refusal_state(default_home, {"/recent/root": recent_ts})
        mtime_before = state_path.stat().st_mtime_ns

        result = self._call(default_home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(state_path.stat().st_mtime_ns, mtime_before)


def _write_meter_errors(home, event_dicts):
    state_dir = pathlib.Path(home) / "state"
    state_dir.mkdir(parents=True, exist_ok=True)
    path = state_dir / "meter-errors.jsonl"
    path.write_text("".join(json.dumps(d, ensure_ascii=False) + "\n" for d in event_dicts), encoding="utf-8")
    return path


def _write_refusal_state_at_default_root(ocw_meter_home, entries):
    # round-1 review finding 2: quota-worktree-refusal.json is ALWAYS at
    # the DEFAULT ($HOME-derived) root, never under a custom
    # OCW_METER_HOME — same as WorktreeRefusalPruningTests'
    # _write_worktree_refusal_state above. run_meter (used without an
    # explicit extra_env={"HOME": ...} override here) defaults $HOME to
    # `_default_home_for(ocw_meter_home)`, so that is where
    # prune-diagnostics will actually look.
    default_home = _default_home_for(ocw_meter_home)
    state_dir = pathlib.Path(default_home) / ".local" / "state" / "ocw-meter" / "state"
    state_dir.mkdir(parents=True, exist_ok=True)
    path = state_dir / "quota-worktree-refusal.json"
    path.write_text(json.dumps(entries), encoding="utf-8")
    return path


class PruneDiagnosticsTests(OcwMeterTestCase):
    """孫1 (計画書 DOC-2608081456【4】の後始末): `ocw-meter prune-diagnostics`
    cleans up state/meter-errors.jsonl and state/quota-worktree-
    refusal.json only, dry-run by default."""

    def _seed(self):
        old_ts = _iso(datetime.now(timezone.utc) - timedelta(days=31))
        new_ts = _iso(datetime.now(timezone.utc) - timedelta(days=1))
        errors_path = _write_meter_errors(
            self.home,
            [
                {
                    "schema_version": 1, "event_type": "meter.error",
                    "idempotency_key": "meter-error:storage_home_inside_git_worktree:old",
                    "ts": old_ts, "stage": "storage_home_inside_git_worktree", "completeness": "unknown",
                },
                {
                    "schema_version": 1, "event_type": "meter.error",
                    "idempotency_key": "meter-error:storage_home_inside_git_worktree:new",
                    "ts": new_ts, "stage": "storage_home_inside_git_worktree", "completeness": "unknown",
                },
            ],
        )
        refusal_path = _write_refusal_state_at_default_root(
            self.home, {"/old/root": old_ts, "/new/root": new_ts}
        )
        return old_ts, new_ts, errors_path, refusal_path

    def test_dry_run_default_removes_nothing_but_reports_counts(self):
        old_ts, new_ts, errors_path, refusal_path = self._seed()

        result = run_meter(["prune-diagnostics"], self.home)
        self.assertEqual(result.returncode, 0)
        self.assertIn("dry-run", result.stdout)
        self.assertIn("would remove 1, kept 1", result.stdout)

        self.assertEqual(len(errors_path.read_text(encoding="utf-8").splitlines()), 2)
        self.assertEqual(len(json.loads(refusal_path.read_text(encoding="utf-8"))), 2)

    def test_apply_removes_only_old_entries(self):
        old_ts, new_ts, errors_path, refusal_path = self._seed()

        result = run_meter(["prune-diagnostics", "--apply"], self.home)
        self.assertEqual(result.returncode, 0)
        self.assertIn("applied", result.stdout)
        self.assertIn("removed 1, kept 1", result.stdout)

        remaining_errors = [
            json.loads(line) for line in errors_path.read_text(encoding="utf-8").splitlines() if line.strip()
        ]
        self.assertEqual(len(remaining_errors), 1)
        self.assertEqual(remaining_errors[0]["ts"], new_ts)

        self.assertEqual(json.loads(refusal_path.read_text(encoding="utf-8")), {"/new/root": new_ts})

    def test_older_than_overrides_the_default_retention(self):
        old_ts, new_ts, errors_path, refusal_path = self._seed()
        # new_ts is 1 day old; --older-than 0 makes even that eligible.
        result = run_meter(["prune-diagnostics", "--older-than", "0", "--apply"], self.home)
        self.assertEqual(result.returncode, 0)
        # Every entry was eligible, so the emptied meter-errors.jsonl is
        # removed outright rather than left behind as a 0-byte file.
        self.assertFalse(errors_path.exists())
        self.assertEqual(json.loads(refusal_path.read_text(encoding="utf-8")), {})

    def test_events_directory_is_never_touched(self):
        old_ts, _new_ts, _errors_path, _refusal_path = self._seed()
        # A real event, well outside the retention window, in events/ —
        # must survive byte-for-byte. Deleting observation events is
        # `prune`'s territory (deliberately unimplemented); this
        # subcommand must never touch events/*.jsonl.
        run_meter(["event", "run.start", "--idempotency-key", "k1", "--ts", old_ts], self.home)
        events_dir = self.home / "events"
        before = {p.name: p.read_bytes() for p in events_dir.glob("*.jsonl")}
        self.assertTrue(before)

        result = run_meter(["prune-diagnostics", "--apply"], self.home)
        self.assertEqual(result.returncode, 0)

        after = {p.name: p.read_bytes() for p in events_dir.glob("*.jsonl")}
        self.assertEqual(before, after)

    def test_missing_target_files_report_zero_and_exit_zero(self):
        result = run_meter(["prune-diagnostics"], self.home)
        self.assertEqual(result.returncode, 0)
        self.assertIn("would remove 0, kept 0", result.stdout)

        result_apply = run_meter(["prune-diagnostics", "--apply"], self.home)
        self.assertEqual(result_apply.returncode, 0)
        self.assertIn("removed 0, kept 0", result_apply.stdout)

    def test_corrupt_refusal_json_is_reported_as_corrupt_not_silently_treated_as_empty(self):
        # round-1 review finding 8: silently treating a corrupt file as
        # {} (load_json_state_file's normal, correct behavior for every
        # OTHER caller) let this subcommand report "kept 0" for a file
        # that, in fact, was still sitting there unreadable. The dry-run
        # output must say so, and --apply must repair it (replace with a
        # valid empty state), not just avoid crashing.
        default_home = _default_home_for(self.home)
        refusal_path = pathlib.Path(default_home) / ".local" / "state" / "ocw-meter" / "state" / "quota-worktree-refusal.json"
        refusal_path.parent.mkdir(parents=True, exist_ok=True)
        refusal_path.write_text("{not valid json", encoding="utf-8")

        result = run_meter(["prune-diagnostics"], self.home)
        self.assertEqual(result.returncode, 0)
        self.assertIn("could not parse", result.stdout)
        # Untouched in dry-run.
        self.assertEqual(refusal_path.read_text(encoding="utf-8"), "{not valid json")

        result_apply = run_meter(["prune-diagnostics", "--apply"], self.home)
        self.assertEqual(result_apply.returncode, 0)
        self.assertIn("replaced with an empty state", result_apply.stdout)
        self.assertEqual(json.loads(refusal_path.read_text(encoding="utf-8")), {})

    def test_meter_errors_under_the_default_root_fallback_are_also_cleaned(self):
        # round-1 review finding 2: emit_meter_error falls back to the
        # DEFAULT ($HOME-derived) root whenever OCW_METER_HOME itself is
        # refused for resolving inside a Git worktree — this subcommand
        # must reach diagnostics stored there too, not only under
        # OCW_METER_HOME (which, in this exact scenario, cannot hold
        # ANY of ocw-meter's own files at all).
        repo_dir = pathlib.Path(self.tmpdir.name) / "repo-for-default-root-fallback"
        subprocess.run(["git", "init", "-q", str(repo_dir)], check=True)
        bad_home = repo_dir / "ocw-meter-home"
        fake_home = pathlib.Path(self.tmpdir.name) / "fake-home-for-default-root-fallback"
        fake_home.mkdir()
        old_ts = _iso(datetime.now(timezone.utc) - timedelta(days=31))
        errors_path = _write_meter_errors(
            fake_home / ".local" / "state" / "ocw-meter",
            [
                {
                    "schema_version": 1, "event_type": "meter.error",
                    "idempotency_key": "meter-error:storage_home_inside_git_worktree:old",
                    "ts": old_ts, "stage": "storage_home_inside_git_worktree", "completeness": "unknown",
                },
            ],
        )

        result = run_meter(["prune-diagnostics", "--apply"], bad_home, extra_env={"HOME": str(fake_home)})
        self.assertEqual(result.returncode, 0)
        self.assertFalse(errors_path.exists())

    def test_trailing_slash_ocw_meter_home_does_not_double_count_meter_errors(self):
        # round-2 review finding 2: storage_root() and
        # default_storage_root() were deduped by bare string equality —
        # a trailing slash on OCW_METER_HOME made the SAME real
        # directory look like two distinct roots, so meter-errors.jsonl
        # got read (and reported) twice, and dry-run/--apply disagreed.
        fake_home = pathlib.Path(self.tmpdir.name) / "fake-home-for-trailing-slash"
        fake_home.mkdir()
        default_root = fake_home / ".local" / "state" / "ocw-meter"
        old_ts = _iso(datetime.now(timezone.utc) - timedelta(days=31))
        errors_path = _write_meter_errors(
            default_root,
            [
                {
                    "schema_version": 1, "event_type": "meter.error",
                    "idempotency_key": "meter-error:storage_home_inside_git_worktree:old",
                    "ts": old_ts, "stage": "storage_home_inside_git_worktree", "completeness": "unknown",
                },
            ],
        )
        # Same real directory as default_storage_root() would compute,
        # spelled with a trailing slash as OCW_METER_HOME.
        ocw_meter_home_with_slash = str(default_root) + "/"

        result = run_meter(["prune-diagnostics"], ocw_meter_home_with_slash, extra_env={"HOME": str(fake_home)})
        self.assertEqual(result.returncode, 0)
        self.assertIn("would remove 1, kept 0", result.stdout)

        result_apply = run_meter(
            ["prune-diagnostics", "--apply"], ocw_meter_home_with_slash, extra_env={"HOME": str(fake_home)}
        )
        self.assertEqual(result_apply.returncode, 0)
        self.assertIn("removed 1, kept 0", result_apply.stdout)
        # The only entry was dropped, so the file is removed outright
        # (same convention as an emptied meter-errors.jsonl elsewhere) —
        # if it had instead been double-counted, this would still exist
        # with the second, incorrectly-kept "copy" of the entry.
        self.assertFalse(errors_path.exists())

    def test_per_root_breakdown_shown_when_both_roots_have_meter_errors(self):
        # round-2 review finding 4: once meter-errors.jsonl could live
        # under either root, the aggregate count alone no longer says
        # which physical file(s) actually get rewritten.
        fake_home = pathlib.Path(self.tmpdir.name) / "fake-home-for-breakdown"
        fake_home.mkdir()
        default_root = fake_home / ".local" / "state" / "ocw-meter"
        old_ts = _iso(datetime.now(timezone.utc) - timedelta(days=31))
        _write_meter_errors(
            default_root,
            [
                {
                    "schema_version": 1, "event_type": "meter.error",
                    "idempotency_key": "meter-error:storage_home_inside_git_worktree:default",
                    "ts": old_ts, "stage": "storage_home_inside_git_worktree", "completeness": "unknown",
                },
            ],
        )
        _write_meter_errors(
            self.home,
            [
                {
                    "schema_version": 1, "event_type": "meter.error",
                    "idempotency_key": "meter-error:write_event_lock_timeout:custom",
                    "ts": old_ts, "stage": "write_event_lock_timeout", "completeness": "unknown",
                },
            ],
        )

        result = run_meter(["prune-diagnostics"], self.home, extra_env={"HOME": str(fake_home)})
        self.assertEqual(result.returncode, 0)
        self.assertIn("would remove 2, kept 0", result.stdout)
        self.assertIn(str(pathlib.Path(default_root).resolve()), result.stdout)
        self.assertIn(str(pathlib.Path(self.home).resolve()), result.stdout)

    def test_negative_older_than_is_rejected(self):
        result = run_meter(["prune-diagnostics", "--older-than", "-1"], self.home)
        self.assertNotEqual(result.returncode, 0)

    def test_non_numeric_older_than_is_rejected(self):
        result = run_meter(["prune-diagnostics", "--older-than", "not-a-number"], self.home)
        self.assertNotEqual(result.returncode, 0)


class SnapshotQuotaThrottleTests(OcwMeterTestCase):
    def test_second_call_within_interval_is_throttled(self):
        r1 = run_snapshot_quota(json.dumps(CLAUDE_STATUSLINE_SAMPLE), self.home)
        r2 = run_snapshot_quota(json.dumps(CLAUDE_STATUSLINE_SAMPLE), self.home)
        self.assertEqual(r1.returncode, 0)
        self.assertEqual(r2.returncode, 0)
        # Both calls still print a display string — throttling only
        # skips the storage write, never the stdout contract.
        self.assertEqual(r1.stdout.strip(), "5h:37% 7d:12% ctx:24%")
        self.assertEqual(r2.stdout.strip(), "5h:37% 7d:12% ctx:24%")
        self.assertEqual(len(read_events(self.home)), 1)

    def test_interval_zero_disables_throttling(self):
        for _ in range(3):
            run_snapshot_quota(json.dumps(CLAUDE_STATUSLINE_SAMPLE), self.home, extra_env={"OCW_METER_QUOTA_INTERVAL": "0"})
        self.assertEqual(len(read_events(self.home)), 3)

    def test_non_numeric_interval_falls_back_to_default_not_zero(self):
        run_snapshot_quota(json.dumps(CLAUDE_STATUSLINE_SAMPLE), self.home, extra_env={"OCW_METER_QUOTA_INTERVAL": "not-a-number"})
        run_snapshot_quota(json.dumps(CLAUDE_STATUSLINE_SAMPLE), self.home, extra_env={"OCW_METER_QUOTA_INTERVAL": "not-a-number"})
        self.assertEqual(len(read_events(self.home)), 1)


class SnapshotQuotaWindowTests(OcwMeterTestCase):
    """T09: 5-hour window reset/staleness handling (plan §8.5, DOC-2608021229
    §2.1/§8 instruction 4)."""

    def test_stale_resets_at_is_marked_partial_with_null_window_id(self):
        # DOC-2608021229 §2.1: 3/8 real samples had an already-past resets_at.
        obj = {"rate_limits": {"five_hour": {"used_percentage": 50, "resets_at": 1}}}
        result = run_snapshot_quota(json.dumps(obj), self.home)
        self.assertEqual(result.returncode, 0)
        event = read_events(self.home)[0]
        self.assertEqual(event["completeness"], "partial")
        self.assertIsNone(event["window_id"])
        # Raw value is still recorded (plan §7.4: 捏造しない — don't
        # erase what was actually reported, just don't trust it as a
        # window identifier).
        self.assertEqual(event["five_hour_resets_at"], 1)

    def test_used_pct_decrease_within_same_window_is_flagged_partial(self):
        far_future = 99999999999
        obj1 = {"rate_limits": {"five_hour": {"used_percentage": 50, "resets_at": far_future}}}
        obj2 = {"rate_limits": {"five_hour": {"used_percentage": 30, "resets_at": far_future}}}
        r1 = run_snapshot_quota(json.dumps(obj1), self.home, extra_env={"OCW_METER_QUOTA_INTERVAL": "0"})
        r2 = run_snapshot_quota(json.dumps(obj2), self.home, extra_env={"OCW_METER_QUOTA_INTERVAL": "0"})
        self.assertEqual(r1.returncode, 0)
        self.assertEqual(r2.returncode, 0)
        self.assertIn("decreased within the same window_id", r2.stderr)

        events = read_events(self.home)
        self.assertEqual(len(events), 2)
        self.assertEqual(events[0]["completeness"], "complete")
        self.assertEqual(events[1]["completeness"], "partial")
        # Still the truthfully-reported value, just flagged as anomalous.
        self.assertEqual(events[1]["five_hour_used_pct"], 30)

    def test_used_pct_increase_within_same_window_stays_complete(self):
        far_future = 99999999999
        obj1 = {"rate_limits": {"five_hour": {"used_percentage": 10, "resets_at": far_future}}}
        obj2 = {"rate_limits": {"five_hour": {"used_percentage": 20, "resets_at": far_future}}}
        run_snapshot_quota(json.dumps(obj1), self.home, extra_env={"OCW_METER_QUOTA_INTERVAL": "0"})
        run_snapshot_quota(json.dumps(obj2), self.home, extra_env={"OCW_METER_QUOTA_INTERVAL": "0"})
        events = read_events(self.home)
        self.assertEqual([e["completeness"] for e in events], ["complete", "complete"])

    def test_different_window_id_after_reset_does_not_trigger_anomaly(self):
        obj1 = {"rate_limits": {"five_hour": {"used_percentage": 90, "resets_at": 99999999999}}}
        obj2 = {"rate_limits": {"five_hour": {"used_percentage": 5, "resets_at": 99999999998}}}
        run_snapshot_quota(json.dumps(obj1), self.home, extra_env={"OCW_METER_QUOTA_INTERVAL": "0"})
        result = run_snapshot_quota(json.dumps(obj2), self.home, extra_env={"OCW_METER_QUOTA_INTERVAL": "0"})
        self.assertNotIn("decreased within the same window_id", result.stderr)
        events = read_events(self.home)
        self.assertEqual(events[1]["completeness"], "complete")


class ReportFiveHourWindowCompletionTests(OcwMeterTestCase):
    """T09 (report half) / 孫4プロンプト §2: 「PRが同一5時間窓で完走でき
    たか」— report --pr <n>."""

    def _seed_pr(self, pr_number, start_ts, end_ts):
        run_meter(
            ["event", "phase.start", "--idempotency-key", f"p{pr_number}-start",
             "--phase", "implement", "--pr-number", str(pr_number), "--ts", start_ts],
            self.home,
        )
        run_meter(
            ["event", "phase.end", "--idempotency-key", f"p{pr_number}-end",
             "--phase", "done", "--pr-number", str(pr_number), "--ts", end_ts],
            self.home,
        )

    def _seed_quota_sample(self, key, window_id, ts):
        run_meter(
            ["event", "quota.sample", "--idempotency-key", key,
             "--plan-source", "statusline", "--window-id", window_id, "--ts", ts],
            self.home,
        )

    def test_yes_when_all_in_range_samples_share_one_window_id(self):
        self._seed_pr(42, "2026-08-01T10:00:00.000Z", "2026-08-01T12:00:00.000Z")
        self._seed_quota_sample("q1", "winA", "2026-08-01T10:30:00.000Z")
        self._seed_quota_sample("q2", "winA", "2026-08-01T11:30:00.000Z")
        result = run_meter(["report", "--pr", "42", "--json"], self.home)
        data = json.loads(result.stdout)
        self.assertEqual(data["five_hour_window_completion"], "yes")
        self.assertEqual(data["five_hour_window_ids_seen"], ["winA"])

    def test_no_when_in_range_samples_span_two_window_ids(self):
        self._seed_pr(42, "2026-08-01T10:00:00.000Z", "2026-08-01T12:00:00.000Z")
        self._seed_quota_sample("q1", "winA", "2026-08-01T10:30:00.000Z")
        self._seed_quota_sample("q2", "winB", "2026-08-01T11:30:00.000Z")
        result = run_meter(["report", "--pr", "42", "--json"], self.home)
        data = json.loads(result.stdout)
        self.assertEqual(data["five_hour_window_completion"], "no")
        self.assertEqual(sorted(data["five_hour_window_ids_seen"]), ["winA", "winB"])

    def test_unknown_when_no_quota_samples_in_range(self):
        self._seed_pr(7, "2026-08-01T10:00:00.000Z", "2026-08-01T12:00:00.000Z")
        result = run_meter(["report", "--pr", "7", "--json"], self.home)
        data = json.loads(result.stdout)
        self.assertEqual(data["five_hour_window_completion"], "unknown")
        self.assertEqual(data["five_hour_window_ids_seen"], [])

    def test_out_of_range_and_windowless_samples_are_excluded(self):
        self._seed_pr(42, "2026-08-01T10:00:00.000Z", "2026-08-01T12:00:00.000Z")
        self._seed_quota_sample("q1", "winA", "2026-08-01T10:30:00.000Z")
        # Outside the PR's own time range — must not count as a second window.
        self._seed_quota_sample("q2", "winB", "2026-08-01T15:00:00.000Z")
        # In range but window_id-less (e.g. a stale/DeepSeek sample) — must
        # not count as evidence either way.
        run_meter(
            ["event", "quota.sample", "--idempotency-key", "q3", "--plan-source", "statusline",
             "--completeness", "unknown", "--ts", "2026-08-01T11:00:00.000Z"],
            self.home,
        )
        result = run_meter(["report", "--pr", "42", "--json"], self.home)
        data = json.loads(result.stdout)
        self.assertEqual(data["five_hour_window_completion"], "yes")
        self.assertEqual(data["five_hour_window_ids_seen"], ["winA"])

    def test_no_pr_filter_omits_window_completion_fields(self):
        result = run_meter(["report", "--json"], self.home)
        data = json.loads(result.stdout)
        self.assertNotIn("five_hour_window_completion", data)
        self.assertNotIn("five_hour_window_ids_seen", data)


# ── 孫5: grouped report views (--phase/--model/--role/--window/--month) ──

class ReportGroupedViewsTests(OcwMeterTestCase):
    """docs/planning/DOC-2608021229-a_..._計画.md 孫5プロンプト §1."""

    def _seed_full_pr(self, pr_number, run_id):
        run_meter(["event", "run.start", "--idempotency-key", f"{run_id}-start",
                   "--run-id", run_id, "--base-ref", "master", "--command", "claude",
                   "--role", "implementer", "--ts", "2026-08-01T09:00:00.000Z"], self.home)
        run_meter(["event", "phase.start", "--idempotency-key", f"{run_id}-p1s",
                   "--run-id", run_id, "--phase", "pr_create", "--round", "1",
                   "--role", "implementer", "--pr-number", str(pr_number),
                   "--ts", "2026-08-01T09:05:00.000Z"], self.home)
        run_meter(["event", "phase.end", "--idempotency-key", f"{run_id}-p1e",
                   "--run-id", run_id, "--phase", "pr_create", "--round", "1",
                   "--role", "implementer", "--pr-number", str(pr_number),
                   "--ts", "2026-08-01T09:10:00.000Z"], self.home)
        run_meter(["bind-pr", "--run", run_id, "--pr", str(pr_number)], self.home)
        run_meter(["event", "review.round", "--idempotency-key", f"{run_id}-rv1",
                   "--run-id", run_id, "--round", "1", "--verdict", "approved",
                   "--findings-count", "0", "--role", "reviewer", "--pr-number", str(pr_number),
                   "--ts", "2026-08-01T09:30:00.000Z"], self.home)
        run_meter(["event", "phase.end", "--idempotency-key", f"{run_id}-done",
                   "--run-id", run_id, "--phase", "done", "--outcome", "success", "--round", "1",
                   "--role", "implementer", "--pr-number", str(pr_number),
                   "--ts", "2026-08-01T09:35:00.000Z"], self.home)
        run_meter(["event", "quota.sample", "--idempotency-key", f"{run_id}-q1",
                   "--plan-source", "statusline", "--window-id", f"win-{run_id}",
                   "--five-hour-used-pct", "20", "--pr-number", str(pr_number),
                   "--ts", "2026-08-01T09:12:00.000Z"], self.home)
        run_meter(["event", "usage.message", "--idempotency-key", f"{run_id}-u1",
                   "--run-id", run_id, "--message-id", f"{run_id}-m1",
                   "--model", "deepseek-v4-pro", "--provider", "deepseek",
                   "--input-tokens", "1000", "--cache-read-input-tokens", "500",
                   "--cache-creation-input-tokens", "0", "--output-tokens", "200",
                   "--cost-basis", "estimated", "--cost-estimate-usd", "0.01",
                   "--price-table-version", "deepseek-2026-08-01", "--role", "implementer",
                   "--pr-number", str(pr_number), "--ts", "2026-08-01T09:06:00.000Z"], self.home)

    # -- empty storage: every new view must not fail (T20) --

    def test_phase_model_role_window_month_on_empty_storage_do_not_fail(self):
        for view_args in (["--phase"], ["--model"], ["--role"], ["--window"], ["--month"]):
            result = run_meter(["report", *view_args], self.home)
            self.assertEqual(result.returncode, 0, f"{view_args} failed: {result.stderr}")
            self.assertIn("coverage:", result.stdout)
            self.assertIn("completeness:", result.stdout)
            self.assertIn("quarantined:", result.stdout)

            result_json = run_meter(["report", *view_args, "--json"], self.home)
            self.assertEqual(result_json.returncode, 0)
            data = json.loads(result_json.stdout)
            for field in ("coverage", "completeness", "quarantined_lines", "price_table", "cost_basis"):
                self.assertIn(field, data, f"{view_args} --json missing {field!r}")

    # -- --model --

    def test_model_view_groups_by_provider_and_model(self):
        self._seed_full_pr(1, "run-model-1")
        data = json.loads(run_meter(["report", "--model", "--json"], self.home).stdout)
        row = data["by_model"]["deepseek/deepseek-v4-pro"]
        self.assertEqual(row["messages"], 1)
        self.assertEqual(row["input_tokens"], 1000)
        self.assertEqual(row["cache_read_input_tokens"], 500)
        self.assertAlmostEqual(row["cost_estimate_usd"], 0.01)

    # -- --role --

    def test_role_view_counts_total_events_and_usage_tokens(self):
        self._seed_full_pr(2, "run-role-1")
        data = json.loads(run_meter(["report", "--role", "--json"], self.home).stdout)
        self.assertEqual(data["by_role"]["implementer"]["messages"], 1)
        self.assertGreaterEqual(data["by_role"]["implementer"]["total_events"], 1)
        self.assertEqual(data["by_role"]["reviewer"]["messages"], 0)
        self.assertGreaterEqual(data["by_role"]["reviewer"]["total_events"], 1)

    # -- --window --

    def test_window_view_groups_quota_samples_and_links_pr_directly(self):
        self._seed_full_pr(3, "run-window-1")
        data = json.loads(run_meter(["report", "--window", "--json"], self.home).stdout)
        row = data["by_window"]["win-run-window-1"]
        self.assertEqual(row["samples"], 1)
        self.assertEqual(row["five_hour_used_pct_max"], 20)
        self.assertEqual(row["prs_direct_link"], [3])
        self.assertIsNone(row["blocked_seconds"])

    # -- --phase --

    def test_phase_view_pairs_phase_start_end_and_attributes_tokens_by_time_range(self):
        self._seed_full_pr(4, "run-phase-1")
        data = json.loads(run_meter(["report", "--phase", "--json"], self.home).stdout)
        pr_create = data["by_phase"]["pr_create"]
        # usage.message at 09:06:00 falls inside pr_create's [09:05, 09:10)
        # window (seeded above), so it must be attributed there, not to
        # `(unassigned)` or to `review_request`/`done`.
        self.assertEqual(pr_create["messages"], 1)
        self.assertAlmostEqual(pr_create["total_duration_seconds"], 300.0)
        self.assertEqual(pr_create["window_count"], 1)
        # `done`'s phase.end in _seed_full_pr has no matching phase.start
        # (pr-review-loop never emits one for `done` — see
        # build_phase_windows' docstring), so it must not appear as a
        # guessed/zero-duration window at all.
        self.assertNotIn("done", data["by_phase"])

    def test_phase_view_usage_with_unknown_run_id_is_unassigned_not_guessed(self):
        # A usage.message with no run_id (e.g. ingest couldn't resolve
        # one) must not be silently attributed to any phase window.
        run_meter(["event", "phase.start", "--idempotency-key", "u-p-s", "--run-id", "run-orphan",
                   "--phase", "fix", "--round", "1", "--ts", "2026-08-01T10:00:00.000Z"], self.home)
        run_meter(["event", "phase.end", "--idempotency-key", "u-p-e", "--run-id", "run-orphan",
                   "--phase", "fix", "--round", "1", "--ts", "2026-08-01T10:05:00.000Z"], self.home)
        run_meter(["event", "usage.message", "--idempotency-key", "u-orphan", "--message-id", "m-orphan",
                   "--model", "deepseek-v4-pro", "--cost-basis", "estimated",
                   "--ts", "2026-08-01T10:02:00.000Z"], self.home)
        data = json.loads(run_meter(["report", "--phase", "--json"], self.home).stdout)
        self.assertEqual(data["by_phase"]["(unassigned)"]["messages"], 1)
        self.assertEqual(data["by_phase"]["fix"]["messages"], 0)

    # -- regression: round-1 finding 1 — phase-view key collision --

    def test_phase_view_null_phase_window_and_unassigned_tokens_do_not_collide(self):
        # Round-1 finding 1: when a phase window has `phase: null` (a
        # paired phase.start/phase.end where neither carries --phase →
        # build_phase_windows assigns phase=None from e.get("phase"))
        # AND unassigned tokens exist, both use `phase or "(unassigned)"`
        # as the output key but the intermediate dicts (durations keyed
        # by raw phase=None, tokens keyed by "(unassigned)") collide when
        # iterated — the second write silently overwrote the first.
        # Regression: both duration AND token metrics must survive.
        # -- Trigger the null-phase window: paired start+end, no --phase --
        run_meter(["event", "phase.start", "--idempotency-key", "col-pair-s",
                   "--run-id", "run-colid", "--round", "1",
                   "--ts", "2026-08-01T11:00:00.000Z"], self.home)
        run_meter(["event", "phase.end", "--idempotency-key", "col-pair-e",
                   "--run-id", "run-colid", "--round", "1",
                   "--ts", "2026-08-01T11:10:00.000Z"], self.home)
        # -- Usage whose run_id never matches any phase window → (unassigned) --
        run_meter(["event", "usage.message", "--idempotency-key", "col-u1",
                   "--message-id", "col-m1", "--model", "deepseek-v4-pro",
                   "--provider", "deepseek", "--input-tokens", "100",
                   "--cache-read-input-tokens", "0", "--output-tokens", "10",
                   "--cost-basis", "estimated", "--run-id", "run-other",
                   "--ts", "2026-08-01T12:00:00.000Z"], self.home)
        data = json.loads(run_meter(["report", "--phase", "--json"], self.home).stdout)
        # (unassigned) tokens must be present AND have their token counts.
        # With the bug, the duration row (None→"(unassigned)") overwrites
        # the token row, leaving messages=0.
        self.assertIn("(unassigned)", data["by_phase"])
        self.assertEqual(data["by_phase"]["(unassigned)"]["messages"], 1)
        self.assertEqual(data["by_phase"]["(unassigned)"]["input_tokens"], 100)
        # The null-phase window must also contribute its duration metrics
        # (same output key, not silently dropped).
        self.assertGreater(data["by_phase"]["(unassigned)"]["window_count"], 0)
        self.assertIsNotNone(data["by_phase"]["(unassigned)"]["total_duration_seconds"])

    # -- regression: round-1 finding 2 + round-2 finding 9 — window repo scoping --

    def test_window_view_excludes_prs_from_other_repos_with_explicit_repo_flag(self):
        # prs_direct_link AND prs_time_overlap must both be repo-scoped.
        # Use DIFFERENT PR numbers across repos — same number would be
        # deduplicated by the set() and hide the cross-repo contamination.
        self._seed_full_pr(7, "run-window-repo")
        other_repo = "someone/other-repo"
        # Different PR number (99), different repo — same window_id so it
        # lands in the same window bucket as PR 7 above.
        run_meter(["event", "quota.sample", "--idempotency-key", "win-other-q1",
                   "--plan-source", "statusline", "--window-id", "win-run-window-repo",
                   "--five-hour-used-pct", "30", "--pr-number", "99",
                   "--repo", other_repo,
                   "--ts", "2026-08-01T09:15:00.000Z"], self.home)
        # Also seed a usage.message from the other repo (for prs_time_overlap)
        run_meter(["event", "usage.message", "--idempotency-key", "win-other-u1",
                   "--message-id", "win-other-m1", "--model", "deepseek-v4-pro",
                   "--provider", "deepseek", "--input-tokens", "50",
                   "--cache-read-input-tokens", "0", "--output-tokens", "5",
                   "--cost-basis", "estimated", "--pr-number", "99",
                   "--repo", other_repo,
                   "--ts", "2026-08-01T09:15:00.000Z"], self.home)
        data = json.loads(run_meter(["report", "--window", "--repo", "manemone/dotfiles",
                                      "--json"], self.home).stdout)
        row = data["by_window"]["win-run-window-repo"]
        # Only our repo's PR 7 must appear; cross-repo PR 99 must NOT leak in
        self.assertEqual(row["prs_direct_link"], [7])
        self.assertEqual(row["prs_time_overlap"], [7])
        # needs_repo (round-2 finding 10) requires --window to resolve a
        # repo just like --pr: from outside a git repo, bare `--window`
        # now fails loud; from inside one, the repo is auto-resolved.
        # The explicit `--repo` flag tested here confirms the scoping is
        # correct when the flag IS given.

    def test_window_view_without_repo_fails_loud_outside_git_repo(self):
        # Round-2 finding 10: --window also needs repo resolution (just
        # like --pr) — otherwise the repo-is-None guard silently disables
        # all scoping and returns cross-contaminated data with exit 0.
        import pathlib
        no_git_dir = pathlib.Path(self.tmpdir.name) / "not-a-git-repo-window"
        no_git_dir.mkdir()
        result = run_meter(["report", "--window"], self.home, cwd=no_git_dir)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not resolve a repo", result.stderr)

    # -- --pr combined with a grouped view scopes to that PR --

    def test_model_view_combined_with_pr_filter_scopes_to_that_pr(self):
        self._seed_full_pr(5, "run-scope-a")
        self._seed_full_pr(6, "run-scope-b")
        data = json.loads(run_meter(["report", "--model", "--pr", "5", "--json"], self.home).stdout)
        self.assertEqual(data["filter_pr"], 5)
        self.assertEqual(data["by_model"]["deepseek/deepseek-v4-pro"]["messages"], 1)

    # -- cross-repo PR-number collision (round-1 review finding 1) --

    def test_pr_filter_excludes_a_same_numbered_pr_in_a_different_repo(self):
        # The store is shared across every repo ocw-meter is ever
        # pointed at (plan §9.1). `pr_number` alone is only unique
        # WITHIN a repo, so a same-numbered PR in a completely
        # different repo must never leak into this repo's --pr report.
        self._seed_full_pr(999, "run-thisrepo")
        run_meter(["event", "usage.message", "--idempotency-key", "other-repo-u1",
                   "--message-id", "other-repo-m1", "--repo", "someone/other-repo",
                   "--model", "deepseek-v4-pro", "--cost-basis", "estimated",
                   "--cost-estimate-usd", "999.0", "--pr-number", "999",
                   "--input-tokens", "1", "--cache-read-input-tokens", "0",
                   "--cache-creation-input-tokens", "0", "--output-tokens", "1",
                   "--ts", "2026-08-01T09:07:00.000Z"], self.home)
        data = json.loads(run_meter(["report", "--pr", "999", "--json"], self.home).stdout)
        # Only the same-repo usage.message (cost 0.01, seeded by
        # _seed_full_pr) counts; the other-repo $999.0 message must be
        # excluded entirely.
        self.assertAlmostEqual(data["pr_detail"]["cash_cost_usd"], 0.01)

    def test_pr_filter_excludes_repo_null_events_from_direct_pr_number_match(self):
        # An event with repo:null (e.g. `ingest` couldn't resolve a repo
        # slug for that message's cwd — DOC-2608021229-c §2.4/§4's documented
        # run_id-resolution gap has the same root cause) must not be
        # guessed into belonging to the caller's own repo; that would
        # silently reopen the exact cross-repo contamination class this
        # fix closes. `--repo ""` is normalized to `null` (empty string
        # -> null, same as every other envelope field).
        run_meter(["event", "usage.message", "--idempotency-key", "norepo-u1",
                   "--message-id", "norepo-m1", "--model", "deepseek-v4-pro",
                   "--cost-basis", "estimated", "--cost-estimate-usd", "5.0",
                   "--pr-number", "1000", "--repo", "",
                   "--input-tokens", "1", "--cache-read-input-tokens", "0",
                   "--cache-creation-input-tokens", "0", "--output-tokens", "1",
                   "--ts", "2026-08-01T09:07:00.000Z"], self.home)
        events = read_events(self.home)
        self.assertIsNone(next(e for e in events if e["idempotency_key"] == "norepo-u1")["repo"])
        data = json.loads(run_meter(["report", "--pr", "1000", "--json"], self.home).stdout)
        self.assertIsNone(data["pr_detail"]["cash_cost_usd"])

    # -- round-2 review finding 10: git_repo_slug() == None must fail loud, not flip scope --

    def test_pr_filter_fails_loud_when_repo_cannot_be_resolved(self):
        # A tempdir with no .git at all -> `git remote get-url origin`
        # fails -> git_repo_slug() returns None. Previously this flipped
        # `events_for_pr`'s repo scoping into matching ONLY repo:null
        # events (the exact opposite of what round-1's fix intended),
        # silently resurrecting cross-repo contamination with zero
        # legitimate events surviving. `report` (the fail-loud half of
        # this CLI) must refuse instead.
        self._seed_full_pr(50, "run-norepo-check")
        no_git_dir = pathlib.Path(self.tmpdir.name) / "not-a-git-repo"
        no_git_dir.mkdir()
        result = run_meter(["report", "--pr", "50"], self.home, cwd=no_git_dir)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--repo", result.stderr)

    def test_standalone_month_fails_loud_when_repo_cannot_be_resolved(self):
        # report --month also calls events_for_pr (via
        # report_month_process_efficiency) once per approved PR, so it
        # needs the same guard.
        no_git_dir = pathlib.Path(self.tmpdir.name) / "not-a-git-repo-month"
        no_git_dir.mkdir()
        result = run_meter(["report", "--month", "2026-08"], self.home, cwd=no_git_dir)
        self.assertNotEqual(result.returncode, 0)

    def test_pr_filter_explicit_repo_flag_works_outside_any_git_repo(self):
        # The escape hatch: --repo <owner>/<name> lets `report --pr`
        # run from anywhere, as long as the caller states which repo's
        # PR numbering they mean.
        self._seed_full_pr(51, "run-explicit-repo")
        no_git_dir = pathlib.Path(self.tmpdir.name) / "not-a-git-repo-2"
        no_git_dir.mkdir()
        # _seed_full_pr's events were written from inside REPO_ROOT, so
        # their `repo` field is REPO_ROOT's own git remote slug.
        real_repo = json.loads(
            run_meter(["report", "--pr", "51", "--json"], self.home).stdout
        )["repo"]
        result = run_meter(
            ["report", "--pr", "51", "--repo", real_repo, "--json"], self.home, cwd=no_git_dir,
        )
        self.assertEqual(result.returncode, 0)
        data = json.loads(result.stdout)
        self.assertEqual(data["repo"], real_repo)
        self.assertEqual(data["total_events"], 8)

    # -- round-3 review finding 14: --repo validation + unused-flag guard --

    def test_repo_flag_rejects_a_value_without_a_slash(self):
        # A plausible typo (missing "owner/") must not silently match
        # zero events with exit 0 — the same "garbage filter, plausible
        # zero result" failure mode --month's 01-12 validation exists to
        # prevent.
        result = run_meter(["report", "--pr", "1", "--repo", "dotfiles"], self.home)
        self.assertNotEqual(result.returncode, 0)

    def test_repo_flag_rejects_empty_owner_or_name(self):
        for bad in ("/dotfiles", "owner/", "owner/name/extra"):
            result = run_meter(["report", "--pr", "1", "--repo", bad], self.home)
            self.assertNotEqual(result.returncode, 0, f"--repo {bad!r} should have been rejected")

    def test_repo_flag_without_pr_or_month_is_rejected(self):
        # --repo only ever matters on paths that call events_for_pr
        # (--pr, or standalone --month); anywhere else it would be
        # silently accepted and ignored, same failure mode as --pr
        # being silently ignored by --month/--reconcile (finding 2).
        result = run_meter(["report", "--model", "--repo", "owner/bogus"], self.home)
        self.assertNotEqual(result.returncode, 0)

    def test_repo_flag_without_pr_or_month_is_rejected_even_for_bare_report(self):
        result = run_meter(["report", "--repo", "owner/bogus"], self.home)
        self.assertNotEqual(result.returncode, 0)

    def test_repo_flag_is_accepted_with_standalone_month(self):
        result = run_meter(["report", "--month", "2026-08", "--repo", "owner/name"], self.home)
        self.assertEqual(result.returncode, 0)

    # -- round-2 review finding 11: cross-repo review.round leaking into --month --

    def test_month_process_efficiency_excludes_other_repo_approved_prs(self):
        run_meter(["event", "review.round", "--idempotency-key", "other-repo-approval",
                   "--repo", "someone/other-repo", "--pr-number", "777", "--round", "1",
                   "--verdict", "approved", "--findings-count", "0",
                   "--ts", "2026-08-05T09:00:00.000Z"], self.home)
        data = json.loads(run_meter(["report", "--month", "2026-08", "--json"], self.home).stdout)
        self.assertEqual(data["process_efficiency"]["approved_pr_count"], 0)
        self.assertNotIn(777, [p["pr_number"] for p in data["process_efficiency"]["per_pr"]])

    # -- --pr detail additions (round list / human intervention / final result / cash cost) --

    def test_pr_detail_includes_rounds_final_result_and_cash_cost(self):
        self._seed_full_pr(7, "run-detail-1")
        data = json.loads(run_meter(["report", "--pr", "7", "--json"], self.home).stdout)
        detail = data["pr_detail"]
        self.assertEqual(detail["review_round_count"], 1)
        self.assertEqual(detail["review_rounds"][0]["verdict"], "approved")
        self.assertEqual(detail["final_result"], "success")
        self.assertEqual(detail["human_intervention_count"], 0)
        self.assertAlmostEqual(detail["cash_cost_usd"], 0.01)

    def test_pr_detail_counts_human_intervention(self):
        self._seed_full_pr(8, "run-detail-2")
        run_meter(["event", "human.intervention", "--idempotency-key", "hi-1", "--run-id", "run-detail-2",
                   "--reason", "review-blocked-condition", "--pr-number", "8",
                   "--ts", "2026-08-01T09:20:00.000Z"], self.home)
        data = json.loads(run_meter(["report", "--pr", "8", "--json"], self.home).stdout)
        self.assertEqual(data["pr_detail"]["human_intervention_count"], 1)
        self.assertEqual(data["pr_detail"]["human_intervention_reasons"], ["review-blocked-condition"])

    # -- mutual exclusivity --

    def test_reconcile_cannot_combine_with_grouped_view(self):
        result = run_meter(["report", "--reconcile", "--phase"], self.home)
        self.assertNotEqual(result.returncode, 0)

    def test_standalone_month_cannot_combine_with_grouped_view(self):
        result = run_meter(["report", "--month", "2026-08", "--model"], self.home)
        self.assertNotEqual(result.returncode, 0)

    def test_two_different_grouped_views_cannot_be_combined(self):
        # Round-1 self-review finding: --phase --model used to silently
        # take the LAST flag (view got overwritten) instead of erroring
        # — exactly the "garbage-but-plausible-looking output" failure
        # mode `report` (the fail-loud half of this CLI) exists to
        # prevent for --month/--reconcile already.
        result = run_meter(["report", "--phase", "--model"], self.home)
        self.assertNotEqual(result.returncode, 0)

    def test_repeating_the_same_grouped_view_flag_is_fine(self):
        result = run_meter(["report", "--phase", "--phase"], self.home)
        self.assertEqual(result.returncode, 0)

    # -- round-1 review finding 2: --pr silently ignored by --month/--reconcile --

    def test_pr_cannot_combine_with_standalone_month(self):
        result = run_meter(["report", "--month", "2026-08", "--pr", "5"], self.home)
        self.assertNotEqual(result.returncode, 0)

    def test_pr_cannot_combine_with_reconcile(self):
        result = run_meter(["report", "--reconcile", "--pr", "5"], self.home)
        self.assertNotEqual(result.returncode, 0)

    # -- round-1 review finding 3/4: duration_seconds semantics + 5h quota in --pr --

    def test_pr_detail_duration_seconds_is_null_without_an_approval(self):
        # A run with no review.round event at all (never reviewed yet).
        run_meter(["event", "run.start", "--idempotency-key", "run-bare-start", "--run-id", "run-bare",
                   "--ts", "2026-08-01T09:00:00.000Z"], self.home)
        run_meter(["bind-pr", "--run", "run-bare", "--pr", "12"], self.home)
        run_meter(["event", "usage.message", "--idempotency-key", "run-bare-u1", "--run-id", "run-bare",
                   "--message-id", "run-bare-m1", "--model", "deepseek-v4-pro", "--cost-basis", "estimated",
                   "--cost-estimate-usd", "0.02", "--pr-number", "12",
                   "--input-tokens", "1", "--cache-read-input-tokens", "0",
                   "--cache-creation-input-tokens", "0", "--output-tokens", "1",
                   "--ts", "2026-08-01T09:05:00.000Z"], self.home)
        data = json.loads(run_meter(["report", "--pr", "12", "--json"], self.home).stdout)
        self.assertIsNone(data["pr_detail"]["duration_seconds"])
        self.assertIsNotNone(data["pr_detail"]["total_span_seconds"])

    def test_pr_detail_duration_seconds_measures_time_to_approval_not_full_span(self):
        self._seed_full_pr(13, "run-approved-then-more")
        # _seed_full_pr's approval round.round is at 09:30:00Z, but the
        # PR's overall span extends to the usage.message at 09:06:00Z
        # .. review.round at 09:30:00Z .. phase.end(done) at 09:35:00Z.
        # Add an event AFTER the approval to prove duration_seconds
        # does NOT grow with it (only total_span_seconds should).
        run_meter(["event", "quota.sample", "--idempotency-key", "run-approved-then-more-late-q",
                   "--run-id", "run-approved-then-more", "--plan-source", "statusline",
                   "--pr-number", "13", "--ts", "2026-08-01T12:00:00.000Z"], self.home)
        data = json.loads(run_meter(["report", "--pr", "13", "--json"], self.home).stdout)
        detail = data["pr_detail"]
        # approval at 09:30:00, earliest event (run.start) at 09:00:00 -> 1800s to approval.
        self.assertAlmostEqual(detail["duration_seconds"], 1800.0)
        # total span now reaches the 12:00:00 event -> much larger.
        self.assertGreater(detail["total_span_seconds"], detail["duration_seconds"])

    def test_pr_detail_includes_five_hour_quota_consumption(self):
        self._seed_full_pr(14, "run-quota-detail")
        data = json.loads(run_meter(["report", "--pr", "14", "--json"], self.home).stdout)
        # _seed_full_pr's quota.sample has five_hour_used_pct=20.
        self.assertEqual(data["pr_detail"]["five_hour_used_pct_max"], 20)


class ReportMonthStandaloneTests(OcwMeterTestCase):
    """孫5プロンプト §1 --month (NOT --reconcile): cash cost / capacity
    cost / process efficiency."""

    def test_cash_and_capacity_cost_are_kept_in_separate_keys(self):
        run_meter(["event", "usage.message", "--idempotency-key", "u1", "--message-id", "m1",
                   "--model", "deepseek-v4-pro", "--cost-basis", "estimated", "--cost-estimate-usd", "1.5",
                   "--input-tokens", "10", "--cache-read-input-tokens", "0",
                   "--cache-creation-input-tokens", "0", "--output-tokens", "5",
                   "--ts", "2026-08-05T10:00:00.000Z"], self.home)
        run_meter(["event", "usage.message", "--idempotency-key", "u2", "--message-id", "m2",
                   "--model", "claude-opus-5", "--cost-basis", "subscription",
                   "--input-tokens", "10", "--cache-read-input-tokens", "0",
                   "--cache-creation-input-tokens", "0", "--output-tokens", "5",
                   "--ts", "2026-08-05T10:05:00.000Z"], self.home)
        data = json.loads(run_meter(["report", "--month", "2026-08", "--json"], self.home).stdout)
        self.assertAlmostEqual(data["cash_cost"]["cash_cost_usd"], 1.5)
        self.assertEqual(data["cash_cost"]["usage_message_count"], 2)
        self.assertEqual(data["capacity"]["capacity_message_count"], 1)
        self.assertNotIn("cash_cost_usd", data["capacity"])

    def test_approved_pr_process_efficiency_is_scoped_to_the_month(self):
        run_meter(["event", "run.start", "--idempotency-key", "r1", "--run-id", "run-m1",
                   "--ts", "2026-08-05T09:00:00.000Z"], self.home)
        run_meter(["bind-pr", "--run", "run-m1", "--pr", "99"], self.home)
        run_meter(["event", "review.round", "--idempotency-key", "rv1", "--run-id", "run-m1",
                   "--round", "1", "--verdict", "approved", "--findings-count", "0",
                   "--ts", "2026-08-05T09:30:00.000Z"], self.home)
        # A second PR approved in a DIFFERENT month must not be counted.
        run_meter(["event", "run.start", "--idempotency-key", "r2", "--run-id", "run-m2",
                   "--ts", "2026-07-05T09:00:00.000Z"], self.home)
        run_meter(["bind-pr", "--run", "run-m2", "--pr", "100"], self.home)
        run_meter(["event", "review.round", "--idempotency-key", "rv2", "--run-id", "run-m2",
                   "--round", "1", "--verdict", "approved", "--findings-count", "0",
                   "--ts", "2026-07-05T09:30:00.000Z"], self.home)

        data = json.loads(run_meter(["report", "--month", "2026-08", "--json"], self.home).stdout)
        self.assertEqual(data["process_efficiency"]["approved_pr_count"], 1)
        self.assertEqual(data["process_efficiency"]["per_pr"][0]["pr_number"], 99)

    def test_month_boundary_uses_utc_not_local_offset(self):
        # T21: an event timestamped 23:30 UTC on 2026-07-31 must land in
        # the 2026-07 month report, NOT 2026-08, even though a JST
        # reader (+9h) would see it as the morning of 2026-08-01.
        run_meter(["event", "usage.message", "--idempotency-key", "u1", "--message-id", "m1",
                   "--model", "deepseek-v4-pro", "--cost-basis", "estimated", "--cost-estimate-usd", "2.0",
                   "--ts", "2026-07-31T23:30:00.000Z"], self.home)
        july = json.loads(run_meter(["report", "--month", "2026-07", "--json"], self.home).stdout)
        august = json.loads(run_meter(["report", "--month", "2026-08", "--json"], self.home).stdout)
        self.assertEqual(july["cash_cost"]["usage_message_count"], 1)
        self.assertEqual(august["cash_cost"]["usage_message_count"], 0)

    def test_month_defaults_to_current_utc_month_when_value_omitted(self):
        result = run_meter(["report", "--month"], self.home)
        self.assertEqual(result.returncode, 0)
        self.assertIn("month:", result.stdout)

    def test_rejects_malformed_month(self):
        result = run_meter(["report", "--month", "2026-13"], self.home)
        self.assertNotEqual(result.returncode, 0)


# ── Round 1 review regression tests ─────────────────────────────────────
# https://github.com/manemone/dotfiles/pull/28 round-1 review findings.

class SnapshotQuotaRoundOneReviewTests(OcwMeterTestCase):
    def test_out_of_range_resets_at_does_not_prevent_recording(self):
        # Finding 1: resets_at in milliseconds instead of seconds (a
        # plausible upstream format change) previously crashed
        # datetime.fromtimestamp() uncaught inside record_quota_sample(),
        # silently dropping the WHOLE sample (display string kept
        # working, masking the failure). Must be tolerated like a stale
        # value instead: window_id null, completeness partial, sample
        # still recorded.
        obj = {"rate_limits": {"five_hour": {"used_percentage": 10, "resets_at": 1785562800000}}}
        result = run_snapshot_quota(json.dumps(obj), self.home)
        self.assertEqual(result.returncode, 0)
        events = read_events(self.home)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["completeness"], "partial")
        self.assertIsNone(events[0]["window_id"])
        self.assertEqual(events[0]["five_hour_resets_at"], 1785562800000)

    def test_negative_resets_at_does_not_prevent_recording(self):
        obj = {"rate_limits": {"five_hour": {"used_percentage": 10, "resets_at": -99999999999999}}}
        result = run_snapshot_quota(json.dumps(obj), self.home)
        self.assertEqual(result.returncode, 0)
        events = read_events(self.home)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["completeness"], "partial")
        self.assertIsNone(events[0]["window_id"])

    def test_different_sessions_are_both_recorded_within_one_interval(self):
        # Finding 2: throttling used to be one global gate, so a second
        # PANE's statusLine sample within the same 60s window was
        # dropped entirely — losing that session's session_cost_usd/
        # context_used_pct permanently (this repo's own standard Herdr
        # commander/implementer/reviewer setup runs 2-3 panes at once).
        obj_a = {
            "session_id": "sess-A", "cost": {"total_cost_usd": 1.11},
            "rate_limits": {"five_hour": {"used_percentage": 10, "resets_at": 99999999999}},
            "context_window": {"used_percentage": 20},
        }
        obj_b = {
            "session_id": "sess-B", "cost": {"total_cost_usd": 9.99},
            "rate_limits": {"five_hour": {"used_percentage": 15, "resets_at": 99999999999}},
            "context_window": {"used_percentage": 80},
        }
        run_snapshot_quota(json.dumps(obj_a), self.home)
        run_snapshot_quota(json.dumps(obj_b), self.home)
        events = read_events(self.home)
        self.assertEqual(len(events), 2)
        by_session = {e["session_id"]: e for e in events}
        self.assertEqual(by_session["sess-A"]["session_cost_usd"], 1.11)
        self.assertEqual(by_session["sess-B"]["session_cost_usd"], 9.99)

    def test_same_session_still_throttled_within_interval(self):
        obj1 = {"session_id": "sess-A", "cost": {"total_cost_usd": 1.0}}
        obj2 = {"session_id": "sess-A", "cost": {"total_cost_usd": 2.0}}
        run_snapshot_quota(json.dumps(obj1), self.home)
        run_snapshot_quota(json.dumps(obj2), self.home)
        events = read_events(self.home)
        self.assertEqual(len(events), 1)
        self.assertEqual(events[0]["session_cost_usd"], 1.0)

    def test_missing_session_id_falls_back_to_a_shared_key_and_still_throttles(self):
        obj1 = {"cost": {"total_cost_usd": 1.0}}
        obj2 = {"cost": {"total_cost_usd": 2.0}}
        run_snapshot_quota(json.dumps(obj1), self.home)
        run_snapshot_quota(json.dumps(obj2), self.home)
        self.assertEqual(len(read_events(self.home)), 1)

    def test_global_window_anomaly_detection_still_works_across_sessions(self):
        # The five_hour_window_id/five_hour_used_pct anomaly check must
        # stay account-wide (global), not per-session — rate_limits
        # reflects the whole Claude.ai account (DOC-2608021229), so a decrease
        # reported by session B right after session A must still be
        # caught even though the two are throttled independently now.
        far_future = 99999999999
        obj_a = {"session_id": "sess-A", "rate_limits": {"five_hour": {"used_percentage": 50, "resets_at": far_future}}}
        obj_b = {"session_id": "sess-B", "rate_limits": {"five_hour": {"used_percentage": 30, "resets_at": far_future}}}
        run_snapshot_quota(json.dumps(obj_a), self.home)
        result_b = run_snapshot_quota(json.dumps(obj_b), self.home)
        self.assertIn("decreased within the same window_id", result_b.stderr)
        events = read_events(self.home)
        by_session = {e["session_id"]: e for e in events}
        self.assertEqual(by_session["sess-B"]["completeness"], "partial")

    def test_worktree_refusal_is_throttled_and_stops_rewarning(self):
        # Finding 3: nothing can ever be persisted under a refused
        # (in-worktree) root, so the per-root throttle state was always
        # empty and in_git_worktree() (a git subprocess call) ran on
        # EVERY single call — unthrottled, unlike every other
        # misconfiguration this file guards against. HOME is overridden
        # too so the suppression cache (which must live outside the
        # refused root, at the machine's default root) doesn't touch
        # this developer's real ~/.local/state/ocw-meter.
        fake_home = pathlib.Path(self.tmpdir.name) / "fake-home-for-default-root"
        fake_home.mkdir()
        repo_dir = pathlib.Path(self.tmpdir.name) / "repo-for-refusal-throttle"
        subprocess.run(["git", "init", "-q", str(repo_dir)], check=True)
        bad_home = repo_dir / "ocw-meter-home"
        env = {"HOME": str(fake_home)}

        r1 = run_snapshot_quota(json.dumps(CLAUDE_STATUSLINE_SAMPLE), bad_home, extra_env=env)
        r2 = run_snapshot_quota(json.dumps(CLAUDE_STATUSLINE_SAMPLE), bad_home, extra_env=env)

        self.assertEqual(r1.returncode, 0)
        self.assertEqual(r2.returncode, 0)
        self.assertIn("resolves inside a Git worktree", r1.stderr)
        self.assertNotIn("resolves inside a Git worktree", r2.stderr)
        # Both calls still print the display string — the point of the
        # fix is suppressing the wasted git subprocess call and stderr
        # noise, never the stdout contract.
        self.assertEqual(r1.stdout.strip(), "5h:37% 7d:12% ctx:24%")
        self.assertEqual(r2.stdout.strip(), "5h:37% 7d:12% ctx:24%")

    def test_cwd_is_recorded_on_the_event(self):
        # Finding 4: `json_cwd` was already extracted (to resolve git
        # context) but never actually stored on the event itself.
        obj = dict(CLAUDE_STATUSLINE_SAMPLE)
        obj["cwd"] = "/some/statusline/reported/cwd"
        run_snapshot_quota(json.dumps(obj), self.home)
        event = read_events(self.home)[0]
        self.assertEqual(event["cwd"], "/some/statusline/reported/cwd")

    def test_stdin_kept_open_without_eof_does_not_hang_forever(self):
        # Finding 8: a caller that opens the pipe but never writes/closes
        # it used to block sys.stdin.buffer.read() with NO time bound at
        # all — only a size bound. This must return within
        # STDIN_READ_TIMEOUT_SECONDS (2s), not hang indefinitely.
        #
        # round-2 review finding 2: `Popen(stdin=subprocess.PIPE)` +
        # `communicate()` with no `input=` closes the CHILD's stdin
        # immediately (an instant EOF) — that version of this test
        # passed identically against the pre-fix code too (review
        # measured 0.06s on both), so it never actually exercised the
        # hang this is meant to guard against. A real "caller keeps the
        # pipe open" scenario needs a fd whose write end the PARENT
        # keeps open for the whole check: os.pipe()'s read end goes to
        # the child as stdin, and the write end is held here, unclosed,
        # until after the process has already returned.
        read_fd, write_fd = os.pipe()
        proc = None
        try:
            proc = subprocess.Popen(
                [str(OCW_METER), "snapshot-quota"],
                cwd=str(REPO_ROOT),
                env={**os.environ, "OCW_METER_HOME": str(self.home)},
                stdin=read_fd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            os.close(read_fd)  # the child has its own copy (dup'd by Popen); this process doesn't need it
            read_fd = None
            start = time.monotonic()
            try:
                stdout, _stderr = proc.communicate(timeout=15)
            finally:
                if proc.poll() is None:
                    proc.kill()
            elapsed = time.monotonic() - start
        finally:
            if read_fd is not None:
                os.close(read_fd)
            os.close(write_fd)  # kept open (unclosed, unwritten-to) for the entire wait above

        self.assertEqual(proc.returncode, 0)
        # STDIN_READ_TIMEOUT_SECONDS is 2.0; review measured the fixed
        # code at ~2.07s under this exact harness. 5s leaves slack for
        # CI/sandbox jitter without hiding a regression the way the
        # previous 10s threshold could (a timeout silently growing from
        # 2s to 8s would still pass under 10s).
        self.assertLess(elapsed, 5)

    def test_interactive_tty_like_stdin_returns_immediately(self):
        # Finding 8 (isatty half). round-2 review finding 2: the
        # previous version of this test fed already-closed/empty stdin,
        # which hits EOF at the select()/read() stage and never actually
        # exercises the isatty() short-circuit branch at all — and its
        # own comment's claim that "a literal TTY is not spawnable
        # inside this test harness" was simply wrong (review's own repro
        # used exactly this pty.openpty() approach). A real pty fd, not
        # a pipe, is required to exercise isatty() == True.
        master_fd, slave_fd = pty.openpty()
        proc = None
        try:
            proc = subprocess.Popen(
                [str(OCW_METER), "snapshot-quota"],
                cwd=str(REPO_ROOT),
                env={**os.environ, "OCW_METER_HOME": str(self.home)},
                stdin=slave_fd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            os.close(slave_fd)
            slave_fd = None
            start = time.monotonic()
            try:
                stdout, _stderr = proc.communicate(timeout=15)
            finally:
                if proc.poll() is None:
                    proc.kill()
            elapsed = time.monotonic() - start
        finally:
            if slave_fd is not None:
                os.close(slave_fd)
            os.close(master_fd)

        self.assertEqual(proc.returncode, 0)
        # isatty() short-circuits before select() ever runs (review
        # measured ~0.06s) — much tighter than the pipe-timeout case.
        self.assertLess(elapsed, 2)


class SnapshotQuotaRoundTwoReviewTests(OcwMeterTestCase):
    def test_rate_limits_less_sample_does_not_erase_global_window_state(self):
        # Round-2 review finding 1 (most severe): the global
        # five_hour_window_id/five_hour_used_pct slot used to be
        # overwritten unconditionally on every write, including by a
        # sample that has NO window info of its own (any claude-ds/
        # DeepSeek sample — DOC-2608021229 §2.1's 58/58). One such sample
        # landing between two Anthropic samples silently defeated plan
        # §8.5's "同一window_id内でused_percentageが減少したら異常" check
        # — and round-1's OWN per-session-throttle fix made this near-
        # guaranteed in this repo's standard Herdr setup (an Anthropic
        # pane + a claude-ds pane both sampling roughly every interval).
        far_future = 99999999999
        obj_a1 = {"session_id": "sess-A", "rate_limits": {"five_hour": {"used_percentage": 50, "resets_at": far_future}}}
        obj_ds = {"session_id": "sess-ds", "model": {"id": "deepseek-v4-pro[1m]"}}  # no rate_limits at all
        obj_a2 = {"session_id": "sess-A", "rate_limits": {"five_hour": {"used_percentage": 30, "resets_at": far_future}}}

        run_snapshot_quota(json.dumps(obj_a1), self.home, extra_env={"OCW_METER_QUOTA_INTERVAL": "0"})
        r_ds = run_snapshot_quota(json.dumps(obj_ds), self.home, extra_env={"OCW_METER_QUOTA_INTERVAL": "0"})
        r_a2 = run_snapshot_quota(json.dumps(obj_a2), self.home, extra_env={"OCW_METER_QUOTA_INTERVAL": "0"})

        self.assertNotIn("decreased within the same window_id", r_ds.stderr)
        self.assertIn("decreased within the same window_id", r_a2.stderr)

        events = read_events(self.home)
        by_session_and_ts = sorted(events, key=lambda e: e["ts"])
        self.assertEqual([e["session_id"] for e in by_session_and_ts], ["sess-A", "sess-ds", "sess-A"])
        self.assertEqual(by_session_and_ts[1]["completeness"], "unknown")  # the rate_limits-less sample itself
        self.assertEqual(by_session_and_ts[2]["completeness"], "partial")  # A's decrease must still be caught

    def test_suppression_cache_does_not_write_inside_a_git_worktree_home(self):
        # Round-2 review finding 3: `default_storage_root()` is a pure
        # path-string builder — it never checks whether $HOME itself
        # happens to sit inside a git worktree (a real shape for this
        # very repo's own dotfiles use case). Writing the round-1
        # suppression cache there unconditionally left an untracked
        # quota-worktree-refusal.json inside a test repo. This must not
        # happen — `emit_meter_error`'s own default-root fallback
        # already re-checks the same way, and the suppression cache must
        # match that precedent.
        home_repo = pathlib.Path(self.tmpdir.name) / "home-is-a-git-repo"
        subprocess.run(["git", "init", "-q", str(home_repo)], check=True)
        other_repo = pathlib.Path(self.tmpdir.name) / "other-repo-for-bad-ocw-meter-home"
        subprocess.run(["git", "init", "-q", str(other_repo)], check=True)
        bad_ocw_meter_home = other_repo / "ocw-meter-home"

        result = run_snapshot_quota(
            json.dumps(CLAUDE_STATUSLINE_SAMPLE), bad_ocw_meter_home,
            extra_env={"HOME": str(home_repo)},
        )
        self.assertEqual(result.returncode, 0)
        self.assertIn("resolves inside a Git worktree", result.stderr)

        status = subprocess.run(
            ["git", "-C", str(home_repo), "status", "--porcelain"],
            capture_output=True, text=True, check=True,
        )
        self.assertEqual(status.stdout.strip(), "", "suppression cache must not write inside $HOME's own git worktree")


if __name__ == "__main__":
    unittest.main()
