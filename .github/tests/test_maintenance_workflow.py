"""Check the scheduled full-verification contract without a GitHub runner."""

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
WORKFLOW = ROOT / ".github/workflows/post-push-verify.yml"
UPDATER_WORKFLOW = ROOT / ".github/workflows/check-updates.yml"
SHA_EXPRESSION = "${{ github.event_name == 'schedule' && github.sha || inputs.sha }}"
FULL_EXPRESSION = "${{ inputs.resume_on_success || github.event_name == 'schedule' }}"


def planning_step(workflow):
    """Extract the actual shell block that selects the verification catalogue."""
    step = workflow.split("      - name: Выбрать изменённые пакеты\n", 1)[1]
    body = step.split("        run: |\n", 1)[1]
    lines = []
    for line in body.splitlines():
        if line and not line.startswith("          "):
            break
        lines.append(line)
    return textwrap.dedent("\n".join(lines))


def condition(section, values):
    """Evaluate the actual restricted GitHub expression used by a workflow gate."""
    expression = re.search(r"\bif: (?:>-\s*)?\$\{\{(.*?)\}\}", section, re.DOTALL)[1]
    for name, value in values.items():
        expression = expression.replace(name, repr(value))
    expression = expression.replace("&&", " and ").replace("||", " or ")
    expression = re.sub(r"!(?!=)", " not ", expression)
    return eval(" ".join(expression.split()), {"__builtins__": {}}, {"true": True, "false": False})


