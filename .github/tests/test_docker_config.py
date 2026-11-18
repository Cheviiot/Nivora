import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


TOOLS = Path(__file__).resolve().parents[1] / "tools"

# Model Docker's config/context lookup, including TLS files and credential-store
# autodetection. Execute the real caller setup and cleanup; stop at Stapler
# preparation so no daemon, image download or package transaction is needed.
DOCKER = r'''#!/usr/bin/env python3
import hashlib
import json
import os
import sys
from pathlib import Path

root = Path(os.environ["DOCKER_CONFIG"])
config_file = root / "config.json"
config = json.loads(config_file.read_text()) if config_file.exists() else {}
context = os.environ.get("DOCKER_CONTEXT") or (
    "default" if os.environ.get("DOCKER_HOST") else config.get("currentContext") or "default"
)
tls = None
if context == "default":
    host = os.environ.get("DOCKER_HOST") or "unix:///var/run/docker.sock"
    if os.environ.get("DOCKER_TLS") or os.environ.get("DOCKER_TLS_VERIFY"):
        tls = Path(os.environ.get("DOCKER_CERT_PATH") or root)
else:
    key = hashlib.sha256(context.encode()).hexdigest()
    metadata = json.loads((root / "contexts/meta" / key / "meta.json").read_text())
    host = metadata["Endpoints"]["docker"]["Host"]
    tls_path = root / "contexts/tls" / key / "docker"
    if tls_path.exists():
        tls = tls_path
certificates = {
    name: hashlib.sha256((tls / name).read_bytes()).hexdigest()
    for name in ("ca.pem", "cert.pem", "key.pem")
} if tls else {}
credential_store = config.get("credsStore", "")
if not credential_store and not config.get("credHelpers") and not config.get("auths"):
    credential_store = "autodetected-personal-store"
record = {
    "args": sys.argv[1:],
    "phase": os.environ.get("NIVORA_DOCKER_TEST_PHASE", "setup"),
    "connection": {"context": context, "host": host, "tls": certificates,
                   "headers": config.get("HttpHeaders", {})},
    "config": config,
    "config_dir": str(root),
    "config_mode": root.stat().st_mode & 0o777 if root.exists() else None,
    "credential_store": credential_store,
    "environment": {name: os.environ.get(name) for name in (
        "DOCKER_HOST", "DOCKER_CONTEXT", "DOCKER_CERT_PATH", "DOCKER_TLS", "DOCKER_TLS_VERIFY"
    )},
    "build_context": os.environ.get("NIVORA_DOCKER_TEST_BUILD_CONTEXT"),
}
with open(os.environ["NIVORA_DOCKER_TEST_LOG"], "a") as stream:
    stream.write(json.dumps(record) + "\n")
assert sys.argv[1:] == ["info"] or sys.argv[1:3] in (["volume", "rm"], ["image", "rm"])
'''


