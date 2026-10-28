import importlib.util
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
MODULE_PATH = REPO_ROOT / ".github/tools/plan_updater_recovery.py"
SPEC = importlib.util.spec_from_file_location("plan_updater_recovery", MODULE_PATH)
planner = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(planner)


PAUSED_SHA = "a" * 40
CURRENT_SHA = "b" * 40
OTHER_SHA = "c" * 40
NOW = datetime(2026, 10, 28, 4, 0, tzinfo=timezone.utc)
NOW_TEXT = NOW.isoformat().replace("+00:00", "Z")


def request(**overrides):
    values = {
        "pause_state": {"paused": True, "sha": PAUSED_SHA},
        "current_sha": CURRENT_SHA,
        "paused_sha_is_ancestor": True,
        "workflow_runs": [],
        "now": NOW_TEXT,
    }
    values.update(overrides)
    return values


def recovery_run(
    sha=CURRENT_SHA,
    *,
    status="completed",
    conclusion="failure",
    created_at=None,
    updated_at=None,
    resume=True,
):
    run = {
        "display_title": f"post-push {sha} · updater 12345 · resume {str(resume).lower()}",
        "status": status,
        "conclusion": conclusion,
        "created_at": created_at or (NOW - timedelta(hours=7)).isoformat().replace("+00:00", "Z"),
    }
    if updated_at is not None:
        run["updated_at"] = updated_at
    return run


class RecoveryPlannerTests(unittest.TestCase):
    def test_unpaused_does_not_schedule_recovery(self):
        self.assertEqual(
            planner.plan_recovery(request(pause_state={"paused": False, "sha": ""})),
            {"action": "none", "reason": "not-paused"},
        )

    def test_active_recovery_for_current_sha_is_deduplicated(self):
        run = recovery_run(status="in_progress", conclusion=None)
        self.assertEqual(
            planner.plan_recovery(request(workflow_runs=[run])),
            {"action": "none", "reason": "recovery-active"},
        )

    def test_recent_failure_is_backed_off(self):
        run = recovery_run(created_at=(NOW - timedelta(hours=5, minutes=59)).isoformat())
        self.assertEqual(
            planner.plan_recovery(request(workflow_runs=[run])),
            {"action": "none", "reason": "retry-cooldown"},
        )

    def test_failure_at_cooldown_boundary_can_retry(self):
        run = recovery_run(created_at=(NOW - timedelta(hours=6)).isoformat())
        self.assertEqual(
            planner.plan_recovery(request(workflow_runs=[[run]])),
            {"action": "dispatch", "reason": "retry-after-cooldown", "sha": CURRENT_SHA},
        )

    def test_long_failed_run_cooldown_starts_at_recent_updated_at(self):
        run = recovery_run(
            created_at=(NOW - timedelta(days=2)).isoformat(),
            updated_at=(NOW - timedelta(hours=5, minutes=59)).isoformat(),
        )
        self.assertEqual(
            planner.plan_recovery(request(workflow_runs=[run])),
            {"action": "none", "reason": "retry-cooldown"},
        )

    def test_missing_updated_at_falls_back_to_created_at(self):
        run = recovery_run(created_at=(NOW - timedelta(hours=6)).isoformat())
        self.assertEqual(
            planner.plan_recovery(request(workflow_runs=[run])),
            {"action": "dispatch", "reason": "retry-after-cooldown", "sha": CURRENT_SHA},
        )

    def test_new_main_sha_is_not_blocked_by_old_sha_failure(self):
        old_failure = recovery_run(sha=OTHER_SHA, created_at=(NOW - timedelta(minutes=1)).isoformat())
        self.assertEqual(
            planner.plan_recovery(request(workflow_runs=[old_failure])),
            {"action": "dispatch", "reason": "new-recovery", "sha": CURRENT_SHA},
        )

    def test_non_recovery_run_does_not_suppress_full_recovery(self):
        ordinary_post_push = recovery_run(resume=False, status="in_progress", conclusion=None)
        self.assertEqual(
            planner.plan_recovery(request(workflow_runs=[ordinary_post_push])),
            {"action": "dispatch", "reason": "new-recovery", "sha": CURRENT_SHA},
        )

    def test_pause_sha_not_ancestor_keeps_pause_blocked(self):
        self.assertEqual(
            planner.plan_recovery(request(paused_sha_is_ancestor=False)),
            {"action": "none", "reason": "pause-sha-not-ancestor"},
        )

    def test_malformed_pause_sha_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "paused issue has a malformed SHA"):
            planner.plan_recovery(request(pause_state={"paused": True, "sha": "bad"}))

    def test_unknown_matching_run_status_fails_closed(self):
        run = recovery_run(status="future-status", conclusion=None)
        with self.assertRaisesRegex(ValueError, "unknown workflow status"):
            planner.plan_recovery(request(workflow_runs=[run]))


if __name__ == "__main__":
    unittest.main()