class MaintenanceWorkflowTests(unittest.TestCase):
    def test_daily_run_uses_event_sha_and_cannot_run_as_a_pull_request(self):
        workflow = WORKFLOW.read_text()
        triggers = workflow.split("\non:\n", 1)[1].split("\npermissions:", 1)[0]
        self.assertIn('    - cron: "47 18 * * *"', triggers)
        self.assertNotIn("pull_request", triggers)
        # Plan and build must check out the exact event/input SHA. Only the
        # privileged reconciler may check out current trusted main.
        refs = re.findall(r"^\s+ref: (.+)$", workflow, re.MULTILINE)
        self.assertEqual(refs, [SHA_EXPRESSION, SHA_EXPRESSION, "main"])
        requested = re.findall(r"^\s+REQUESTED_SHA: (.+)$", workflow, re.MULTILINE)
        self.assertEqual(requested, [SHA_EXPRESSION] * 4)
        self.assertIn(f"RESUME_ON_SUCCESS: {FULL_EXPRESSION}", workflow)
        self.assertIn("needs.stable.result == 'success' &&", workflow)

    def test_failed_daily_check_leaves_hourly_mutable_source_repairs_enabled(self):
        workflow = WORKFLOW.read_text()
        pause = workflow.split("      - name: Приостановить updater после сбоя\n", 1)[1]
        diagnostic = workflow.split("      - name: Сообщить о сбое ежедневной проверки\n", 1)[1]
        fail_run = workflow.split("      - name: Завершить workflow ошибкой при сбое gate\n", 1)[1]
        detect = UPDATER_WORKFLOW.read_text().split("\n  detect:\n", 1)[1]
        # A changed /latest/ archive can fail a scheduled checksum/build gate.
        # Preserve the pause state so the hourly updater can validate and publish
        # a fresh recipe. Ordinary post-push failures must still stop publication.
        for plan, stable in [("success", "failure"), ("failure", "skipped"), ("success", "cancelled")]:
            with self.subTest(plan=plan, stable=stable):
                values = {
                    "github.event_name": "schedule",
                    "needs.plan.result": plan,
                    "needs.stable.result": stable,
                }
                self.assertFalse(condition(pause, values))
                self.assertTrue(condition(diagnostic, values))
                self.assertTrue(condition(fail_run, values))
                self.assertTrue(condition(detect, {
                    "needs.pause_status.outputs.paused": "false",
                    "needs.pause_status.outputs.repair_allowed": "false", "inputs.force": False,
                }))
                # An existing post-push pause is preserved, never overridden.
                self.assertFalse(condition(detect, {
                    "needs.pause_status.outputs.paused": "true",
                    "needs.pause_status.outputs.repair_allowed": "false", "inputs.force": False,
                }))
                values["github.event_name"] = "workflow_dispatch"
                self.assertTrue(condition(pause, values))
                self.assertFalse(condition(diagnostic, values))

    def test_only_successful_full_verification_can_attempt_resume(self):
        resume = WORKFLOW.read_text().split(
            "      - name: Восстановить обновления после полной проверки текущего main\n", 1,
        )[1]
        for event, full in [("schedule", False), ("workflow_dispatch", True)]:
            for plan, stable in [("success", "success"), ("success", "skipped"), ("failure", "skipped")]:
                with self.subTest(event=event, plan=plan, stable=stable):
                    self.assertEqual(condition(resume, {
                        "github.event_name": event,
                        "inputs.resume_on_success": full,
                        "needs.plan.result": plan,
                        "needs.stable.result": stable,
                    }), plan == stable == "success")
        self.assertFalse(condition(resume, {
            "github.event_name": "workflow_dispatch",
            "inputs.resume_on_success": False,
            "needs.plan.result": "success",
            "needs.stable.result": "success",
        }))

    def test_paused_repair_requires_a_read_only_full_job_and_exact_tree_proof(self):
        workflow = UPDATER_WORKFLOW.read_text()
        repair = workflow.split("\n  repair:\n", 1)[1].split("\n  publish:\n", 1)[0]
        publish = workflow.split("\n  publish:\n", 1)[1]
        detect = workflow.split("\n  detect:\n", 1)[1]
        self.assertIn("permissions:\n      contents: read\n", repair)
        self.assertNotIn(": write", repair)
        self.assertNotIn("GH_TOKEN:", repair)
        self.assertIn("ref: ${{ needs.detect.outputs.base_sha }}", repair)
        self.assertIn("EXPECTED_BASE_SHA: ${{ needs.detect.outputs.base_sha }}", repair)
        self.assertIn(".github/tools/validate_paused_repair.sh", repair)
        self.assertIn("needs: [pause_status, detect, update, repair]", publish)
        self.assertIn("NIVORA_CHECK_UPDATER_PAUSE: '1'", publish)
        self.assertIn("NIVORA_VERIFIED_REPAIR_TREE: ${{ needs.repair.outputs.tree }}", publish)
        self.assertIn("RESUME_ON_SUCCESS: ${{ needs.repair.result == 'success' }}", publish)
        self.assertIn('-f resume_on_success="$RESUME_ON_SUCCESS"', publish)
        self.assertTrue(condition(detect, {
            "needs.pause_status.outputs.paused": "true",
            "needs.pause_status.outputs.repair_allowed": "true", "inputs.force": False,
        }))
        self.assertTrue(condition(repair, {
            "cancelled()": False,
            "needs.pause_status.outputs.paused": "true",
            "needs.update.result": "success", "needs.update.outputs.successful": '["parsec"]',
        }))
        for name in ["Применить только успешные обновления", "Отправить обновления прямо в main"]:
            gate = publish.split(f"      - name: {name}\n", 1)[1]
            for result in ["success", "failure", "skipped", "cancelled"]:
                with self.subTest(step=name, repair=result):
                    self.assertEqual(condition(gate, {
                        "steps.publication_base.outputs.fresh": "true",
                        "needs.pause_status.outputs.paused": "true",
                        "needs.repair.result": result,
                    }), result == "success")
        # A failed combined gate still reaches trusted issue reporting on the
        # pristine base, so identical candidates retain their 6-hour cooldown.
        report = publish.split("      - name: Синхронизировать постоянные отчёты о сбоях\n", 1)[1]
        self.assertTrue(condition(report, {
            "always()": True,
            "steps.artifact_gate.outcome": "success",
            "steps.publish.outcome": "skipped",
            "steps.publish.outputs.pushed": "",
            "steps.publish.outputs.reason": "",
            "needs.pause_status.outputs.paused": "true",
            "needs.repair.result": "failure",
            "needs.update.outputs.successful": '["parsec"]',
        }))

    def test_scheduled_or_recovery_run_executes_the_full_real_catalogue_plan(self):
        workflow = WORKFLOW.read_text()
        with (ROOT / ".github/support-matrix.toml").open("rb") as stream:
            matrix = tomllib.load(stream)
        expected = sorted(package["id"] for package in matrix["packages"])
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "github-output"
            result = subprocess.run(
                ["bash", "-euo", "pipefail", "-c", planning_step(workflow)],
                cwd=ROOT,
                env={**os.environ, "RESUME_ON_SUCCESS": "true", "GITHUB_OUTPUT": str(output)},
                capture_output=True,
                text=True,
                check=True,
            )
            plan = json.loads(result.stdout)
            self.assertEqual(plan["packages"], expected)
            self.assertTrue(plan["full"])
            self.assertTrue(plan["has_packages"])
            self.assertIn("full=true\n", output.read_text())


if __name__ == "__main__":
    unittest.main()
