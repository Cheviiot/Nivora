#!/bin/bash
# Exercise the production discovery/update helper without network access.
set -euo pipefail
package_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$package_dir" <<'PY'
import contextlib
import copy
import hashlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

package_dir = Path(sys.argv[1])
script = package_dir / ".stapler/update-run"
source = script.read_text().split("<<'PY'\n", 1)[1].rsplit("\nPY", 1)[0]
helper = {"__name__": "plugin_updater_test"}
exec(compile(source, str(script), "exec"), helper)

COMMIT = "777b48ffee5f84b411154355e35b68e2347fa0ff"
FINGERPRINT = hashlib.sha256(COMMIT.encode("ascii")).hexdigest()
VERSION = "0.3.0.git20260525192209"
HEAD = {"sha": COMMIT, "commit": {"committer": {"date": "2026-05-25T22:22:09+03:00"}}}
REAL_SPEC = os.environ.get("STPLR_SPEC_COMMAND") or shutil.which("stplr-spec")
REAL_RUN = subprocess.run


class PluginUpdaterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.recipe = self.directory / "Staplerfile"
        self.recipe.write_text(
            "name='gnome-software-plugin-stplr'\n"
            "version='0.3.0.git20260524192209'\nrelease=4\n"
            f"upstream_commit='{'a' * 40}'\n"
            f"source_fingerprint='{'b' * 64}'\n"
            "checksums=('sha256:old')\n# unrelated content\n"
        )
        self.recipe.chmod(0o640)
        self.tags = [{"name": "v0.1.0"}, {"name": "v0.3.0"}, {"name": "0.2.0"}]
        self.head = copy.deepcopy(HEAD)
        self.api_calls = []
        self.commands = []
        self.failure = None
        self.concurrent_change = False

        def fetch_json(path):
            self.api_calls.append(path)
            if path == "/tags?limit=100":
                return self.tags
            if path == "/git/commits/main":
                return self.head
            raise AssertionError(f"unexpected API request: {path}")

        self.helper_patch = patch.dict(helper, {"PACKAGE_DIR": self.directory, "fetch_json": fetch_json})
        self.helper_patch.start()
        self.addCleanup(self.helper_patch.stop)
        self.env_patch = patch.dict(os.environ, {"STPLR_PLUGIN_EXPECTED_FINGERPRINT": FINGERPRINT}, clear=True)
        self.env_patch.start()
        self.addCleanup(self.env_patch.stop)
        self.command_patch = patch.object(helper["subprocess"], "run", side_effect=self.run_spec)
        self.command_patch.start()
        self.addCleanup(self.command_patch.stop)

    def run_spec(self, command, **kwargs):
        self.commands.append(command)
        self.assertTrue(kwargs.get("check"))
        self.assertEqual(command[0], os.environ.get("STPLR_SPEC_COMMAND", "stplr-spec"))
        action, recipe_path = command[1], Path(command[3])
        text = recipe_path.read_text()
        if action == self.failure:
            raise subprocess.CalledProcessError(19, command)
        if action == "get-field":
            self.assertEqual(recipe_path, self.recipe)
            match = re.search(rf"^{command[4]}=(.*)$", text, re.M)
            self.assertIsNotNone(match)
            return subprocess.CompletedProcess(command, 0, match[1].strip("'\"") + "\n")
        self.assertNotEqual(recipe_path, self.recipe, "updates must only touch the staged recipe")
        self.assertEqual(recipe_path.parent, self.directory, "local sources must keep their base directory")
        if action == "set-field":
            # Match the real parser: set-field emits unquoted scalar values.
            text, count = re.subn(rf"^{command[4]}=.*$", f"{command[4]}={command[5]}", text, flags=re.M)
            self.assertEqual(count, 1)
        elif action == "update-checksums":
            text = text.replace("sha256:old", "sha256:updated")
            if self.concurrent_change:
                self.recipe.write_text(self.recipe.read_text() + "# concurrent edit\n")
        else:
            raise AssertionError(f"unexpected spec command: {command}")
        recipe_path.write_text(text)
        return subprocess.CompletedProcess(command, 0)

    def assert_no_staged_recipe(self):
        self.assertEqual(list(self.directory.glob(".Staplerfile-*")), [])

    def assert_rejected_unchanged(self, exception=ValueError):
        before = self.recipe.read_bytes()
        with self.assertRaises(exception):
            helper["update"](VERSION)
        self.assertEqual(self.recipe.read_bytes(), before)
        self.assertEqual(self.recipe.stat().st_mode & 0o777, 0o640)
        self.assert_no_staged_recipe()

    def test_snapshot_uses_commit_timestamp_in_utc(self):
        self.assertEqual(helper["snapshot"](), {
            "version": VERSION, "commit": COMMIT, "created": "2026-05-25T19:22:09Z",
        })
        self.assertEqual(self.api_calls, ["/tags?limit=100", "/git/commits/main"])

    def test_tag_order_is_numeric_and_v_prefix_is_optional(self):
        self.tags = [{"name": "v0.9.0"}, {"name": "0.10.0"}, {"name": "v9.0.0-rc1"}]
        self.assertEqual(helper["snapshot"]()["version"], "0.10.0.git20260525192209")

    def test_two_commits_in_one_day_have_distinct_versions(self):
        first = helper["snapshot"]()["version"]
        self.head["commit"]["committer"]["date"] = "2026-05-25T22:22:10+03:00"
        second = helper["snapshot"]()["version"]
        self.assertGreater(helper["version_key"](second), helper["version_key"](first))

    def test_malformed_or_prerelease_only_tags_fail(self):
        for tags in (None, {}, [], [None], [{"name": 3}], [{"name": "v0.3.0-rc1"}]):
            with self.subTest(tags=tags):
                self.tags = tags
                with self.assertRaises(ValueError):
                    helper["snapshot"]()

    def test_bad_commit_or_timestamp_fails(self):
        invalid = [None, {}, {"sha": "short"}, {"sha": "a" * 40}]
        for date in (None, "invalid", "2026-05-25T19:22:09"):
            invalid.append({"sha": COMMIT, "commit": {"committer": {"date": date}}})
        for head in invalid:
            with self.subTest(head=head):
                self.head = head
                with self.assertRaises(ValueError):
                    helper["snapshot"]()

    def test_cli_outputs_exact_shared_contract(self):
        expected = {
            "--latest": VERSION + "\n",
            "--snapshot": json.dumps({"version": VERSION, "commit": COMMIT, "created": "2026-05-25T19:22:09Z"}, separators=(",", ":")) + "\n",
            "--fingerprints": "source_fingerprint\t" + FINGERPRINT + "\n",
        }
        for argument, wanted in expected.items():
            with self.subTest(argument=argument), contextlib.redirect_stdout(io.StringIO()) as output:
                helper["main"]([argument])
                self.assertEqual(output.getvalue(), wanted)
        self.assertEqual(self.commands, [])

    def test_missing_plan_binding_fails_before_api_or_recipe_commands(self):
        os.environ.pop("STPLR_PLUGIN_EXPECTED_FINGERPRINT")
        self.assert_rejected_unchanged()
        self.assertEqual(self.api_calls, [])
        self.assertEqual(self.commands, [])

    def test_commit_drift_fails_before_recipe_commands(self):
        self.head["sha"] = "c" * 40
        self.assert_rejected_unchanged()
        self.assertEqual(self.commands, [])

    def test_version_drift_fails_before_recipe_commands(self):
        self.head["commit"]["committer"]["date"] = "2026-05-25T19:22:10Z"
        self.assert_rejected_unchanged()
        self.assertEqual(self.commands, [])

    def test_update_commits_all_pins_atomically_and_preserves_mode(self):
        os.environ["STPLR_SPEC_COMMAND"] = "/fixture/spec"
        helper["update"](VERSION)
        text = self.recipe.read_text()
        for value in (f"version='{VERSION}'", "release=1", f"upstream_commit='{COMMIT}'", f"source_fingerprint='{FINGERPRINT}'", "sha256:updated", "# unrelated content"):
            self.assertIn(value, text)
        self.assertEqual(self.recipe.stat().st_mode & 0o777, 0o640)
        self.assertEqual(sum(command[1] == "update-checksums" for command in self.commands), 1)
        self.assert_no_staged_recipe()

    def test_same_version_changed_commit_increments_release(self):
        self.recipe.write_text(self.recipe.read_text().replace("20260524192209", "20260525192209"))
        helper["update"](VERSION)
        self.assertIn("release=5", self.recipe.read_text())
        self.assertIn(f"upstream_commit='{COMMIT}'", self.recipe.read_text())

    def test_same_version_and_commit_is_noop(self):
        helper["update"](VERSION)
        self.commands.clear()
        original = self.recipe.read_bytes()
        helper["update"](VERSION)
        self.assertEqual(self.recipe.read_bytes(), original)
        self.assertTrue(all(command[1] == "get-field" for command in self.commands))
        self.assert_no_staged_recipe()

    def test_downgrade_and_invalid_release_are_rejected(self):
        original = self.recipe.read_text()
        self.recipe.write_text(original.replace("20260524192209", "20260526192209"))
        self.assert_rejected_unchanged()
        self.recipe.write_text(original.replace("20260524192209", "20260525192209").replace("release=4", "release=oops"))
        self.assert_rejected_unchanged()
        self.assertTrue(all(command[1] == "get-field" for command in self.commands))

    def test_every_spec_failure_preserves_recipe_and_cleans_stage(self):
        for action in ("get-field", "set-field", "update-checksums"):
            with self.subTest(action=action):
                self.failure = action
                self.assert_rejected_unchanged(subprocess.CalledProcessError)

    def test_concurrent_recipe_edit_is_not_overwritten(self):
        self.concurrent_change = True
        original = self.recipe.read_text()
        with self.assertRaisesRegex(ValueError, "recipe changed"):
            helper["update"](VERSION)
        self.assertEqual(self.recipe.read_text(), original + "# concurrent edit\n")
        self.assert_no_staged_recipe()

    @unittest.skipUnless(REAL_SPEC, "stplr-spec is not available")
    def test_real_spec_keeps_source_pins_acceptable_to_publication_gate(self):
        os.environ["STPLR_SPEC_COMMAND"] = REAL_SPEC
        self.command_patch.stop()

        def run_actual_spec(command, **kwargs):
            if command[1] == "update-checksums":
                # Source downloading is independently gated. Keep this parser
                # regression offline while executing every actual set-field.
                path = Path(command[3])
                path.write_text(path.read_text().replace("sha256:old", "sha256:updated"))
                return subprocess.CompletedProcess(command, 0)
            return REAL_RUN(command, **kwargs)

        with patch.object(helper["subprocess"], "run", side_effect=run_actual_spec):
            helper["update"](VERSION)
        lines = self.recipe.read_text().splitlines()
        for wanted in (f"version='{VERSION}'", "release=1", f"upstream_commit='{COMMIT}'", f"source_fingerprint='{FINGERPRINT}'"):
            self.assertIn(wanted, lines)
        self.assert_no_staged_recipe()


unittest.main(argv=[sys.argv[0]], verbosity=2)
PY
