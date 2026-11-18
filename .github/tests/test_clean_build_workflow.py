"""Exercise manual-build selection and gates without a container engine."""

import json
import os
import re
import subprocess
import tempfile
import textwrap
import tomllib
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/clean-build.yml"


def workflow_step(name):
    match = re.search(
        rf"(?ms)^      - name: {re.escape(name)}\n(.*?)(?=^      - name:|\Z)",
        WORKFLOW.read_text(),
    )
    if match is None:
        raise AssertionError(f"Missing manual-build step: {name}")
    return match.group(1)


def step_script(name):
    step = workflow_step(name)
    run = re.search(r"(?m)^        run: (.*)$", step)
    if run is None:
        raise AssertionError(f"Missing run block: {name}")
    if run[1] not in {"|", ">-"}:
        return run[1]
    lines = []
    for line in step[run.end():].splitlines():
        if line and not line.startswith("          "):
            break
        lines.append(line)
    body = textwrap.dedent("\n".join(lines)).strip()
    return " ".join(body.splitlines()) if run[1] == ">-" else body


class ManualBuildTests(unittest.TestCase):
    def run_build(self, selection, failed_phase=""):
        workflow = WORKFLOW.read_text()
        names = ["Выбрать пакеты", "Проверить обязательные G0–G2", "Собрать пакеты"]
        self.assertEqual(sorted(names, key=workflow.index), names)
        static = workflow_step(names[1])
        self.assertNotIn("if:", static)
        self.assertNotIn("continue-on-error:", static)
        build = workflow_step(names[2])
        self.assertIn("PACKAGES_JSON: ${{ steps.plan.outputs.packages }}", build)
        self.assertIn("NIVORA_STPLR_CHANNEL: stable", build)
        self.assertIn("NIVORA_ALT_BRANCH: p11", build)
        self.assertIn("shellcheck", workflow_step("Подготовить инструменты"))

        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tools = root / ".github/tools"
            tools.mkdir(parents=True)
            (tools / "ci_plan.py").symlink_to(ROOT / ".github/tools/ci_plan.py")
            log = root / "commands.jsonl"
            output = root / "github-output"
            for name in ["run_checks.sh", "clean_build.sh", "verify_artifacts.sh",
                         "test_package_lifecycle.sh"]:
                script = tools / name
                script.write_text(textwrap.dedent("""\
                    #!/usr/bin/env python3
                    import json, os, sys
                    from pathlib import Path
                    phase = Path(sys.argv[0]).name
                    with open(os.environ["TEST_COMMAND_LOG"], "a") as stream:
                        stream.write(json.dumps({
                            "phase": phase,
                            "packages": sys.argv[1:],
                            "lifecycle": os.environ.get("NIVORA_LIFECYCLE_PACKAGES", ""),
                        }) + "\\n")
                    sys.exit(1 if os.environ["TEST_FAILED_PHASE"] == phase else 0)
                """))
                script.chmod(0o755)
            env = {
                **os.environ, "REQUESTED_PACKAGES": selection,
                "GITHUB_OUTPUT": str(output), "TEST_COMMAND_LOG": str(log),
                "TEST_FAILED_PHASE": failed_phase,
            }
            for name in names:
                if name == "Собрать пакеты":
                    outputs = dict(line.split("=", 1) for line in output.read_text().splitlines())
                    env["PACKAGES_JSON"] = outputs["packages"]
                result = subprocess.run(
                    ["bash", "-euo", "pipefail", "-c", step_script(name)],
                    cwd=root, env=env, capture_output=True, text=True, check=False,
                )
                if result.returncode:
                    break
            calls = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, calls

    def test_all_uses_the_same_catalog_for_build_artifact_and_lifecycle(self):
        with (ROOT / ".github/support-matrix.toml").open("rb") as stream:
            packages = sorted(item["id"] for item in tomllib.load(stream)["packages"])
        result, calls = self.run_build("all")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([item["phase"] for item in calls], [
            "run_checks.sh", "clean_build.sh", "verify_artifacts.sh", "test_package_lifecycle.sh",
        ])
        self.assertEqual(calls[1]["packages"], packages)
        self.assertEqual(calls[2]["packages"], packages)
        self.assertEqual(calls[3]["lifecycle"], ",".join(packages))

    def test_selection_is_normalized_once_for_every_gate(self):
        result, calls = self.run_build("telegram\n antigravity telegram")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(calls[1]["packages"], ["antigravity", "telegram"])
        self.assertEqual(calls[2]["packages"], ["antigravity", "telegram"])
        self.assertEqual(calls[3]["lifecycle"], "antigravity,telegram")

    def test_invalid_selection_never_starts_validation_or_builds(self):
        for selection in ["", "   ", "unknown", "telegram unknown", "all telegram"]:
            with self.subTest(selection=selection):
                result, calls = self.run_build(selection)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(calls, [])

    def test_a_failed_gate_stops_following_phases(self):
        for phase, expected in [
            ("run_checks.sh", ["run_checks.sh"]),
            ("clean_build.sh", ["run_checks.sh", "clean_build.sh"]),
            ("verify_artifacts.sh", ["run_checks.sh", "clean_build.sh", "verify_artifacts.sh"]),
        ]:
            with self.subTest(phase=phase):
                result, calls = self.run_build("telegram", failed_phase=phase)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual([item["phase"] for item in calls], expected)


if __name__ == "__main__":
    unittest.main()
