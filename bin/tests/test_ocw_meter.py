"""Tests for bin/ocw-meter.

These invoke the real executable as a subprocess (black-box) rather than
importing internals, because ocw-meter is a single deployable file (bash
skin + embedded python3), matching bin/ocw's style. Every test points
OCW_METER_HOME at a throwaway tempdir outside this repo, so nothing here
touches real state or the repo itself.

No network access. No secrets. See docs/planning/DOC-003_..._計画.md §13
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
transcripts. See docs/planning/DOC-003_..._計画.md's 孫3プロンプト for the
completion criteria this maps to (idempotency, message.id dedup,
message.content non-exposure, cost formula, price-table versioning).
"""

import concurrent.futures
import json
import os
import pathlib
import pty
import stat
import subprocess
import sys
import tempfile
import time
import unittest

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
OCW_METER = REPO_ROOT / "bin" / "ocw-meter"


def run_meter(args, home, extra_env=None, timeout=30):
    env = dict(os.environ)
    env["OCW_METER_HOME"] = str(home)
    # Isolate from whatever role/run/Herdr context this test happens to run
    # under, so assertions about "unset -> null" stay meaningful.
    for key in ("OCW_RUN_ID", "OCW_ROLE", "HERDR_WORKSPACE_ID", "HERDR_PANE_ID"):
        env.pop(key, None)
    if extra_env:
        env.update(extra_env)
    return subprocess.run(
        [str(OCW_METER), *args],
        cwd=str(REPO_ROOT),
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
        # DeepSeek session with no rate_limits — ADR-001 §2.1) must NOT
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
        # shape-accurate sample of exactly that situation (ADR-001 §2.2
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
        # above) — this is the fixture ADR-001 §2.2's 59.4%-duplicate
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
        # July totals from plan §1 / ADR-001 §2.2 — this is the $46.78
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
        # coverage" case (plan §5.10 / ADR-001 §2.2, deepseek-v4-flash)
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
    """孫4: `ocw-meter snapshot-quota`. See docs/planning/DOC-003_..._
    計画.md §8.5 / 孫4プロンプト and ADR-001 §2.1/§8."""

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
        # T10 (quota half) / ADR-001 §2.1: every claude-ds session (58/58
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
        # ADR-001 §2.1: used_percentage was null in 7/66 real samples;
        # total_input_tokens/context_window_size were "常に取得可能".
        # ADR-001 §8 instruction 7 draws a line between the RECORDED
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
        # in some session types already — ADR-001 §2.1).
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
        repo_dir = pathlib.Path(self.tmpdir.name) / "repo"
        subprocess.run(["git", "init", "-q", str(repo_dir)], check=True)
        bad_home = repo_dir / "ocw-meter-home"
        result = run_snapshot_quota(json.dumps(CLAUDE_STATUSLINE_SAMPLE), bad_home)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "5h:37% 7d:12% ctx:24%")
        self.assertIn("resolves inside a Git worktree", result.stderr)
        self.assertFalse((bad_home / "events").exists())


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
    """T09: 5-hour window reset/staleness handling (plan §8.5, ADR-001
    §2.1/§8 instruction 4)."""

    def test_stale_resets_at_is_marked_partial_with_null_window_id(self):
        # ADR-001 §2.1: 3/8 real samples had an already-past resets_at.
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
    """docs/planning/DOC-003_..._計画.md 孫5プロンプト §1."""

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

    # -- --pr combined with a grouped view scopes to that PR --

    def test_model_view_combined_with_pr_filter_scopes_to_that_pr(self):
        self._seed_full_pr(5, "run-scope-a")
        self._seed_full_pr(6, "run-scope-b")
        data = json.loads(run_meter(["report", "--model", "--pr", "5", "--json"], self.home).stdout)
        self.assertEqual(data["filter_pr"], 5)
        self.assertEqual(data["by_model"]["deepseek/deepseek-v4-pro"]["messages"], 1)

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
        # reflects the whole Claude.ai account (ADR-001), so a decrease
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
        # DeepSeek sample — ADR-001 §2.1's 58/58). One such sample
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
