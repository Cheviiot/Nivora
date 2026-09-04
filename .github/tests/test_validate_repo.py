import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "tools/validate_repo.py"
SPEC = importlib.util.spec_from_file_location("validate_repo", MODULE_PATH)
assert SPEC and SPEC.loader
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class ParserTests(unittest.TestCase):
    def test_scalar_and_array(self):
        text = "name='demo'\narchitectures=('amd64' 'arm64')\n"
        self.assertEqual(VALIDATOR.scalar(text, "name"), "demo")
        self.assertEqual(
            VALIDATOR.array(text, "architectures"), ["amd64", "arm64"]
        )

    def test_source_arrays_include_architectures(self):
        text = "sources=('one')\n\nsources_arm64=(\n 'two'\n)\n"
        self.assertEqual(
            VALIDATOR.source_arrays(text),
            {"sources": ["one"], "sources_arm64": ["two"]},
        )

    def test_local_source_rejects_traversal(self):
        self.assertEqual(VALIDATOR.local_source_name("local:///LICENSE"), "LICENSE")
        self.assertEqual(VALIDATOR.local_source_name("local:///../secret"), "")
        self.assertIsNone(VALIDATOR.local_source_name("https://example.com/file"))

    def test_markdown_targets(self):
        text = "[Doc](docs/guide.md) <img src='assets/icon.svg'>"
        self.assertEqual(
            VALIDATOR.markdown_targets(text), {"docs/guide.md", "assets/icon.svg"}
        )

    def test_all_architecture_expands_to_two_runtime_cells(self):
        self.assertEqual(
            VALIDATOR.expanded_architectures(["all"]), ["amd64", "arm64"]
        )

    def test_support_groups_expand_by_target(self):
        package = {
            "support": [
                {
                    "targets": ["one", "two"],
                    "tier": "partial",
                    "caveats": ["runtime"],
                }
            ]
        }
        self.assertEqual(
            set(VALIDATOR.support_by_target(package)), {"one", "two"}
        )


class LinkTests(unittest.TestCase):
    def test_missing_link_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "README.md"
            path.write_text("[missing](no.md)\n", encoding="utf-8")
            old_root = VALIDATOR.ROOT
            VALIDATOR.ROOT = Path(directory)
            try:
                errors = []
                VALIDATOR.validate_links(path, errors)
                self.assertEqual(len(errors), 1)
            finally:
                VALIDATOR.ROOT = old_root


class WorkflowTests(unittest.TestCase):
    def test_github_desktop_dispatch_and_fallback_match_recipe(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workflow_dir = root / ".github/workflows"
            workflow_dir.mkdir(parents=True)
            workflow = workflow_dir / "github-desktop-linux.yml"
            workflow.write_text(
                """on:
  workflow_dispatch:
    inputs:
      version:
        default: \"3.6.5\"
value: ${{ inputs.version || '3.6.5' }}
""",
                encoding="utf-8",
            )
            old_root = VALIDATOR.ROOT
            VALIDATOR.ROOT = root
            try:
                errors = []
                VALIDATOR.validate_github_desktop_workflow(
                    {"github-desktop": {"version": "3.6.5"}}, errors
                )
                self.assertEqual(errors, [])

                workflow.write_text(
                    workflow.read_text(encoding="utf-8").replace("3.6.5", "3.6.3"),
                    encoding="utf-8",
                )
                errors = []
                VALIDATOR.validate_github_desktop_workflow(
                    {"github-desktop": {"version": "3.6.5"}}, errors
                )
                self.assertEqual(len(errors), 2)
            finally:
                VALIDATOR.ROOT = old_root


class AppStreamTests(unittest.TestCase):
    def test_sidecar_id_and_launchable_are_required(self):
        with tempfile.TemporaryDirectory() as directory:
            package_dir = Path(directory)
            sidecar = package_dir / "com.example.App.metainfo.xml"
            sidecar.write_text(
                """<component type="desktop-application">
  <id>com.example.App</id>
  <launchable type="desktop-id">com.example.App.desktop</launchable>
</component>
""",
                encoding="utf-8",
            )
            errors = []
            VALIDATOR.validate_appstream_sidecar(
                "demo",
                package_dir,
                "com.example.App",
                "/usr/share/applications/com.example.App.desktop",
                errors,
            )
            self.assertEqual(errors, [])

            sidecar.write_text(
                "<component><id>wrong</id></component>", encoding="utf-8"
            )
            errors = []
            VALIDATOR.validate_appstream_sidecar(
                "demo",
                package_dir,
                "com.example.App",
                "/usr/share/applications/com.example.App.desktop",
                errors,
            )
            self.assertGreaterEqual(len(errors), 2)

    def test_cross_package_local_url_collision_is_rejected(self):
        errors = []
        VALIDATOR.validate_unique_local_source_urls(
            {
                "one": {"local_sources": ["local:///LICENSE"]},
                "two": {"local_sources": ["local:///LICENSE"]},
            },
            errors,
        )
        self.assertEqual(len(errors), 1)


if __name__ == "__main__":
    unittest.main()
