"""Tests for bin/ocw-meter.

These invoke the real executable as a subprocess (black-box) rather than
importing internals, because ocw-meter is a single deployable file (bash
skin + embedded python3), matching bin/ocw's style. Every test points
OCW_METER_HOME at a throwaway tempdir outside this repo, so nothing here
touches real state or the repo itself.

No network access. No secrets. See docs/planning/DOC-003_..._計画.md §13
for the numbered test-case list (T01, T02, ...) this file implements.
"""

import concurrent.futures
import json
import os
import pathlib
import stat
import subprocess
import tempfile
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
            ["event", "run.start", "--idempotency-key", "k1", "--source", "ocw"],
            self.home,
        )
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), "written")

        events = read_events(self.home)
        self.assertEqual(len(events), 1)
        event = events[0]
        self.assertEqual(event["event_type"], "run.start")
        self.assertEqual(event["schema_version"], 1)
        self.assertEqual(event["idempotency_key"], "k1")
        self.assertEqual(event["source"], "ocw")
        self.assertEqual(event["completeness"], "complete")
        # Fields nobody supplied a value for must be present and null,
        # never silently missing (T10-style robustness at envelope level).
        for field in ("role", "session_id", "provider", "model", "phase", "round", "pr_number", "pr_url"):
            self.assertIn(field, event)
            self.assertIsNone(event[field])

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
        run_meter(["event", "phase.end", "--idempotency-key", "e2", "--run-id", "run-7", "--phase", "implement"], self.home)
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
        good = json.dumps({"schema_version": 1, "event_id": "e1", "event_type": "run.start", "idempotency_key": "k1", "ts": "2026-08-01T00:00:00.000Z"})
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
        good = json.dumps({"schema_version": 1, "event_id": "e1", "event_type": "run.start", "idempotency_key": "k1", "ts": "2026-08-01T00:00:00.000Z"})
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
        good = json.dumps({"schema_version": 1, "event_id": "e1", "event_type": "run.start", "idempotency_key": "k1", "ts": "2026-08-01T00:00:00.000Z"})
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
        result = run_meter(["event", "run.start", "--idempotency-key", "k1"], self.home)
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
        home = REPO_ROOT / "tmp-test-ocw-meter-worktree-guard"
        self.assertFalse(home.exists())
        try:
            result = run_meter(["event", "run.start", "--idempotency-key", "k1"], home)
            self.assertEqual(result.returncode, 0)
            self.assertFalse(home.exists())
        finally:
            if home.exists():
                import shutil

                shutil.rmtree(home)

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


class NoAccidentalCouplingTests(unittest.TestCase):
    def test_ocw_does_not_reference_ocw_meter_yet(self):
        # Regression guard for this PR's stated scope: instrumentation of
        # `ocw` itself is a later phase. If this starts failing, it means
        # someone wired ocw-meter into ocw here — that integration needs
        # its own review focused on non-regression of ocw's behavior.
        ocw_source = (REPO_ROOT / "bin" / "ocw").read_text(encoding="utf-8")
        self.assertNotIn("ocw-meter", ocw_source)


if __name__ == "__main__":
    unittest.main()
