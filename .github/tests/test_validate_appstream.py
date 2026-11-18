import base64
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

    def test_extraction_requires_successful_digest_listing_and_unpack(self):
        listing = f"{self.metainfo_path}\n{self.desktop_path}\n"
        for failed_step in range(3):
            outputs = ["", listing, ""]
            outputs[failed_step] = CHECK.ValidationError(f"failed stage {failed_step}")
            with self.subTest(failed_step=failed_step), mock.patch.object(CHECK, "run_checked", side_effect=outputs):
                with self.assertRaisesRegex(CHECK.ValidationError, "failed stage"):
                    CHECK.extract_metadata(self.rpm, (self.metainfo_path, self.desktop_path), self.root)

    def test_archive_matching_selects_one_exact_spelling(self):
        for prefix in ("/", "", "./"):
            with self.subTest(prefix=prefix):
                names = [prefix + path[1:] for path in (self.metainfo_path, self.desktop_path)]
                def command(argv, **_kwargs):
                    if argv[0] == "rpm":
                        self.assertEqual(argv[1:3], ["--checksig", "--nosignature"])
                        return "digests OK"
                    if argv[1] == "-tf":
                        return "\n".join(names)
                    self.assertEqual(argv[argv.index("--") + 1:], names)
                    self.assertEqual(Path(argv[2]), self.rpm.resolve())
                    self.extract(self.rpm, (self.metainfo_path, self.desktop_path), self.root)
                    return ""
                with mock.patch.object(CHECK, "run_checked", side_effect=command):
                    CHECK.extract_metadata(self.rpm, (self.metainfo_path, self.desktop_path), self.root)

    def test_archive_matching_rejects_missing_or_ambiguous_members(self):
        for listing in (
            f"{self.metainfo_path}\n",
            f"{self.metainfo_path}\n.{self.metainfo_path}\n{self.desktop_path}\n",
            f"{self.metainfo_path}\n{self.metainfo_path}\n{self.desktop_path}\n",
        ):
            with self.subTest(listing=listing), mock.patch.object(CHECK, "run_checked", side_effect=["", listing]) as command:
                with self.assertRaisesRegex(CHECK.ValidationError, "exactly one"):
                    CHECK.extract_metadata(self.rpm, (self.metainfo_path, self.desktop_path), self.root)
                self.assertEqual(command.call_count, 2)

    def test_successful_extractor_must_really_create_both_regular_files(self):
        listing = f"{self.metainfo_path}\n{self.desktop_path}\n"
        with mock.patch.object(CHECK, "run_checked", side_effect=["", listing, ""]):
            with self.assertRaisesRegex(CHECK.ValidationError, "required regular file"):
                CHECK.extract_metadata(self.rpm, (self.metainfo_path, self.desktop_path), self.root)

    def test_extraction_deadline_terminates_hung_native_command(self):
        commands = self.root / "bin"
        commands.mkdir()
        (commands / "rpm").write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        (commands / "bsdtar").write_text("""#!/usr/bin/env python3
import os
import time
from pathlib import Path
Path(os.environ["TEST_EXTRACTOR_PID"]).write_text(str(os.getpid()))
time.sleep(30)
""", encoding="utf-8")
        for command in commands.iterdir():
            command.chmod(0o755)
        pid_path = self.root / "extractor.pid"
        started = time.monotonic()
        with mock.patch.dict(os.environ, {
            "PATH": f"{commands}:{os.environ['PATH']}",
            "TEST_EXTRACTOR_PID": str(pid_path),
        }), mock.patch.object(CHECK, "EXTRACTION_TIMEOUT", 1):
            with self.assertRaisesRegex(CHECK.ValidationError, "timed out"):
                CHECK.extract_metadata(self.rpm, (self.metainfo_path, self.desktop_path), self.root)
        self.assertLess(time.monotonic() - started, 5)
        with self.assertRaises(ProcessLookupError):
            os.kill(int(pid_path.read_text()), 0)

    def generated_rpm(self):
        fixture = Path(__file__).with_name("fixtures") / "stapler-rpmpack-9f1edfec.rpm.b64"
        return base64.b64decode("".join(fixture.read_text().split()), validate=True)

    def test_native_stapler_rpm_with_legacy_archive_size_extracts(self):
        self.rpm.write_bytes(self.generated_rpm())
        destination = self.root / "native"
        destination.mkdir()
        # The public caller passes a relative artifact path; -C must not
        # change the meaning of that path for the native extractor.
        relative_rpm = Path(os.path.relpath(self.rpm, Path.cwd()))
        CHECK.extract_metadata(relative_rpm, (self.metainfo_path, self.desktop_path), destination)
        self.assertEqual(CHECK.read_metadata(destination / self.metainfo_path[1:]), self.expected)
        self.assertEqual((destination / self.desktop_path[1:]).read_text(), self.desktop)

    def test_native_rpm_digest_rejects_crc_damage_and_truncation_before_extraction(self):
        original = self.generated_rpm()
        crc_damage = bytearray(original)
        crc_damage[-8] ^= 0x40
        for number, data in enumerate((bytes(crc_damage), original[:-8])):
            with self.subTest(variant=number):
                self.rpm.write_bytes(data)
                destination = self.root / f"corrupt-{number}"
                destination.mkdir()
                with mock.patch.object(CHECK, "run_checked", wraps=CHECK.run_checked) as command:
                    with self.assertRaisesRegex(CHECK.ValidationError, "rpm failed"):
                        CHECK.extract_metadata(self.rpm, (self.metainfo_path, self.desktop_path), destination)
                    self.assertEqual(command.call_count, 1)
                    self.assertEqual(command.call_args.args[0][0], "rpm")
                self.assertEqual(list(destination.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
