#!/usr/bin/env python3

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


PACKAGE_DIR = Path(__file__).resolve().parents[2] / "netbird"
UNIT_PATH = Path("usr/lib/systemd/system/netbird.service")


class ServiceLifecycleTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.manager = self.root / "run/systemd/system"
        self.manager.mkdir(parents=True)
        unit = self.root / UNIT_PATH
        unit.parent.mkdir(parents=True)
        shutil.copyfile(PACKAGE_DIR / UNIT_PATH.name, unit)
        self.enabled = self.root / "etc/systemd/system/multi-user.target.wants/netbird.service"
        self.calls = self.root / "calls"
        systemctl = self.root / "systemctl"
        systemctl.write_text(
            "#!/bin/bash\n"
            "printf '%s\\n' \"$*\" >>\"$TEST_CALLS\"\n"
            "[[ \"${TEST_FAIL:-0}\" == 0 ]] || exit 1\n"
            'case "$*" in\n'
            '    "enable --now netbird.service")\n'
            '        exec "$TEST_SYSTEMCTL" --root "$TEST_ROOT" enable netbird.service ;;\n'
            '    "--no-reload disable netbird.service")\n'
            '        exec "$TEST_SYSTEMCTL" --root "$TEST_ROOT" --no-reload disable netbird.service ;;\n'
            '    daemon-reload | "try-restart netbird.service" | "stop netbird.service") exit 0 ;;\n'
            '    *) exit 2 ;;\n'
            'esac\n'
        )
        systemctl.chmod(0o755)
        self.env = dict(
            os.environ,
            PATH=f"{self.root}:{os.environ['PATH']}",
            TEST_ROOT=str(self.root),
            TEST_CALLS=str(self.calls),
            TEST_SYSTEMCTL=shutil.which("systemctl"),
        )

    def run_hook(self, hook, count, *, fail=False):
        self.calls.write_text("")
        # Point the hook's systemd detection at the isolated unit tree.
        script = (PACKAGE_DIR / f"{hook}.sh").read_text()
        script = script.replace("/run/systemd/system", str(self.manager))
        result = subprocess.run(
            ["bash", "-c", script, hook, str(count)],
            env=dict(self.env, TEST_FAIL=str(int(fail))),
            check=True,
            capture_output=True,
            text=True,
        )
        return self.calls.read_text().splitlines(), result.stderr

    def test_install_and_final_removal(self):
        calls, _ = self.run_hook("postinstall", 1)
        self.assertEqual(calls, ["daemon-reload", "enable --now netbird.service"])
        self.assertTrue(self.enabled.is_symlink())

        calls, _ = self.run_hook("preremove", 0)
        self.assertEqual(calls, ["--no-reload disable netbird.service", "stop netbird.service"])
        self.assertFalse(self.enabled.is_symlink())

        (self.root / UNIT_PATH).unlink()
        calls, _ = self.run_hook("postremove", 0)
        self.assertEqual(calls, ["daemon-reload"])

    def test_upgrade_preserves_service_enablement(self):
        for enabled in (False, True):
            with self.subTest(enabled=enabled):
                if enabled:
                    self.run_hook("postinstall", 1)
                calls, _ = self.run_hook("postinstall", 2)
                self.assertEqual(calls, ["daemon-reload", "try-restart netbird.service"])
                calls, _ = self.run_hook("preremove", 1)
                self.assertEqual(calls, [])
                calls, _ = self.run_hook("postremove", 1)
                self.assertEqual(calls, ["daemon-reload"])
                self.assertEqual(self.enabled.is_symlink(), enabled)

    def test_offline_and_failing_systemd(self):
        calls, stderr = self.run_hook("postinstall", 1, fail=True)
        self.assertEqual(calls, ["daemon-reload", "enable --now netbird.service"])
        self.assertIn("systemctl daemon-reload", stderr)
        self.assertIn("systemctl enable --now netbird.service", stderr)
        calls, _ = self.run_hook("preremove", 0, fail=True)
        self.assertEqual(calls, ["--no-reload disable netbird.service", "stop netbird.service"])
        self.run_hook("postremove", 0, fail=True)

        self.manager.rmdir()
        for hook, count in (("postinstall", 1), ("preremove", 0), ("postremove", 0)):
            with self.subTest(hook=hook):
                calls, _ = self.run_hook(hook, count)
                self.assertEqual(calls, [])


if __name__ == "__main__":
    unittest.main()
