import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / ".github/tools/candidate_backoff.py"
NOW = "2026-10-28T00:00:00Z"
RETRY = "2026-10-28T06:00:00Z"


class CandidateBackoffTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.package_dir = self.root / "demo"
        self.package_dir.mkdir()
        (self.package_dir / "Staplerfile").write_text(
            "name='demo'\nversion='1.0.0'\nrelease=1\n", encoding="utf-8"
        )
        self.plan = {"demo": {"current": "1.0.0", "latest": "2.0.0", "fingerprints": {}}}
        self.plan_path = self.root / "plan.json"
        self.issues_path = self.root / "issues.json"

    def write_plan(self, plan=None):
        self.plan_path.write_text(json.dumps(self.plan if plan is None else plan), encoding="utf-8")

    def write_issues(self, issues):
        self.issues_path.write_text(json.dumps([issues]), encoding="utf-8")

    def run_filter(self, now=NOW, plan=None, issues=None):
        self.write_plan(plan)
        self.write_issues([] if issues is None else issues)
        result = subprocess.run(
            [
                "python3",
                str(TOOL),
                "filter",
                "--plan",
                str(self.plan_path),
                "--issues",
                str(self.issues_path),
                "--repo-root",
                str(self.root),
                "--now",
                now,
            ],
            check=True,
            capture_output=True,
            text=True,
            env={**os.environ, "BASH_ENV": "/dev/null"},
        )
        return json.loads(result.stdout)

    def issue(
        self,
        body,
        *,
        login="github-actions[bot]",
        state="open",
        title="[autoupdate] demo: обновление отложено",
    ):
        return {
            "number": 7,
            "title": title,
            "user": {"login": login},
            "state": state,
            "body": body,
        }

    def cooldown_issue(self, key=None, retry=RETRY):
        if key is None:
            key = self.run_filter()["candidate_keys"]["demo"]
        body = (
            "<!-- nivora-autonomous-update:demo -->\n"
            f"<!-- nivora-update-candidate: {key} -->\n"
            f"<!-- nivora-update-retry-after: {retry} -->\n"
        )
        return self.issue(body)

    def test_identical_candidate_waits_until_exact_six_hour_boundary(self):
        issue = self.cooldown_issue()
        before = self.run_filter(issues=[issue])
        at_boundary = self.run_filter(now=RETRY, issues=[issue])
        self.assertEqual(before["packages"], [])
        self.assertEqual(before["deferred"], ["demo"])
        self.assertEqual(at_boundary["packages"], ["demo"])
        self.assertEqual(at_boundary["deferred"], [])

    def test_changed_version_fingerprint_or_recipe_is_immediately_eligible(self):
        original_issue = self.cooldown_issue()
        version_plan = {"demo": {**self.plan["demo"], "latest": "2.1.0"}}
        fingerprint_plan = {
            "demo": {
                **self.plan["demo"],
                "fingerprints": {"source_fingerprint": "a" * 64},
            }
        }
        self.assertEqual(self.run_filter(plan=version_plan, issues=[original_issue])["packages"], ["demo"])
        self.assertEqual(self.run_filter(plan=fingerprint_plan, issues=[original_issue])["packages"], ["demo"])
        (self.package_dir / "Staplerfile").write_text(
            "name='demo'\nversion='1.0.0'\nrelease=2\n", encoding="utf-8"
        )
        self.assertEqual(self.run_filter(issues=[original_issue])["packages"], ["demo"])

    def test_human_closed_and_untrusted_issues_do_not_impose_cooldown(self):
        issue = self.cooldown_issue()
        cases = (
            {**issue, "user": {"login": "octocat"}},
            {**issue, "state": "closed"},
            {**issue, "title": "unrelated"},
            {**issue, "pull_request": {"url": "https://example.invalid/pr"}},
        )
        for candidate in cases:
            with self.subTest(candidate=candidate):
                self.assertEqual(self.run_filter(issues=[candidate])["packages"], ["demo"])

    def test_human_spoof_does_not_cancel_valid_bot_cooldown(self):
        bot_issue = self.cooldown_issue()
        human_spoof = {
            **bot_issue,
            "number": 8,
            "user": {"login": "octocat"},
        }
        result = self.run_filter(issues=[human_spoof, bot_issue])
        self.assertEqual(result["packages"], [])
        self.assertEqual(result["deferred"], ["demo"])

    def test_missing_duplicate_or_corrupt_metadata_retries_safely(self):
        key = self.run_filter()["candidate_keys"]["demo"]
        body = "<!-- nivora-autonomous-update:demo -->\n"
        invalid_bodies = (
            body,
            body + f"<!-- nivora-update-candidate: {key} -->\n<!-- nivora-update-retry-after: bad -->\n",
            body
            + f"<!-- nivora-update-candidate: {key} -->\n"
            + "<!-- nivora-update-retry-after: 2099-01-01T00:00:00Z -->\n",
            body
            + f"<!-- nivora-update-candidate: {key} -->\n"
            + f"<!-- nivora-update-candidate: {key} -->\n"
            + f"<!-- nivora-update-retry-after: {RETRY} -->\n",
        )
        for invalid in invalid_bodies:
            with self.subTest(body=invalid):
                self.assertEqual(self.run_filter(issues=[self.issue(invalid)])["packages"], ["demo"])
        duplicate_issues = [self.cooldown_issue(key), self.cooldown_issue(key)]
        self.assertEqual(self.run_filter(issues=duplicate_issues)["packages"], ["demo"])

    def test_filter_output_keeps_only_eligible_expected_updates(self):
        result = self.run_filter(issues=[self.cooldown_issue()])
        self.assertEqual(result["expected_updates"], {})
        self.assertEqual(len(result["candidate_keys"]["demo"]), 64)

    def test_bad_plan_package_ids_are_rejected(self):
        invalid = {"../demo": {"current": "1", "latest": "2", "fingerprints": {}}}
        self.write_plan(invalid)
        self.write_issues([])
        result = subprocess.run(
            ["python3", str(TOOL), "filter", "--plan", str(self.plan_path), "--issues", str(self.issues_path), "--repo-root", str(self.root), "--now", NOW],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)

        self.plan_path.write_text(
            '{"demo":{"current":"1.0.0","latest":"2.0.0","fingerprints":{}},'
            '"demo":{"current":"1.0.0","latest":"3.0.0","fingerprints":{}}}',
            encoding="utf-8",
        )
        result = subprocess.run(
            ["python3", str(TOOL), "filter", "--plan", str(self.plan_path), "--issues", str(self.issues_path), "--repo-root", str(self.root), "--now", NOW],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(result.returncode, 0)

    def test_stamp_requires_trusted_plan_and_matching_current_recipe(self):
        self.write_plan()
        command = [
            "python3",
            str(TOOL),
            "stamp",
            "--package",
            "demo",
            "--plan",
            str(self.plan_path),
            "--repo-root",
            str(self.root),
            "--now",
            NOW,
        ]
        stamped = subprocess.run(command, check=True, capture_output=True, text=True)
        self.assertIn("<!-- nivora-update-candidate: ", stamped.stdout)
        self.assertIn("<!-- nivora-update-retry-after: 2026-10-28T06:00:00Z -->", stamped.stdout)

        self.plan_path.unlink()
        missing_plan = subprocess.run(command, check=True, capture_output=True, text=True)
        self.assertEqual(missing_plan.stdout, "")

        self.write_plan({"demo": {**self.plan["demo"], "current": "9.9.9"}})
        stale_plan = subprocess.run(command, check=True, capture_output=True, text=True)
        self.assertEqual(stale_plan.stdout, "")


if __name__ == "__main__":
    unittest.main()
