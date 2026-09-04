import os
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


SOURCE_SCRIPT = (
    Path(__file__).resolve().parents[1] / "tools" / "target_lifecycle.sh"
)


class TargetLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repo"
        self.tools = self.repo / ".github" / "tools"
        self.package_dir = self.repo / "nivora-cli"
        self.bin_dir = self.root / "bin"
        self.test_root = self.root / "target-root"
        self.state = self.root / "installed"
        self.log = self.root / "commands.log"
        self.os_release = self.root / "os-release"
        self.apparmor_userns = self.root / "apparmor-userns"
        self.runner_temp = self.root / "runner-temp"
        self.builder_state = self.root / "builder-user"
        self.wheel_state = self.root / "wheel-group"
        self.stplr_cache = self.root / "stplr-cache"
        for directory in (
            self.tools,
            self.package_dir,
            self.bin_dir,
            self.test_root,
            self.runner_temp,
        ):
            directory.mkdir(parents=True, exist_ok=True)
        script = self.tools / "target_lifecycle.sh"
        script.write_bytes(SOURCE_SCRIPT.read_bytes())
        script.chmod(0o755)
        (self.package_dir / "Staplerfile").write_text(
            textwrap.dedent(
                """\
                name='nivora-cli'
                version='1.1.0'
                release=1
                architectures=('all')
                package() { :; }
                """
            ),
            encoding="utf-8",
        )
        (self.package_dir / "payload").write_text("fixture\n", encoding="utf-8")
        self.os_release.write_text(
            'ID=ubuntu\nVERSION_ID="24.04"\nPRETTY_NAME="Ubuntu 24.04 LTS"\n',
            encoding="utf-8",
        )
        self.apparmor_userns.write_text("1\n", encoding="utf-8")
        self.write_executable(
            "uname",
            """
            if [[ "${1:-}" == '-m' ]]; then
                printf '%s\\n' "$FAKE_UNAME_MACHINE"
            else
                printf 'Linux lifecycle-fixture 6.8.0 #1 SMP %s GNU/Linux\\n' \
                    "$FAKE_UNAME_MACHINE"
            fi
            """,
        )
        self.write_executable(
            "stplr",
            """
            if [[ "${1:-}" == 'version' ]]; then
                printf '%s\\n' "${FAKE_STPLR_VERSION:-v0.1.1}"
                exit 0
            fi
            printf 'stplr cwd=%s args=%s\\n' "$PWD" "$*" >>"$LIFECYCLE_LOG"
            [[ "${FAKE_STPLR_BUILD_FAIL:-0}" != '1' ]] || exit 42
            touch 'nivora-cli+stplr-default_1.1.0-1_all.deb'
            """,
        )
        self.write_executable(
            "dpkg-deb",
            """
            case "${3:-}" in
                Package) printf '%s\\n' "${FAKE_DEB_PACKAGE:-nivora-cli+stplr-default}" ;;
                Version) printf '%s\\n' "${FAKE_DEB_VERSION:-1.1.0-1}" ;;
                Architecture) printf '%s\\n' "${FAKE_DEB_ARCH:-all}" ;;
                *) exit 2 ;;
            esac
            """,
        )
        self.write_executable(
            "dpkg-query",
            """
            if [[ -f "$LIFECYCLE_STATE" ]]; then
                printf 'nivora-cli+stplr-default\\n'
                exit 0
            fi
            exit 1
            """,
        )
        self.write_executable(
            "apt-get",
            """
            printf 'apt-get %s\\n' "$*" >>"$LIFECYCLE_LOG"
            case "${1:-}" in
                update) ;;
                install)
                    touch "$LIFECYCLE_STATE"
                    install -d "$NIVORA_TEST_ROOT/usr/bin"
                    cat >"$NIVORA_TEST_ROOT/usr/bin/nv" <<'SMOKE'
            #!/bin/bash
            printf 'Nivora CLI 1.1.0\\n'
            printf 'smoke %s\\n' "$*" >>"$LIFECYCLE_LOG"
            SMOKE
                    chmod 0755 "$NIVORA_TEST_ROOT/usr/bin/nv"
                    ;;
                purge)
                    find "$NIVORA_TEST_ROOT/usr/bin" -mindepth 1 -delete
                    rm -f "$LIFECYCLE_STATE"
                    ;;
                *) exit 2 ;;
            esac
            """,
        )
        self.write_executable(
            "sudo",
            """
            while [[ "$#" -gt 0 ]]; do
                case "$1" in
                    -n) shift ;;
                    -u) shift 2 ;;
                    --) shift; break ;;
                    true) exit 0 ;;
                    *) break ;;
                esac
            done
            exec "$@"
            """,
        )
        self.write_executable(
            "getent",
            """
            case "${1:-}:${2:-}" in
                passwd:stapler-builder)
                    [[ -f "$LIFECYCLE_BUILDER_STATE" ]] || exit 2
                    printf 'stapler-builder:x:%s:%s::%s:/usr/sbin/nologin\\n' \
                        "$FAKE_BUILDER_UID" "$FAKE_BUILDER_GID" \
                        "$NIVORA_TEST_ROOT/home/stapler-builder"
                    ;;
                group:wheel)
                    [[ -f "$LIFECYCLE_WHEEL_STATE" ]] || exit 2
                    printf 'wheel:x:999:stapler-builder\\n'
                    ;;
                *) exit 2 ;;
            esac
            """,
        )
        self.write_executable(
            "useradd",
            """
            printf 'useradd %s\\n' "$*" >>"$LIFECYCLE_LOG"
            touch "$LIFECYCLE_BUILDER_STATE"
            """,
        )
        self.write_executable(
            "groupadd",
            """
            printf 'groupadd %s\\n' "$*" >>"$LIFECYCLE_LOG"
            touch "$LIFECYCLE_WHEEL_STATE"
            """,
        )
        self.write_executable(
            "usermod",
            """
            printf 'usermod %s\\n' "$*" >>"$LIFECYCLE_LOG"
            """,
        )
        self.write_executable(
            "chown",
            """
            printf 'chown %s\\n' "$*" >>"$LIFECYCLE_LOG"
            """,
        )
        self.write_executable(
            "runuser",
            """
            [[ "${1:-}" == '-u' ]]
            shift 2
            [[ "${1:-}" == '--' ]]
            shift
            exec "$@"
            """,
        )
        self.write_executable(
            "unshare",
            """
            printf 'unshare %s\\n' "$*" >>"$LIFECYCLE_LOG"
            if [[ "${FAKE_UNSHARE_REQUIRES_WORKAROUND:-0}" == '1' ]] \
                && [[ "$(cat "$NIVORA_APPARMOR_USERNS_PATH")" != '0' ]]; then
                exit 1
            fi
            """,
        )
        self.write_executable(
            "sysctl",
            """
            if [[ "${1:-}" == '-n' ]]; then
                cat "$NIVORA_APPARMOR_USERNS_PATH"
                exit 0
            fi
            [[ "${1:-}" == '-q' && "${2:-}" == '-w' ]]
            value="${3##*=}"
            printf '%s\\n' "$value" >"$NIVORA_APPARMOR_USERNS_PATH"
            printf 'sysctl %s\\n' "$3" >>"$LIFECYCLE_LOG"
            """,
        )

    def write_executable(self, name: str, body: str) -> None:
        path = self.bin_dir / name
        path.write_text(
            "#!/bin/bash\nset -euo pipefail\n"
            + textwrap.dedent(body).lstrip(),
            encoding="utf-8",
        )
        path.chmod(0o755)

    def run_lifecycle(self, **overrides: str) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.update(
            {
                "PATH": f"{self.bin_dir}:{environment['PATH']}",
                "TARGET_ID": "ubuntu-24.04",
                "PACKAGE": "nivora-cli",
                "STPLR_PATH": str(self.bin_dir / "stplr"),
                "EXPECTED_ARCH": "amd64",
                "GITHUB_ACTIONS": "true",
                "NIVORA_TESTING": "1",
                "NIVORA_TEST_ROOT": str(self.test_root),
                "NIVORA_OS_RELEASE_PATH": str(self.os_release),
                "NIVORA_APPARMOR_USERNS_PATH": str(self.apparmor_userns),
                "NIVORA_STPLR_CACHE_PATH": str(self.stplr_cache),
                "RUNNER_TEMP": str(self.runner_temp),
                "FAKE_UNAME_MACHINE": "x86_64",
                "LIFECYCLE_STATE": str(self.state),
                "LIFECYCLE_LOG": str(self.log),
                "LIFECYCLE_BUILDER_STATE": str(self.builder_state),
                "LIFECYCLE_WHEEL_STATE": str(self.wheel_state),
                "FAKE_BUILDER_UID": str(os.getuid()),
                "FAKE_BUILDER_GID": str(os.getgid()),
            }
        )
        environment.update(overrides)
        return subprocess.run(
            [str(self.tools / "target_lifecycle.sh")],
            cwd=self.root,
            env=environment,
            check=False,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def test_full_lifecycle_is_native_and_uses_a_temporary_recipe_copy(self):
        for machine, expected_arch in (("x86_64", "amd64"), ("aarch64", "arm64")):
            with self.subTest(machine=machine):
                self.log.unlink(missing_ok=True)
                self.builder_state.unlink(missing_ok=True)
                self.wheel_state.unlink(missing_ok=True)
                result = self.run_lifecycle(
                    FAKE_UNAME_MACHINE=machine, EXPECTED_ARCH=expected_arch
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("ID=ubuntu", result.stdout)
                self.assertIn("GNU/Linux", result.stdout)
                self.assertIn(
                    f"lifecycle passed on ubuntu-24.04/{expected_arch}",
                    result.stdout,
                )
                commands = self.log.read_text(encoding="utf-8")
                self.assertIn("apt-get update", commands)
                self.assertIn("apt-get install -y --no-install-recommends", commands)
                self.assertIn("apt-get purge -y nivora-cli+stplr-default", commands)
                self.assertIn("smoke --version", commands)
                self.assertIn("useradd --system --user-group --create-home", commands)
                self.assertIn("groupadd --system wheel", commands)
                self.assertIn("usermod -a -G wheel stapler-builder", commands)
                build_line = next(
                    line for line in commands.splitlines() if line.startswith("stplr ")
                )
                self.assertNotIn(str(self.package_dir), build_line)
                self.assertFalse(self.state.exists())
                self.assertFalse((self.test_root / "usr/bin/nv").exists())
                self.assertEqual(
                    list(self.package_dir.glob("*.deb")),
                    [],
                    "the source package directory must remain unchanged",
                )

    def test_each_metadata_mismatch_stops_before_install(self):
        cases = (
            ("FAKE_DEB_PACKAGE", "other+stplr-default", "DEB package mismatch"),
            ("FAKE_DEB_VERSION", "1.1.0-99", "DEB version mismatch"),
            ("FAKE_DEB_ARCH", "amd64", "DEB architecture mismatch"),
        )
        for variable, value, message in cases:
            with self.subTest(field=variable):
                self.log.unlink(missing_ok=True)
                result = self.run_lifecycle(**{variable: value})
                self.assertEqual(result.returncode, 1)
                self.assertIn(message, result.stderr)
                commands = self.log.read_text(encoding="utf-8")
                self.assertNotIn("apt-get", commands)

    def test_unknown_target_and_package_are_rejected(self):
        target = self.run_lifecycle(TARGET_ID="debian-13")
        self.assertEqual(target.returncode, 2)
        self.assertIn("Unsupported target lifecycle", target.stderr)

        package = self.run_lifecycle(PACKAGE="../nivora-cli")
        self.assertEqual(package.returncode, 2)
        self.assertIn("not in the lifecycle allowlist", package.stderr)

        for service_package in ("happ", "tailscale"):
            with self.subTest(service_package=service_package):
                service = self.run_lifecycle(PACKAGE=service_package)
                self.assertEqual(service.returncode, 2)
                self.assertIn("not in the lifecycle allowlist", service.stderr)

    def test_wrong_host_release_is_rejected(self):
        self.os_release.write_text(
            'ID=ubuntu\nVERSION_ID="26.04"\n', encoding="utf-8"
        )
        result = self.run_lifecycle()
        self.assertEqual(result.returncode, 2)
        self.assertIn("requires Ubuntu 24.04", result.stderr)

    def test_runner_architecture_must_match_the_requested_cell(self):
        result = self.run_lifecycle(EXPECTED_ARCH="arm64")
        self.assertEqual(result.returncode, 2)
        self.assertIn("does not match EXPECTED_ARCH arm64", result.stderr)

    def test_wrong_stapler_version_is_rejected(self):
        result = self.run_lifecycle(FAKE_STPLR_VERSION="v0.2.0")
        self.assertEqual(result.returncode, 2)
        self.assertIn("requires Stapler v0.1.1", result.stderr)

    def test_apparmor_userns_workaround_is_always_restored(self):
        result = self.run_lifecycle(FAKE_UNSHARE_REQUIRES_WORKAROUND="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.apparmor_userns.read_text(encoding="utf-8"), "1\n")
        commands = self.log.read_text(encoding="utf-8")
        self.assertIn(
            "sysctl kernel.apparmor_restrict_unprivileged_userns=0", commands
        )
        self.assertIn(
            "sysctl kernel.apparmor_restrict_unprivileged_userns=1", commands
        )

    def test_apparmor_userns_is_restored_when_build_fails(self):
        result = self.run_lifecycle(
            FAKE_UNSHARE_REQUIRES_WORKAROUND="1", FAKE_STPLR_BUILD_FAIL="1"
        )
        self.assertEqual(result.returncode, 42)
        self.assertEqual(self.apparmor_userns.read_text(encoding="utf-8"), "1\n")
        commands = self.log.read_text(encoding="utf-8")
        self.assertIn(
            "sysctl kernel.apparmor_restrict_unprivileged_userns=0", commands
        )
        self.assertIn(
            "sysctl kernel.apparmor_restrict_unprivileged_userns=1", commands
        )

    def test_non_ephemeral_host_is_rejected(self):
        result = self.run_lifecycle(GITHUB_ACTIONS="", NIVORA_EPHEMERAL_TARGET="0")
        self.assertEqual(result.returncode, 2)
        self.assertIn("explicitly ephemeral", result.stderr)


if __name__ == "__main__":
    unittest.main()
