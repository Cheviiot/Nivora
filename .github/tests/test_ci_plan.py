import importlib.util
import subprocess
import unittest
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).resolve().parents[1] / "tools/ci_plan.py"
SPEC = importlib.util.spec_from_file_location("ci_plan", MODULE_PATH)
assert SPEC and SPEC.loader
CI_PLAN = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CI_PLAN)


class ClassifyPathsTests(unittest.TestCase):
    packages = ["alpha", "beta"]

    def test_package_path_selects_only_that_package(self):
        self.assertEqual(
            CI_PLAN.classify_paths(["alpha/Staplerfile"], self.packages),
            (["alpha"], False),
        )

    def test_common_ci_path_selects_every_package(self):
        self.assertEqual(
            CI_PLAN.classify_paths(
                [".github/tools/validate_repo.py"], self.packages
            ),
            (self.packages, True),
        )

    def test_unrelated_docs_do_not_schedule_builds(self):
        self.assertEqual(
            CI_PLAN.classify_paths(["README.md"], self.packages), ([], False)
        )

    def test_requested_packages_are_checked(self):
        self.assertEqual(
            CI_PLAN.parse_requested("beta alpha beta", self.packages),
            (["alpha", "beta"], False),
        )
        with self.assertRaises(ValueError):
            CI_PLAN.parse_requested("missing", self.packages)

    @mock.patch.object(CI_PLAN.subprocess, "run")
    def test_unreachable_base_forces_full_plan(self, run):
        run.return_value = subprocess.CompletedProcess(
            args=[], returncode=128, stdout="", stderr="bad revision"
        )
        self.assertEqual(
            CI_PLAN.changed_paths("deadbeef", "HEAD"),
            [".github/support-matrix.toml"],
        )

    @mock.patch.object(CI_PLAN.subprocess, "run")
    def test_deleted_paths_are_included_in_plan(self, run):
        run.return_value = subprocess.CompletedProcess(
            args=[], returncode=0, stdout="alpha/tests/test-smoke.sh\n", stderr=""
        )
        self.assertEqual(
            CI_PLAN.changed_paths("base", "head"),
            ["alpha/tests/test-smoke.sh"],
        )
        self.assertIn("--diff-filter=ACMRD", run.call_args.args[0])


if __name__ == "__main__":
    unittest.main()
