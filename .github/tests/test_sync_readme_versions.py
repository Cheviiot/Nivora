import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = (
    Path(__file__).resolve().parents[1] / "tools/sync_readme_versions.py"
)
SPEC = importlib.util.spec_from_file_location("sync_readme_versions", MODULE_PATH)
assert SPEC and SPEC.loader
SYNC = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SYNC)


class SyncCatalogTests(unittest.TestCase):
    def test_updates_html_card_version_and_architectures(self):
        readme = """<!-- package-card:demo -->
<strong>Demo</strong><br>
<code>1.0.0</code> · <code>amd64</code><br>
<code>stplr install nivora/demo</code>
"""
        result = SYNC.sync_catalog(
            readme,
            {"demo": ("2.0.0", ["amd64", "arm64"])},
        )
        self.assertIn(
            "<code>2.0.0</code> · <code>amd64</code> <code>arm64</code><br>",
            result,
        )
        self.assertNotIn("<code>1.0.0</code>", result)

    def test_rejects_missing_duplicate_and_cross_card_commands(self):
        valid = """<!-- package-card:demo -->
<code>1</code> · <code>amd64</code><br>
<code>stplr install nivora/demo</code>
"""
        cases = (
            valid.replace("<!-- package-card:demo -->", ""),
            valid.replace(
                "<!-- package-card:demo -->",
                "<!-- package-card:demo --><!-- package-card:demo -->",
            ),
            """<!-- package-card:demo -->
<code>1</code> · <code>amd64</code><br>
<!-- package-card:other -->
<code>stplr install nivora/demo</code>
""",
        )
        for candidate in cases:
            with self.subTest(candidate=candidate):
                with self.assertRaises(RuntimeError):
                    SYNC.sync_catalog(candidate, {"demo": ("2", ["amd64"])})


if __name__ == "__main__":
    unittest.main()
