import copy
import importlib.util
import sys
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS))
SPEC = importlib.util.spec_from_file_location("check_gnome_catalog", TOOLS / "check_gnome_catalog.py")
CATALOG = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CATALOG)


class CatalogContractTests(unittest.TestCase):
    XML = """<component type="desktop-application">
      <id>org.example.App</id><launchable type="desktop-id">example.desktop</launchable>
      <name>Example</name><summary>Example app</summary><summary xml:lang="ru">Приложение</summary>
      <description><p>Long description</p><p xml:lang="ru">Описание</p></description>
      <developer id="org.example"><name>Example Team</name></developer>
      <url type="homepage">https://example.org/</url><project_license>MIT</project_license>
      <screenshots><screenshot><image>https://example.org/ui.png</image></screenshot></screenshots>
    </component>"""
    DATA = {
        "id": "org.example.App", "launchable": {"desktop-id": "example.desktop"},
        "name": {"C": "Example"}, "summary": {"C": "Example app", "ru": "Приложение"},
        "description": {"C": "<p>Long description</p>", "ru": "<p>Описание</p>"},
        "developer": {"id": "org.example", "name": {"C": "Example Team"}},
        "urls": {"homepage": "https://example.org/"}, "project_license": "MIT",
        "screenshots": [{"images": [{"url": "https://example.org/ui.png"}]}],
    }

    def test_modern_and_legacy_developer_contracts(self):
        document = ET.fromstring(self.XML)
        CATALOG.validate_details("example", document, self.DATA)
        legacy = copy.deepcopy(self.DATA)
        legacy["developer_name"] = legacy.pop("developer")["name"]
        CATALOG.validate_details("example", document, legacy)

    def test_loss_of_visible_metadata_is_rejected(self):
        for field in ("id", "launchable", "name", "summary", "description", "developer", "urls", "project_license", "screenshots"):
            with self.subTest(field=field), self.assertRaises(ValueError):
                data = copy.deepcopy(self.DATA)
                data.pop(field)
                CATALOG.validate_details("example", ET.fromstring(self.XML), data)

    def test_lost_russian_summary_is_rejected(self):
        data = copy.deepcopy(self.DATA)
        data["summary"].pop("ru")
        with self.assertRaises(ValueError):
            CATALOG.validate_details("example", ET.fromstring(self.XML), data)

    def test_search_format_handles_multiline_descriptions(self):
        row = ["nivora", "example", "1.0-2", "org.example.App", "Example", "Summary", "<p>A</p>\n<p>B</p>"]
        self.assertEqual(CATALOG.search_rows("\x1f".join(row) + "\x1e\n"), [row])
        with self.assertRaises(ValueError):
            CATALOG.search_rows("nivora\texample\t1.0\n")


if __name__ == "__main__":
    unittest.main()
