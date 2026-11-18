import importlib.util
import os
import subprocess
import sys
import tempfile
import time
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest import mock


MODULE_PATH = Path(__file__).resolve().parents[1] / "tools/validate_appstream.py"
SPEC = importlib.util.spec_from_file_location("validate_appstream", MODULE_PATH)
assert SPEC and SPEC.loader
CHECK = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = CHECK
SPEC.loader.exec_module(CHECK)


def metadata_xml(component_id="com.example.Demo", desktop="demo.desktop"):
    return f"""<component type="desktop-application">
  <id>{component_id}</id>
  <metadata_license>MIT</metadata_license>
  <project_license>MIT</project_license>
  <name>Demo</name>
  <summary>Run useful desktop tasks</summary>
  <description><p>A desktop application for useful tasks.</p></description>
  <developer id="com.example"><name>Example</name></developer>
  <url type="homepage">https://example.com/</url>
  <launchable type="desktop-id">{desktop}</launchable>
</component>"""


def cpio_member(name, data=b"", mode=0o100644):
    filename = name.encode("utf-8") + b"\0"
    fields = (1, mode, 0, 0, 1, 0, len(data), 0, 0, 0, 0, len(filename), 0)
    header = b"070701" + b"".join(f"{value:08x}".encode("ascii") for value in fields)
    prefix = header + filename
    return prefix + b"\0" * (-len(prefix) % 4) + data + b"\0" * (-len(data) % 4)


PADDING_PRODUCER = """#!/usr/bin/env python3
import fcntl
import os
import sys
import time
from pathlib import Path

Path(os.environ["TEST_PRODUCER_PID"]).write_text(str(os.getpid()))
with open(os.environ["TEST_CPIO_ARCHIVE"], "rb") as archive:
    sys.stdout.buffer.write(archive.read())
# Ensure the unread padding exceeds this actual pipe's capacity. A consumer
# which stops at TRAILER!!! cannot accept it all before exiting.
remaining = max(2 * fcntl.fcntl(1, fcntl.F_GETPIPE_SZ), 2 * 1024 * 1024)
while remaining:
    block = bytes(min(64 * 1024, remaining))
    sys.stdout.buffer.write(block)
    remaining -= len(block)
sys.stdout.buffer.flush()
if os.environ.get("TEST_PRODUCER_HOLD") == "1":
    time.sleep(30)
raise SystemExit(int(os.environ.get("TEST_PRODUCER_STATUS", "0")))
"""


EARLY_CPIO_CONSUMER = """#!/usr/bin/env python3
import sys
from pathlib import Path

def read_exact(size):
    value = sys.stdin.buffer.read(size)
    if len(value) != size:
        raise SystemExit("truncated newc fixture")
    return value

while True:
    header = read_exact(110)
    if header[:6] != b"070701":
        raise SystemExit("invalid newc fixture")
    fields = [int(header[offset:offset + 8], 16) for offset in range(6, 110, 8)]
    size, name_size = fields[6], fields[11]
    name = read_exact(name_size)[:-1].decode()
    read_exact(-(110 + name_size) % 4)
    if name == "TRAILER!!!":
        break
    contents = read_exact(size)
    read_exact(-size % 4)
    path = Path(name)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(contents)
# Deliberately do not read the trailing padding, just like GNU cpio.
"""


class AppStreamTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.sidecar = self.root / "com.example.Demo.metainfo.xml"
        self.sidecar.write_text(metadata_xml(), encoding="utf-8")
        self.recipe = """appstream_app_id='com.example.Demo'
appstream_name='Demo'
appstream_developer='Example'
homepage='https://example.com/'
"""
        self.expected = CHECK.read_metadata(self.sidecar)
        self.rpm = self.root / "demo.rpm"
        self.rpm.touch()
        self.metainfo_path = "/usr/share/metainfo/com.example.Demo.metainfo.xml"
        self.desktop_path = "/usr/share/applications/demo.desktop"
        self.icon_path = "/usr/share/icons/hicolor/128x128/apps/demo.png"
        self.manifest = {
            path: CHECK.PayloadEntry(0o100644, "")
            for path in (self.metainfo_path, self.desktop_path, self.icon_path)
        }
        self.payload_xml = metadata_xml()
        self.desktop = "[Desktop Entry]\nType=Application\nName=Demo\nExec=demo\nIcon=demo\n"

    def extract(self, _rpm, paths, destination):
        for path, contents in zip(paths, (self.payload_xml, self.desktop), strict=True):
            target = destination / path[1:]
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(contents, encoding="utf-8")

    def validate_payload(self):
        with (
            mock.patch.object(CHECK, "read_manifest", return_value=self.manifest),
            mock.patch.object(CHECK, "extract_metadata", side_effect=self.extract),
            mock.patch.object(CHECK, "run_checked", return_value=""),
        ):
            CHECK.validate_rpm("demo", self.expected, self.rpm)

    def test_native_legacy_override_is_limited_to_existing_package_id_pairs(self):
        for package, app_id in CHECK.LEGACY_IDS.items():
            with self.subTest(package=package), mock.patch.object(CHECK, "run_checked") as command:
                data = CHECK.Metadata(app_id, "demo.desktop", "Demo", None, None, None)
                CHECK.validate_native(package, data, self.sidecar)
                self.assertEqual(command.call_args.args[0], [
                    "appstreamcli", "validate", "--no-net", "--override",
                    "cid-desktopapp-is-not-rdns=info", str(self.sidecar),
                ])
        for package, app_id in (("new-app", "anidesk"), ("anidesk", "new-id"), ("demo", "com.example.Demo")):
            with self.subTest(package=package, app_id=app_id), mock.patch.object(CHECK, "run_checked") as command:
                data = CHECK.Metadata(app_id, "demo.desktop", "Demo", None, None, None)
                CHECK.validate_native(package, data, self.sidecar)
                self.assertEqual(command.call_args.args[0], ["appstreamcli", "validate", "--no-net", str(self.sidecar)])

    def test_native_failure_and_missing_tool_are_not_ignored(self):
        failures = (
            subprocess.CompletedProcess([], 3, stdout="metadata-license-invalid", stderr=""),
            FileNotFoundError("appstreamcli"),
        )
        for failure in failures:
            with self.subTest(failure=failure):
                kwargs = {"side_effect": failure} if isinstance(failure, Exception) else {"return_value": failure}
                with mock.patch.object(CHECK.subprocess, "run", **kwargs):
                    with self.assertRaises(CHECK.ValidationError):
                        CHECK.validate_native("demo", self.expected, self.sidecar)

    def test_missing_sidecar_fails_before_native_validator(self):
        self.sidecar.unlink()
        with mock.patch.object(CHECK, "run_checked") as command:
            with self.assertRaisesRegex(CHECK.ValidationError, "regular file"):
                CHECK.validate_sidecar("demo", self.root, self.recipe)
            command.assert_not_called()

    def test_sidecar_recipe_identity_mismatches_fail(self):
        for old, new in (
            ("com.example.Demo", "com.other.Demo"),
            ("<name>Demo</name>", "<name>Other</name>"),
            ("https://example.com/", "https://wrong.example/"),
            ("<name>Example</name>", "<name>Other developer</name>"),
        ):
            with self.subTest(new=new), mock.patch.object(CHECK, "run_checked"):
                self.sidecar.write_text(metadata_xml().replace(old, new), encoding="utf-8")
                with self.assertRaises(CHECK.ValidationError):
                    CHECK.validate_sidecar("demo", self.root, self.recipe)

    def test_legacy_and_modern_developer_names_are_read_semantically(self):
        self.sidecar.write_text(metadata_xml().replace(
            '<developer id="com.example"><name>Example</name></developer>',
            '<developer_name>Example</developer_name>',
        ), encoding="utf-8")
        self.assertEqual(CHECK.read_metadata(self.sidecar).developer, self.expected.developer)

    def test_payload_accepts_different_component_and_desktop_ids(self):
        for app_id, desktop in (
            ("com.openai.chatgpt", "chatgpt.desktop"),
            ("com.google.Antigravity", "antigravity.desktop"),
            ("org.telegram.desktop", "org.telegram.desktop.desktop"),
        ):
            with self.subTest(app_id=app_id):
                self.sidecar.write_text(metadata_xml(app_id, desktop), encoding="utf-8")
                self.expected = CHECK.read_metadata(self.sidecar)
                self.payload_xml = metadata_xml(app_id, desktop)
                self.manifest = {
                    path: CHECK.PayloadEntry(0o100644, "")
                    for path in (
                        f"/usr/share/metainfo/{app_id}.metainfo.xml",
                        f"/usr/share/applications/{desktop}", self.icon_path,
                    )
                }
                self.validate_payload()

    def test_missing_metainfo_or_declared_desktop_is_rejected(self):
        for path in (self.metainfo_path, self.desktop_path):
            with self.subTest(path=path):
                original = self.manifest.pop(path)
                self.manifest["/usr/share/applications/unrelated.desktop"] = CHECK.PayloadEntry(0o100644, "")
                with self.assertRaisesRegex(CHECK.ValidationError, "required regular file"):
                    self.validate_payload()
                self.manifest[path] = original

    def test_payload_identity_drift_is_rejected(self):
        changes = (
            ("com.example.Demo", "com.other.Demo"),
            ("demo.desktop", "wrong.desktop"),
            ("<name>Demo</name>", "<name>Other</name>"),
            ("https://example.com/", "https://wrong.example/"),
            ("<name>Example</name>", "<name>Other developer</name>"),
            ('id="com.example"', 'id="org.other"'),
        )
        for old, new in changes:
            with self.subTest(new=new):
                self.payload_xml = metadata_xml().replace(old, new)
                with self.assertRaisesRegex(CHECK.ValidationError, "differs from catalog"):
                    self.validate_payload()

    def test_richer_upstream_description_does_not_require_byte_equality(self):
        root = ET.fromstring(self.payload_xml)
        root.find("description/p").text = "A different but valid upstream description."
        ET.SubElement(root, "url", {"type": "help"}).text = "https://example.com/help"
        self.payload_xml = ET.tostring(root, encoding="unicode")
        self.validate_payload()

    def test_proprietary_application_cannot_be_relabelled_as_free_in_payload(self):
        self.sidecar.write_text(metadata_xml().replace(
            "<project_license>MIT</project_license>",
            "<project_license>LicenseRef-proprietary</project_license>",
        ), encoding="utf-8")
        self.expected = CHECK.read_metadata(self.sidecar)
        with self.assertRaisesRegex(CHECK.ValidationError, "project_license.*differs from catalog"):
            self.validate_payload()

    def test_missing_icon_or_nonregular_icon_is_rejected(self):
        for entry in (None, CHECK.PayloadEntry(0o040755, "")):
            with self.subTest(entry=entry):
                self.manifest.pop(self.icon_path, None)
                if entry is not None:
                    self.manifest[self.icon_path] = entry
                with self.assertRaisesRegex(CHECK.ValidationError, "Icon.*no file"):
                    self.validate_payload()

    def test_icon_name_is_literal_and_cannot_match_another_icon_with_glob(self):
        self.desktop = self.desktop.replace("Icon=demo", "Icon=dem*")
        with self.assertRaisesRegex(CHECK.ValidationError, "Icon.*no file"):
            self.validate_payload()

    def test_absolute_icon_and_symlink_to_packaged_icon_are_valid(self):
        target = "/opt/demo/icon.png"
        self.manifest[target] = CHECK.PayloadEntry(0o100644, "")
        self.manifest[self.icon_path] = CHECK.PayloadEntry(0o120777, target)
        self.validate_payload()
        self.desktop = self.desktop.replace("Icon=demo", f"Icon={target}")
        self.validate_payload()

    def test_absolute_icon_path_is_normalized_for_lookup(self):
        self.desktop = self.desktop.replace("Icon=demo", "Icon=/usr/share/pixmaps/../pixmaps/demo.png")
        self.manifest["/usr/share/pixmaps/demo.png"] = CHECK.PayloadEntry(0o100644, "")
        self.validate_payload()

    def test_explicit_metainfo_stock_icon_must_exist_even_when_desktop_icon_is_valid(self):
        self.payload_xml = metadata_xml().replace("</component>", '<icon type="stock">missing</icon></component>')
        with self.assertRaisesRegex(CHECK.ValidationError, "stock icon.*no file"):
            self.validate_payload()
        self.payload_xml = self.payload_xml.replace(
            '<icon type="stock">missing</icon>', '<icon type="stock">demo</icon>',
        )
        self.validate_payload()

    def test_explicit_catalog_stock_icon_cannot_silently_change_or_disappear(self):
        canonical = metadata_xml().replace("</component>", '<icon type="stock">demo</icon></component>')
        self.sidecar.write_text(canonical, encoding="utf-8")
        self.expected = CHECK.read_metadata(self.sidecar)
        for payload in (metadata_xml(), canonical.replace(
            '<icon type="stock">demo</icon>', '<icon type="stock">another</icon>',
        )):
            with self.subTest(payload=payload):
                self.payload_xml = payload
                self.manifest["/usr/share/pixmaps/another.png"] = CHECK.PayloadEntry(0o100644, "")
                with self.assertRaisesRegex(CHECK.ValidationError, "stock icons differ"):
                    self.validate_payload()

    def test_broken_or_cyclic_icon_symlink_is_rejected(self):
        target = "/opt/demo/icon.png"
        self.manifest[self.icon_path] = CHECK.PayloadEntry(0o120777, target)
        with self.assertRaisesRegex(CHECK.ValidationError, "Icon.*no file"):
            self.validate_payload()
        self.manifest[target] = CHECK.PayloadEntry(0o120777, self.icon_path)
        with self.assertRaisesRegex(CHECK.ValidationError, "Icon.*no file"):
            self.validate_payload()

    def test_native_desktop_failure_is_propagated(self):
        path = self.root / "demo.desktop"
        path.write_text(self.desktop, encoding="utf-8")
        with mock.patch.object(CHECK, "run_checked", side_effect=CHECK.ValidationError("invalid desktop")):
            with self.assertRaisesRegex(CHECK.ValidationError, "invalid desktop"):
                CHECK.validate_desktop(path, self.manifest)

    def test_manifest_rejects_failed_query_even_after_plausible_output(self):
        result = subprocess.CompletedProcess([], 42, stdout="100644\t\t/usr/share/icon.png\n", stderr="RPM failed")
        with mock.patch.object(CHECK.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(CHECK.ValidationError, "failed.*42"):
                CHECK.read_manifest(self.rpm)

    def test_manifest_rejects_malformed_or_duplicate_metadata(self):
        for output in (
            "", "invalid\n", "999\t\t/usr/share/icon.png\n",
            "100644\t\trelative/path\n", "100644\t\t/usr/../etc/file\n",
            "100644\t\t/usr/share/icon.png\n100644\t\t/usr/share/icon.png\n",
        ):
            with self.subTest(output=output), mock.patch.object(CHECK, "run_checked", return_value=output):
                with self.assertRaises(CHECK.ValidationError):
                    CHECK.read_manifest(self.rpm)

    def test_extraction_checks_both_pipeline_processes_and_output_files(self):
        commands = self.root / "bin"
        commands.mkdir()
        (commands / "rpm2cpio").write_text('#!/bin/sh\nprintf archive\nexit "${TEST_PRODUCER_STATUS:-0}"\n', encoding="utf-8")
        (commands / "cpio").write_text('#!/bin/sh\ncat >/dev/null\nexit "${TEST_CONSUMER_STATUS:-0}"\n', encoding="utf-8")
        for command in commands.iterdir():
            command.chmod(0o755)
        for producer, consumer in ((42, 0), (0, 42), (0, 0)):
            with self.subTest(producer=producer, consumer=consumer), mock.patch.dict(os.environ, {
                "PATH": f"{commands}:{os.environ['PATH']}",
                "TEST_PRODUCER_STATUS": str(producer), "TEST_CONSUMER_STATUS": str(consumer),
            }):
                with self.assertRaises(CHECK.ValidationError):
                    CHECK.extract_metadata(self.rpm, (self.metainfo_path, self.desktop_path), self.root)

    def padding_pipeline(self):
        archive = self.root / "metadata.cpio"
        contents = (
            cpio_member(f".{self.metainfo_path}", self.payload_xml.encode())
            + cpio_member(f".{self.desktop_path}", self.desktop.encode())
            + cpio_member("TRAILER!!!", mode=0)
        )
        archive.write_bytes(contents + bytes(-len(contents) % 512))
        commands = self.root / "bin"
        commands.mkdir()
        for name, script in (("rpm2cpio", PADDING_PRODUCER), ("cpio", EARLY_CPIO_CONSUMER)):
            command = commands / name
            command.write_text(script, encoding="utf-8")
            command.chmod(0o755)
        destination = self.root / "extracted"
        destination.mkdir()
        return destination, {
            "PATH": f"{commands}:{os.environ['PATH']}",
            "TEST_CPIO_ARCHIVE": str(archive),
            "TEST_PRODUCER_PID": str(self.root / "producer.pid"),
            "TEST_PRODUCER_STATUS": "0",
            "TEST_PRODUCER_HOLD": "0",
        }

    def test_extraction_drains_padding_after_consumer_exits_at_valid_trailer(self):
        destination, environment = self.padding_pipeline()
        with mock.patch.dict(os.environ, environment):
            CHECK.extract_metadata(self.rpm, (self.metainfo_path, self.desktop_path), destination)
        self.assertEqual((destination / self.metainfo_path[1:]).read_text(), self.payload_xml)
        self.assertEqual((destination / self.desktop_path[1:]).read_text(), self.desktop)

    def test_genuine_producer_failure_after_valid_archive_and_padding_is_rejected(self):
        destination, environment = self.padding_pipeline()
        environment["TEST_PRODUCER_STATUS"] = "42"
        with mock.patch.dict(os.environ, environment):
            with self.assertRaisesRegex(CHECK.ValidationError, "rpm2cpio=42, cpio=0"):
                CHECK.extract_metadata(self.rpm, (self.metainfo_path, self.desktop_path), destination)

    def test_padding_drain_deadline_terminates_a_producer_that_keeps_pipe_open(self):
        destination, environment = self.padding_pipeline()
        environment["TEST_PRODUCER_HOLD"] = "1"
        started = time.monotonic()
        with mock.patch.dict(os.environ, environment), mock.patch.object(CHECK, "EXTRACTION_TIMEOUT", 1):
            with self.assertRaisesRegex(CHECK.ValidationError, "timed out"):
                CHECK.extract_metadata(self.rpm, (self.metainfo_path, self.desktop_path), destination)
        self.assertLess(time.monotonic() - started, 5)
        producer_pid = int(Path(environment["TEST_PRODUCER_PID"]).read_text())
        with self.assertRaises(ProcessLookupError):
            os.kill(producer_pid, 0)


if __name__ == "__main__":
    unittest.main()
