import importlib.util
import subprocess
import sys
import tempfile
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

    def test_mixed_package_and_common_files_build_every_package(self):
        self.assertEqual(
            CI_PLAN.classify_paths(
                ["alpha/Staplerfile", ".github/support-matrix.toml"],
                self.packages,
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

    def test_explicit_empty_selection_is_not_an_implicit_full_build(self):
        for selection in ["", " ", "\n\t"]:
            with self.subTest(selection=selection), tempfile.TemporaryDirectory() as directory:
                output = Path(directory) / "github-output"
                result = subprocess.run(
                    [sys.executable, str(MODULE_PATH), "--packages", selection,
                     "--github-output", str(output)],
                    capture_output=True, text=True, check=False,
                )
                self.assertEqual(result.returncode, 2)
                self.assertIn("package selection is empty", result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertFalse(output.exists())

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
            args=[], returncode=0, stdout="alpha/tests/test-smoke.sh\0", stderr=""
        )
        self.assertEqual(
            CI_PLAN.changed_paths("base", "head"),
            ["alpha/tests/test-smoke.sh"],
        )
        self.assertIn("--no-renames", run.call_args.args[0])
        self.assertIn("-z", run.call_args.args[0])


class ChangedPathsGitTests(unittest.TestCase):
    """Use Git itself: mocks cannot reproduce rename and path-quoting rules."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.git("init", "-q")
        self.git("config", "user.name", "CI test")
        self.git("config", "user.email", "ci@example.invalid")
        self.git("config", "diff.renames", "true")
        for package in ("alpha", "beta"):
            (self.root / package).mkdir()
            (self.root / package / "Staplerfile").write_text("name=" + package)
        (self.root / "alpha/payload").write_text("fixture payload\n")
        self.commit()
        self.base = self.git("rev-parse", "HEAD")

    def git(self, *args):
        return subprocess.run(
            ["git", *args], cwd=self.root, check=True,
            capture_output=True, text=True,
        ).stdout.strip()

    def commit(self):
        self.git("add", "-A")
        self.git("commit", "-qm", "fixture")

    def changed(self):
        self.commit()
        with mock.patch.object(CI_PLAN, "ROOT", self.root):
            return CI_PLAN.changed_paths(self.base, "HEAD")

    def test_move_between_packages_checks_both_owners(self):
        (self.root / "alpha/payload").rename(self.root / "beta/payload")
        paths = self.changed()
        self.assertEqual(paths, ["alpha/payload", "beta/payload"])
        self.assertEqual(
            CI_PLAN.classify_paths(paths, ["alpha", "beta"]),
            (["alpha", "beta"], False),
        )

    def test_move_outside_package_still_checks_source_owner(self):
        (self.root / "alpha/payload").rename(self.root / "payload")
        self.assertEqual(
            CI_PLAN.classify_paths(self.changed(), ["alpha", "beta"]),
            (["alpha"], False),
        )

    def test_type_change_is_not_filtered_out(self):
        (self.root / "alpha/payload").unlink()
        (self.root / "alpha/payload").symlink_to("Staplerfile")
        self.assertEqual(self.changed(), ["alpha/payload"])

    def test_unusual_path_is_preserved_without_git_quoting(self):
        path = "alpha/данные\nfixture.txt"
        (self.root / path).write_text("fixture")
        self.assertEqual(self.changed(), [path])


if __name__ == "__main__":
    unittest.main()
