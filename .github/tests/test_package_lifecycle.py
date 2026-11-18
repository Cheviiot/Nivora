import json
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools/test_package_lifecycle.sh"
SOURCE = SCRIPT.read_text(encoding="utf-8")
CONTAINER_SCRIPT = re.search(
    r"cat >\"\$\{work_dir\}/run-rpm.sh\" <<'EOF'\n(.*?)\nEOF",
    SOURCE,
    re.DOTALL,
).group(1)

# Execute the real container script. Only the RPM database, package-manager
# transactions and user creation are fixtures; the lifecycle decisions,
# installed-file checks and persistent-data checks are production shell code.
DRIVER = r'''import json
import os
import sys
from pathlib import Path

root = Path(os.environ["FIXTURE_ROOT"])
database = root / "rpm-state.json"
state = json.loads(database.read_text())
role, *args = sys.argv[1:]
package = os.environ["TEST_PACKAGE"]
rpm_license = os.environ["TEST_RPM_LICENSE"]
config = root / "etc/default/tailscaled"

def trace(message):
    with (root / "transactions").open("a") as stream:
        stream.write(message + "\n")

def save():
    database.write_text(json.dumps(state))

def evr(kind):
    return "0:1-alt1" if kind == "previous" else "0:2-alt1"

if role == "rpm":
    if args[0] == "--eval":
        print("x86_64")
    elif args[0] == "-qp":
        artifact = Path(args[-1])
        assert artifact.is_file(), artifact
        previous = artifact.parent.name == "previous"
        if args[2] == '[%{FILEFLAGS}\\t%{FILENAMES}\\n]':
            print(os.environ["TEST_PREVIOUS_CONFIG_FLAGS"] + "\t" + str(config))
            sys.exit(0)
        values = {
            "%{NAME}": package + "+stplr-default",
            "%{EPOCHNUM}:%{VERSION}-%{RELEASE}": evr("previous" if previous else "current"),
            "%{ARCH}": "noarch" if previous else "x86_64",
            "%{LICENSE}": rpm_license,
            "%{SUMMARY}": "Previous Nivora package fixture for lifecycle tests",
        }
        print(values[args[2]])
    elif args[0] == "-q":
        name = args[-1]
        installed = state["bc"] if name == "bc" else state["installed"]
        if not installed:
            sys.exit(1)
        print(evr(installed) if "--queryformat" in args else name)
    elif args[0] == "-Uvh":
        trace("test upgrade")
        sys.exit(0 if state["installed"] == "previous" else 1)
    else:
        raise AssertionError(args)
elif role == "apt":
    if "install" in args:
        previous = Path(args[-1]).parent.name == "previous"
        if previous:
            assert state["installed"] is None
            state.update(installed="previous", bc=True)
            trace("install previous")
            if package == "tailscale":
                config.parent.mkdir(parents=True)
                config.write_text('PORT="41641"\nFLAGS=""\n')
        else:
            kind = "fresh" if state["installed"] is None else "upgrade"
            trace("install current " + kind)
            if kind == "fresh" and os.environ["TEST_FAIL_FRESH"] == "1":
                print("fixture apt install failed", file=sys.stderr)
                sys.exit(23)
            count = os.environ["TEST_NOTICE_COUNT"]
            count = int(kind == "fresh") if count == "auto" else int(count)
            if rpm_license == "LicenseRef-proprietary":
                notice = f"проприетарная. Условия в /usr/share/licenses/{package}/LICENSE.nivora"
            else:
                notice = f"{rpm_license}. Подробности в /usr/share/licenses/{package}/"
            for _ in range(count):
                print(f"Лицензия {package} — {notice}", file=sys.stderr)
            state["installed"] = "current"
            command = root / "command"
            command.write_text("#!/bin/sh\nexit 0\n")
            command.chmod(0o755)
            if os.environ["TEST_MUTATE_STAGE"] == "install":
                (root / "user-data/state").write_text("overwritten on install\n")
            if package == "tailscale" and (kind == "fresh" or os.environ["TEST_CONFIG_MUTATE_STAGE"] == "install"):
                config.parent.mkdir(parents=True, exist_ok=True)
                config.write_text('PORT="41641"\nFLAGS=""\n')
    elif "remove" in args:
        assert state["installed"] == "current"
        trace("remove current")
        state["installed"] = None
        (root / "command").unlink()
        if os.environ["TEST_MUTATE_STAGE"] == "remove":
            (root / "user-data/state").write_text("overwritten on remove\n")
        if package == "tailscale":
            mode = os.environ["TEST_CONFIG_REMOVE"]
            if mode == "delete":
                config.unlink()
            elif mode != "keep":
                saved = config.with_suffix(".rpmsave")
                config.rename(saved)
                if mode == "corrupt":
                    saved.write_text("overwritten on remove\n")
    else:
        raise AssertionError(args)
    save()
else:
    raise AssertionError(role)
'''


