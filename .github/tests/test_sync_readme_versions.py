import importlib.util
import re
import tempfile
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
    @staticmethod
    def fixture():
        return """# Hand-authored showcase
<!-- catalog:start -->
## Applications
<table><tr>
<td width="50%" valign="top">
<!-- package-card:demo -->
<h3><img src="demo/icon.svg" alt=""> Demo</h3>
<p>Original description. <a href="https://demo.example/">Website</a></p>
<!-- package-meta:demo --><p><sub>Версия <code>1.0.0</code> · <code>amd64</code></sub></p><!-- /package-meta:demo -->
</td>
<td width="50%" valign="top">
<!-- package-card:other -->
<h3>Other</h3>
<!-- package-meta:other -->
  <p><sub>Версия <code>3.0.0</code> · <code>amd64</code> <code>arm64</code></sub></p>
<!-- /package-meta:other -->
</td>
</tr></table>
<!-- catalog:end -->
Hand-authored footer.
"""

    def test_updates_only_owned_blocks_and_is_idempotent(self):
        readme = self.fixture()
        metadata = {
            "demo": ("2.0.0", ["amd64", "arm64"]),
            "other": ("3.1.0", ["amd64"]),
        }
        result = SYNC.sync_catalog(readme, metadata)
        self.assertIn(
            '<!-- package-meta:demo --><p><sub>Версия <code>2.0.0</code> · '
            '<code>amd64</code> <code>arm64</code></sub></p><!-- /package-meta:demo -->',
            result,
        )
        self.assertIn(
            '<!-- package-meta:other -->\n  <p><sub>Версия <code>3.1.0</code> · '
            '<code>amd64</code></sub></p>\n<!-- /package-meta:other -->',
            result,
        )
        self.assertNotIn("<code>1.0.0</code>", result)
        owned_blocks = r"(<!-- package-meta:([a-z0-9-]+) -->).*?(<!-- /package-meta:\2 -->)"
        self.assertEqual(
            re.sub(owned_blocks, r"\1\3", readme, flags=re.DOTALL),
            re.sub(owned_blocks, r"\1\3", result, flags=re.DOTALL),
        )
        self.assertEqual(SYNC.sync_catalog(result, metadata), result)

    def test_rejects_ambiguous_or_cross_card_ownership(self):
        valid = self.fixture()
        metadata = {"demo": ("2", ["amd64"]), "other": ("4", ["arm64"])}
        cases = {
            "missing card": valid.replace("<!-- package-card:demo -->", ""),
            "duplicate card": valid.replace(
                "<!-- package-card:demo -->",
                "<!-- package-card:demo --><!-- package-card:demo -->",
            ),
            "unknown card": valid.replace("package-card:other", "package-card:unknown"),
            "missing metadata": valid.replace("<!-- package-meta:demo -->", ""),
            "duplicate metadata": valid + "<!-- package-meta:demo -->",
            "foreign metadata ID": valid.replace("package-meta:other", "package-meta:unknown"),
            "cross-card metadata": valid.replace("package-meta:demo", "package-meta:swap")
                .replace("package-meta:other", "package-meta:demo")
                .replace("package-meta:swap", "package-meta:other"),
            "metadata before card marker": valid.replace("<!-- package-card:demo -->", "")
                .replace("<!-- /package-meta:demo -->", "<!-- /package-meta:demo --><!-- package-card:demo -->"),
            "unexpected metadata markup": valid.replace(
                "<code>1.0.0</code>", "<strong><code>1.0.0</code></strong>"
            ),
            "missing boundary": valid.replace("<!-- catalog:end -->", ""),
            "duplicate boundary": valid + "<!-- catalog:end -->",
            "outside catalogue": valid.replace("<!-- catalog:start -->", "").replace(
                "<!-- package-card:other -->", "<!-- catalog:start --><!-- package-card:other -->"
            ),
            "metadata after catalogue": valid.replace("<!-- catalog:end -->", "").replace(
                "<!-- package-meta:other -->", "<!-- catalog:end --><!-- package-meta:other -->"
            ),
        }
        for name, candidate in cases.items():
            with self.subTest(name=name):
                with self.assertRaises(RuntimeError):
                    SYNC.sync_catalog(candidate, metadata)

    def test_rejects_invalid_recipe_architectures(self):
        for architectures in ([], ["s390x"], ["amd64", "amd64"], ["all", "arm64"]):
            with self.subTest(architectures=architectures):
                with self.assertRaises(RuntimeError):
                    SYNC.sync_catalog(self.fixture(), {
                        "demo": ("2", architectures), "other": ("4", ["amd64"]),
                    })


class ShowcaseSelectionTests(unittest.TestCase):
    def fixture(self, root, extra="showcase = false"):
        (root / ".github").mkdir()
        for name in ("app", "service"):
            (root / name).mkdir()
            (root / name / "Staplerfile").write_text("name='fixture'\n")
        (root / ".github/support-matrix.toml").write_text(
            '[[packages]]\nid = "app"\n\n[[packages]]\nid = "service"\n' + extra + '\n'
        )

    def test_service_package_is_excluded_only_from_showcase(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            self.assertEqual(SYNC.showcase_packages(root), ["app"])
            self.assertTrue((root / "service/Staplerfile").is_file())

    def test_existing_packages_remain_visible_by_default(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root, "")
            self.assertEqual(SYNC.showcase_packages(root), ["app", "service"])

    def test_invalid_flag_and_missing_matrix_package_are_rejected(self):
        for extra in ('showcase = "false"', 'showcase = 0'):
            with self.subTest(extra=extra), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.fixture(root, extra)
                with self.assertRaisesRegex(RuntimeError, "showcase must be a boolean"):
                    SYNC.showcase_packages(root)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.fixture(root)
            (root / "unlisted").mkdir()
            (root / "unlisted/Staplerfile").touch()
            with self.assertRaisesRegex(RuntimeError, "do not match"):
                SYNC.showcase_packages(root)


if __name__ == "__main__":
    unittest.main()