class DockerConfigTests(unittest.TestCase):
    def run_setup(self, scenario):
        with tempfile.TemporaryDirectory(prefix="nivora-docker-config-") as directory:
            root = Path(directory)
            repo = root / "repo"
            tools = repo / ".github/tools"
            (tools / "lib").mkdir(parents=True)
            (repo / "anidesk").mkdir()
            (repo / "anidesk/Staplerfile").touch()
            for name in ("clean_build.sh", "test_package_lifecycle.sh"):
                shutil.copy2(TOOLS / name, tools / name)
            for name in ("alt_builder.sh", "alt_branch.sh", "alt_apt_network.sh", "source_cache.sh"):
                shutil.copy2(TOOLS / "lib" / name, tools / "lib" / name)
            prepare = tools / "prepare_stplr.sh"
            prepare.write_text(
                '#!/bin/bash\nset -euo pipefail\n'
                'NIVORA_DOCKER_TEST_PHASE=prepared '
                'NIVORA_DOCKER_TEST_BUILD_CONTEXT="$(dirname "$1")" docker info\n'
                'exit 23\n',
                encoding="utf-8",
            )
            prepare.chmod(0o755)
            binary = root / "bin"
            binary.mkdir()
            (binary / "docker").write_text(DOCKER, encoding="utf-8")
            (binary / "docker").chmod(0o755)
            for name in ("rpm", "rpmbuild", "sqlite3", "stplr-spec"):
                path = binary / name
                path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
                path.chmod(0o755)

            original = root / "original-config"
            original.mkdir()
            config = {
                "currentContext": "builder",
                "HttpHeaders": {"X-Fixture-Endpoint": "selected-daemon"},
                "auths": {"registry.invalid": {"auth": "fixture-personal-secret"}},
                "credsStore": "personal-store",
                "credHelpers": {"registry.invalid": "personal-helper"},
                "proxies": {"default": {"httpProxy": "http://fixture:secret@proxy.invalid"}},
                "plugins": {"fixture": {"private-setting": "private-value"}},
            }

            def certificates(path, marker):
                path.mkdir(parents=True, exist_ok=True)
                for name in ("ca.pem", "cert.pem", "key.pem"):
                    (path / name).write_text(marker + ":" + name, encoding="utf-8")

            for context in ("builder", "override"):
                key = hashlib.sha256(context.encode()).hexdigest()
                metadata = original / "contexts/meta" / key / "meta.json"
                metadata.parent.mkdir(parents=True)
                metadata.write_text(json.dumps({
                    "Name": context,
                    "Endpoints": {"docker": {"Host": f"tcp://{context}.invalid:2376"}},
                }), encoding="utf-8")
                certificates(original / "contexts/tls" / key / "docker", context)
            (original / "config.json").write_text(json.dumps(config), encoding="utf-8")

            environment = {
                key: value for key, value in os.environ.items()
                if not key.startswith(("DOCKER_", "NIVORA_", "GITHUB_"))
            } | {
                "PATH": f"{binary}:{os.environ['PATH']}",
                "BASH_ENV": "/dev/null",
                "NIVORA_CONTAINER_ENGINE": "docker",
                "NIVORA_ALT_BUILDER_IMAGE": "registry.altlinux.org/p11/base@sha256:" + "a" * 64,
                "NIVORA_LIFECYCLE_PACKAGES": "anidesk",
                "DOCKER_CONFIG": str(original),
            }
            if scenario == "environment-context":
                environment["DOCKER_CONTEXT"] = "override"
            elif scenario in ("default-tls", "external-tls"):
                environment.update(DOCKER_HOST="tcp://legacy.invalid:2376", DOCKER_TLS_VERIFY="1")
                certificates(original, "legacy-default")
                if scenario == "external-tls":
                    certificates(root / "external-certs", "legacy-external")
                    environment["DOCKER_CERT_PATH"] = str(root / "external-certs")
            elif scenario == "no-config":
                shutil.rmtree(original)
            original_files = {
                path.relative_to(original): path.read_bytes()
                for path in original.rglob("*") if path.is_file()
            }

            for script in ("clean_build.sh", "test_package_lifecycle.sh"):
                with self.subTest(script=script, scenario=scenario):
                    log = root / (script + ".log")
                    result = subprocess.run(
                        ["bash", str(tools / script)] + (["anidesk"] if script == "clean_build.sh" else []),
                        env=environment | {"NIVORA_DOCKER_TEST_LOG": str(log)},
                        text=True, capture_output=True,
                    )
                    self.assertEqual(result.returncode, 23, result.stdout + result.stderr)
                    calls = [json.loads(line) for line in log.read_text().splitlines()]
                    self.assertEqual(len(calls), 4, calls)
                    self.assertEqual(calls[0]["args"], ["info"])
                    prepared = calls[1]
                    self.assertEqual(prepared["phase"], "prepared")
                    for call in calls[1:]:
                        self.assertEqual(call["connection"], calls[0]["connection"])
                        self.assertEqual(call["environment"], calls[0]["environment"])
                        self.assertEqual(call["config_dir"], prepared["config_dir"])
                        self.assertEqual(call["config_mode"], 0o700)
                        self.assertEqual(call["credential_store"], "")
                        self.assertNotIn("credHelpers", call["config"])
                        self.assertNotIn("proxies", call["config"])
                        self.assertNotIn("plugins", call["config"])
                        self.assertTrue(call["config"]["auths"])
                        self.assertTrue(all(not auth for auth in call["config"]["auths"].values()))
                    isolated = Path(prepared["config_dir"])
                    self.assertNotEqual(isolated, original)
                    self.assertFalse(isolated.is_relative_to(Path(prepared["build_context"])))
                    self.assertFalse(isolated.exists(), "private Docker config leaked after failure cleanup")
                    self.assertEqual(original_files, {
                        path.relative_to(original): path.read_bytes()
                        for path in original.rglob("*") if path.is_file()
                    })

    def test_configured_context_keeps_endpoint_and_context_tls(self):
        self.run_setup("configured-context")

    def test_environment_selected_context_is_preserved(self):
        self.run_setup("environment-context")

    def test_default_context_keeps_tls_files_from_original_config(self):
        self.run_setup("default-tls")

    def test_explicit_certificate_path_is_preserved(self):
        self.run_setup("external-tls")

    def test_no_existing_config_uses_anonymous_default_daemon(self):
        self.run_setup("no-config")


if __name__ == "__main__":
    unittest.main()