class PackageLifecycleTests(unittest.TestCase):
    def run_scenario(self, scenario, *, fail_fresh=False, mutate_stage="", package="demo",
                     config_mutate_stage="", config_remove="rpmsave", previous_config_flags="0",
                     rpm_license=None, notice_count=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "bin").mkdir()
            (root / "repo" / package).mkdir(parents=True)
            (root / "repo" / package / "current.rpm").touch()
            if scenario == "upgrade":
                (root / "previous").mkdir()
                (root / "previous" / f"{package}.rpm").touch()
            (root / "rpm-state.json").write_text(
                json.dumps({"installed": None, "bc": False}), encoding="utf-8"
            )
            driver = root / "driver.py"
            driver.write_text(DRIVER, encoding="utf-8")
            for name, role in (("rpm", "rpm"), ("apt.sh", "apt")):
                path = root / "bin" / name
                path.write_text(
                    f'#!/bin/bash\nexec python3 "$FIXTURE_ROOT/driver.py" {role} "$@"\n',
                    encoding="utf-8",
                )
                path.chmod(0o755)
            useradd = root / "bin/useradd"
            useradd.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            useradd.chmod(0o755)
            script = root / "run-lifecycle.sh"
            script.write_text(
                CONTAINER_SCRIPT.replace("/repo/", f"{root}/repo/")
                .replace("/previous/", f"{root}/previous/")
                .replace("/etc/default/tailscaled", str(root / "etc/default/tailscaled"))
                .replace("/usr/local/lib/nivora/alt_apt_network.sh", str(root / "bin/apt.sh")),
                encoding="utf-8",
            )
            environment = os.environ | {
                "PATH": f"{root}/bin:{os.environ['PATH']}",
                "BASH_ENV": "/dev/null",
                "FIXTURE_ROOT": str(root),
                "LIFECYCLE_ENTRY": f"{package}|{root}/command|{root}/user-data/state|-|-|-",
                "LIFECYCLE_SCENARIO": scenario,
                "NIVORA_ALT_BRANCH": "p11",
                "TEST_FAIL_FRESH": "1" if fail_fresh else "0",
                "TEST_MUTATE_STAGE": mutate_stage,
                "TEST_PACKAGE": package,
                "TEST_RPM_LICENSE": rpm_license or ("BSD-3-Clause" if package == "tailscale" else "MIT"),
                "TEST_NOTICE_COUNT": "auto" if notice_count is None else str(notice_count),
                "TEST_CONFIG_MUTATE_STAGE": config_mutate_stage,
                "TEST_CONFIG_REMOVE": config_remove,
                "TEST_PREVIOUS_CONFIG_FLAGS": previous_config_flags,
            }
            result = subprocess.run(
                ["bash", str(script)], env=environment, text=True, capture_output=True
            )
            trace = root / "transactions"
            transactions = trace.read_text().splitlines() if trace.is_file() else []
            return result, transactions

    def test_fresh_install_does_not_use_a_previous_rpm(self):
        for license_id, notice in (
            ("MIT", "Лицензия demo — MIT. Подробности в /usr/share/licenses/demo/"),
            ("LicenseRef-proprietary", "Лицензия demo — проприетарная. Условия в /usr/share/licenses/demo/LICENSE.nivora"),
        ):
            with self.subTest(license=license_id):
                result, transactions = self.run_scenario("fresh", rpm_license=license_id)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(transactions, ["install current fresh", "remove current"])
                self.assertIn(notice, result.stdout + result.stderr)

    def test_upgrade_keeps_the_previous_transaction_and_order_check(self):
        result, transactions = self.run_scenario("upgrade", fail_fresh=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("Лицензия demo", result.stdout + result.stderr)
        self.assertEqual(
            transactions,
            ["install previous", "test upgrade", "install current upgrade", "remove current"],
        )

    def test_fresh_only_installation_failure_is_a_gate_failure(self):
        result, transactions = self.run_scenario("fresh", fail_fresh=True)
        self.assertEqual(result.returncode, 23, result.stdout + result.stderr)
        self.assertIn("fixture apt install failed", result.stdout + result.stderr)
        self.assertEqual(transactions, ["install current fresh"])

    def test_fresh_install_requires_one_license_notice(self):
        for license_id in ("MIT", "LicenseRef-proprietary"):
            for count in (0, 2):
                with self.subTest(license=license_id, count=count):
                    result, transactions = self.run_scenario(
                        "fresh", rpm_license=license_id, notice_count=count,
                    )
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("expected 1", result.stderr)
                    self.assertEqual(transactions, ["install current fresh"])

    def test_upgrade_rejects_a_repeated_license_notice(self):
        for license_id in ("MIT", "LicenseRef-proprietary"):
            with self.subTest(license=license_id):
                result, transactions = self.run_scenario(
                    "upgrade", rpm_license=license_id, notice_count=1,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("expected 0", result.stderr)
                self.assertEqual(transactions[-1], "install current upgrade")

    def test_preserved_filename_cannot_hide_overwritten_user_data(self):
        for scenario in ("fresh", "upgrade"):
            for stage in ("install", "remove"):
                with self.subTest(scenario=scenario, stage=stage):
                    result, _ = self.run_scenario(scenario, mutate_stage=stage)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("changed persistent state", result.stderr)

    def test_tailscale_settings_survive_install_or_upgrade_and_removal(self):
        for scenario in ("fresh", "upgrade"):
            for config_remove in ("rpmsave", "keep"):
                with self.subTest(scenario=scenario, removal=config_remove):
                    result, _ = self.run_scenario(
                        scenario, package="tailscale", config_remove=config_remove,
                    )
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_tailscale_upgrade_detects_overwritten_old_ordinary_config(self):
        result, transactions = self.run_scenario(
            "upgrade", package="tailscale", config_mutate_stage="install",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("lost configured tailscaled settings", result.stderr)
        self.assertEqual(transactions, ["install previous", "test upgrade", "install current upgrade"])

    def test_tailscale_removal_must_preserve_configured_bytes(self):
        for scenario in ("fresh", "upgrade"):
            for mode in ("delete", "corrupt"):
                with self.subTest(scenario=scenario, removal=mode):
                    result, _ = self.run_scenario(scenario, package="tailscale", config_remove=mode)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("lost configured tailscaled settings", result.stderr)

    def test_tailscale_previous_fixture_cannot_mask_migration_with_config_flags(self):
        result, transactions = self.run_scenario(
            "upgrade", package="tailscale", previous_config_flags="17",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("previous fixture must own ordinary", result.stderr)
        self.assertEqual(transactions, [])

    def test_each_package_gets_two_disposable_containers(self):
        loop = SOURCE[SOURCE.index("while IFS= read -r lifecycle_entry; do\n"):]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "lifecycle-packages.txt").write_text("alpha|entry\nbeta|entry\n")
            engine = root / "engine"
            engine.write_text(
                "#!/usr/bin/env python3\n"
                "import json, os, sys\n"
                "with open(os.environ['FIXTURE_ROOT'] + '/runs', 'a') as stream:\n"
                "    stream.write(json.dumps(sys.argv[1:]) + '\\n')\n",
                encoding="utf-8",
            )
            engine.chmod(0o755)
            environment = os.environ | {
                "BASH_ENV": "/dev/null", "FIXTURE_ROOT": str(root),
                "engine": str(engine), "work_dir": str(root),
                "repo_root": str(root / "repo"), "branch": "p11", "rpm_image": "fixture",
            }
            result = subprocess.run(
                ["bash", "-c", "set -euo pipefail\npackages=(alpha beta)\n" + loop],
                env=environment, text=True, capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            runs = [json.loads(line) for line in (root / "runs").read_text().splitlines()]
            self.assertEqual(len(runs), 4)
            for call, (package, scenario) in zip(
                runs, ((package, scenario) for package in ("alpha", "beta")
                       for scenario in ("fresh", "upgrade")), strict=True
            ):
                self.assertEqual(call[0:2], ["run", "--rm"])
                self.assertIn(f"LIFECYCLE_ENTRY={package}|entry", call)
                self.assertIn(f"LIFECYCLE_SCENARIO={scenario}", call)


if __name__ == "__main__":
    unittest.main()
