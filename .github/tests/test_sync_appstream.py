import importlib.util
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "tools/sync_appstream.py"
SPEC = importlib.util.spec_from_file_location("sync_appstream", MODULE_PATH)
assert SPEC and SPEC.loader
SYNC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SYNC)


class DesktopIdentityTests(unittest.TestCase):
    def document(self, app_id, desktop_id=None):
        recipe = f"name='example'\nappstream_app_id='{app_id}'\n"
        if desktop_id is not None:
            recipe += f"appstream_desktop_id='{desktop_id}'\n"
        return ET.fromstring(SYNC.render("example", recipe))

    def test_default_launchable_keeps_existing_component_ids(self):
        for app_id in ("com.example.App", "org.telegram.desktop", "anidesk"):
            with self.subTest(app_id=app_id):
                doc = self.document(app_id)
                self.assertEqual(doc.findtext("id"), app_id)
                self.assertEqual(doc.findtext("launchable"), f"{app_id}.desktop")

    def test_upstream_desktop_identity_preserves_component_id(self):
        doc = self.document("com.google.Antigravity", "antigravity.desktop")
        self.assertEqual(doc.findtext("id"), "com.google.Antigravity")
        self.assertEqual(doc.findtext("launchable"), "antigravity.desktop")
        self.assertEqual(doc.find("launchable").get("type"), "desktop-id")

    def test_launchable_must_be_a_desktop_basename(self):
        for invalid in ("../other.desktop", "/tmp/other.desktop", "app", "a b.desktop"):
            with self.subTest(launchable=invalid):
                with self.assertRaises(ValueError):
                    self.document("com.example.App", invalid)


class MetadataSemanticsTests(unittest.TestCase):
    RECIPE = "name='example'\nappstream_app_id='com.example.App'\n"

    def test_unassessed_age_rating_stays_unknown(self):
        doc = ET.fromstring(SYNC.render("example", self.RECIPE))
        self.assertIsNone(doc.find("content_rating"))

    def test_official_screenshot_preserves_localized_captions(self):
        recipe = self.RECIPE + (
            "appstream_screenshot='https://example.com/ui.png'\n"
            "appstream_screenshot_caption='Chats & groups'\n"
            "appstream_screenshot_caption_ru='Чаты и группы'\n"
        )
        doc = ET.fromstring(SYNC.render("example", recipe))
        shot = doc.find("screenshots/screenshot")
        self.assertEqual(shot.get("type"), "default")
        self.assertEqual(shot.findtext("caption"), "Chats & groups")
        self.assertEqual(shot.findall("caption")[1].text, "Чаты и группы")
        self.assertEqual(shot.findtext("image"), "https://example.com/ui.png")
        self.assertIsNone(doc.find("releases"))

    def test_screenshot_requires_https_and_caption(self):
        for url in ("file:///tmp/image.png", "http://example.com/image.png", "https://u:p@example.com/image.png"):
            with self.subTest(url=url), self.assertRaises(ValueError):
                SYNC.render("example", self.RECIPE + f"appstream_screenshot='{url}'\n")
        with self.assertRaises(ValueError):
            SYNC.render("example", self.RECIPE + "appstream_screenshot='https://example.com/ui.png'\n")


if __name__ == "__main__":
    unittest.main()
