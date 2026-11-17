import importlib.util
import tempfile
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "tools/validate_repo.py"
SPEC = importlib.util.spec_from_file_location("validate_repo", MODULE_PATH)
assert SPEC and SPEC.loader
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class RepositoryTextTests(unittest.TestCase):
    def test_private_scratch_is_excluded_but_product_sources_are_scanned(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for cache in (".cache", "external", ".venv"):
                path = root / cache / "diagnostic.txt"
                path.parent.mkdir()
                path.write_text("chmod " + "777", encoding="utf-8")
            product = root / "product.txt"
            product.write_text("chmod " + "777", encoding="utf-8")
            old_root = VALIDATOR.ROOT
            VALIDATOR.ROOT = root
            try:
                errors = []
                VALIDATOR.validate_repository_text(errors)
                self.assertEqual(errors, ["product.txt: chmod " + "777 is forbidden"])
            finally:
                VALIDATOR.ROOT = old_root


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

    def test_only_alt_p11_target_is_approved(self):
        self.assertEqual(VALIDATOR.EXPECTED_TARGETS, {"alt-p11"})
        self.assertNotIn("experimental", VALIDATOR.SUPPORTED_TIERS)


class SupportMatrixTests(unittest.TestCase):
    MATRIX = """schema_version = 2

[stapler]
stable_version = "0.1.1"
stable_commit = "{sha}"
main_commit = "{sha}"

[images]
alt_p11 = "registry.altlinux.org/p11/base@sha256:{digest}"

[expectations]
package_count = 1
target_count = 1
logical_runtime_cells = {logical}
declared_supported_runtime_cells = {supported}
verified_runtime_cells = {verified}
blocking_ci_build_cells_full_common_change = 1
advisory_main_build_cells_full_common_change = 1

[ci_coverage]
blocking_builders = ["alt-p11-x86_64"]
main_canary = "advisory-alt-p11-x86_64"

[[targets]]
id = "alt-p11"
distro = "altlinux"
release = "p11"
branch_id = "p11"
ci_mode = "blocking-lifecycle"
gated_architectures = ["amd64"]

[[packages]]
id = "demo"
architectures = ["amd64", "arm64"]
support = [
{support}
]
"""

    def render(self, support, logical=2, supported=2, verified=1):
        return self.MATRIX.format(
            sha="0" * 40,
            digest="a" * 64,
            support=support,
            logical=logical,
            supported=supported,
            verified=verified,
        )

    def run_validator(self, body):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / ".github/workflows").mkdir(parents=True)
            (root / ".github/support-matrix.toml").write_text(body, encoding="utf-8")
            (root / ".github/workflows/package-ci.yml").write_text(
                "\n".join(
                    (
                        ".github/tools/clean_build.sh",
                        ".github/tools/verify_artifacts.sh",
                        ".github/tools/test_package_lifecycle.sh",
                    )
                ),
                encoding="utf-8",
            )
            old_root = VALIDATOR.ROOT
            old_packages = VALIDATOR.EXPECTED_PACKAGES
            VALIDATOR.ROOT = root
            VALIDATOR.EXPECTED_PACKAGES = ("demo",)
            try:
                errors = []
                VALIDATOR.load_support_matrix(errors)
                return errors
            finally:
                VALIDATOR.ROOT = old_root
                VALIDATOR.EXPECTED_PACKAGES = old_packages

    def test_gated_amd64_and_ungated_arm64_are_accepted(self):
        support = (
            '  { targets = ["alt-p11"], architectures = ["amd64"], '
            'tier = "verified", caveats = [] },\n'
            '  { targets = ["alt-p11"], architectures = ["arm64"], '
            'tier = "partial", caveats = ["arm64-not-gated"] },'
        )
        self.assertEqual(self.run_validator(self.render(support)), [])

    def test_verified_is_rejected_for_an_ungated_architecture(self):
        support = (
            '  { targets = ["alt-p11"], architectures = ["amd64", "arm64"], '
            'tier = "verified", caveats = [] },'
        )
        errors = self.run_validator(self.render(support, verified=2))
        self.assertTrue(
            any("is not gated" in error for error in errors), errors
        )

    def test_missing_cell_is_reported(self):
        support = (
            '  { targets = ["alt-p11"], architectures = ["amd64"], '
            'tier = "verified", caveats = [] },'
        )
        errors = self.run_validator(self.render(support, logical=1, supported=1))
        self.assertTrue(
            any("must occur exactly once" in error for error in errors), errors
        )

    def test_non_p11_build_targets_are_rejected(self):
        support = (
            '  { targets = ["alt-p11"], architectures = ["amd64"], '
            'tier = "verified", caveats = [] },\n'
            '  { targets = ["alt-p11"], architectures = ["arm64"], '
            'tier = "partial", caveats = ["arm64-not-gated"] },'
        )
        body = self.render(support)
        cases = {
            "renamed target": (
                body.replace('"alt-p11"', '"alt-sisyphus"'),
                "only approved target is alt-p11",
            ),
            "target keeps old release": (
                body.replace('release = "p11"', 'release = "sisyphus"'),
                "release and branch_id must be p11",
            ),
            "target keeps old branch": (
                body.replace('branch_id = "p11"', 'branch_id = "sisyphus"'),
                "release and branch_id must be p11",
            ),
            "blocking builder": (
                body.replace('"alt-p11-x86_64"', '"alt-sisyphus-x86_64"'),
                "only blocking builder must be alt-p11-x86_64",
            ),
            "advisory builder": (
                body.replace(
                    '"advisory-alt-p11-x86_64"', '"advisory-alt-sisyphus-x86_64"'
                ),
                "canary must also target ALT p11",
            ),
            "image mislabeled as p11": (
                body.replace(
                    "registry.altlinux.org/p11/base",
                    "registry.altlinux.org/sisyphus/base",
                ),
                "must be the official ALT p11 base",
            ),
            "extra image": (
                body.replace(
                    "[images]\n",
                    '[images]\nalt_sisyphus = "registry.altlinux.org/sisyphus/base@sha256:'
                    + "b" * 64 + '"\n',
                ),
                "images must contain only alt_p11",
            ),
        }
        for name, (candidate, expected) in cases.items():
            with self.subTest(name=name):
                errors = self.run_validator(candidate)
                self.assertTrue(any(expected in error for error in errors), errors)


class UpdaterListTests(unittest.TestCase):
    def write_updater(self, root, packages):
        tools = root / ".github/tools"
        tools.mkdir(parents=True)
        body = ["readonly -a PACKAGES=("]
        body += [f"    {name}" for name in packages]
        body.append(")")
        body.append("latest_version() {")
        body.append("    case \"$1\" in")
        body += [f"    {name}) true ;;" for name in packages]
        body.append("    esac")
        body.append("}")
        (tools / "package_updates.sh").write_text(
            "\n".join(body) + "\n", encoding="utf-8"
        )

    def run_validator(self, packages, expected):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.write_updater(root, packages)
            old_root = VALIDATOR.ROOT
            old_packages = VALIDATOR.EXPECTED_PACKAGES
            VALIDATOR.ROOT = root
            VALIDATOR.EXPECTED_PACKAGES = expected
            try:
                errors = []
                VALIDATOR.validate_updater_package_list(errors)
                return errors
            finally:
                VALIDATOR.ROOT = old_root
                VALIDATOR.EXPECTED_PACKAGES = old_packages

    def test_matching_list_is_accepted(self):
        self.assertEqual(
            self.run_validator(("alpha", "beta"), ("alpha", "beta")), []
        )

    def test_forgotten_package_is_reported(self):
        errors = self.run_validator(("alpha",), ("alpha", "beta"))
        self.assertTrue(
            any("PACKAGES differs" in error for error in errors), errors
        )

    def test_missing_detection_branch_is_reported(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tools = root / ".github/tools"
            tools.mkdir(parents=True)
            (tools / "package_updates.sh").write_text(
                "readonly -a PACKAGES=(\n    alpha\n)\n", encoding="utf-8"
            )
            old_root = VALIDATOR.ROOT
            old_packages = VALIDATOR.EXPECTED_PACKAGES
            VALIDATOR.ROOT = root
            VALIDATOR.EXPECTED_PACKAGES = ("alpha",)
            try:
                errors = []
                VALIDATOR.validate_updater_package_list(errors)
            finally:
                VALIDATOR.ROOT = old_root
                VALIDATOR.EXPECTED_PACKAGES = old_packages
        self.assertTrue(
            any("no branch for alpha" in error for error in errors), errors
        )


class RecipeStyleTests(unittest.TestCase):
    RECIPE = """name='demo'
version={version}
release=1
architectures=('amd64')
compatible_with=('{compatible}')
maintainer='Demo <demo@example.invalid>'
license=('MIT')
provides=()
replaces=('demo')
conflicts=()
auto_reqprov_method='dirty'
auto_req=0
auto_prov=0
disable_network=1
deps=()
sources=()
checksums=()
package() {{ :; }}
files() {{ :; }}
"""

    def validate(self, version, *, compatible="altlinux_p11", extra=""):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "demo").mkdir()
            (root / "demo/Staplerfile").write_text(
                self.RECIPE.format(version=version, compatible=compatible) + extra,
                encoding="utf-8",
            )
            update_check = root / "demo/.stapler/update-check"
            update_check.parent.mkdir()
            update_check.write_text("#!/bin/sh\nprintf '1.2.3\\n'\n", encoding="utf-8")
            update_check.chmod(0o755)
            old_root = VALIDATOR.ROOT
            VALIDATOR.ROOT = root
            try:
                errors = []
                VALIDATOR.validate_package(
                    "demo", errors, {"architectures": ["amd64"]}
                )
                return errors
            finally:
                VALIDATOR.ROOT = old_root

    def test_quoted_version_is_accepted(self):
        errors = self.validate("'1.2.3'")
        self.assertFalse(
            any("single-quoted" in error for error in errors), errors
        )

    def test_unquoted_version_is_rejected(self):
        errors = self.validate("1.2.3")
        self.assertTrue(
            any("single-quoted" in error for error in errors), errors
        )

    def test_broad_alt_and_other_branch_compatibility_are_rejected(self):
        for compatible in ("altlinux", "altlinux_sisyphus", "altlinux_p10"):
            with self.subTest(compatible=compatible):
                errors = self.validate("'1.2.3'", compatible=compatible)
                self.assertTrue(
                    any(
                        "compatible_with must be ['altlinux_p11']" in error
                        for error in errors
                    ),
                    errors,
                )

    def test_single_branch_dependencies_cannot_be_hidden_in_overrides(self):
        cases = {
            "altlinux": True,
            "altlinux_p11": True,
            "altlinux_sisyphus": True,
            "altlinux_p10": True,
            "amd64_altlinux": True,
            "amd64_altlinux_p11": True,
            "arm64_altlinux_sisyphus": True,
            "amd64": False,
            "arm64": False,
        }
        for field in ("deps", "opt_deps", "build_deps"):
            for suffix, rejected in cases.items():
                with self.subTest(field=field, suffix=suffix):
                    override = f"{field}_{suffix}"
                    errors = self.validate(
                        "'1.2.3'", extra=f"{override}=('example')\n"
                    )
                    self.assertEqual(
                        any(
                            f"{override} is redundant or unsupported" in error
                            for error in errors
                        ),
                        rejected,
                        errors,
                    )
                    if not rejected:
                        self.assertEqual(errors, [])


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


class ReadmeTests(unittest.TestCase):
    @staticmethod
    def fixture() -> tuple[str, dict[str, dict[str, object]]]:
        metadata = {
            "alpha": {"version": "1.2.3", "architectures": ["amd64"]},
            "beta": {"version": "4.5.6", "architectures": ["amd64", "arm64"]},
            "gamma": {"version": "7.0", "architectures": ["all"]},
            "delta": {"version": "8.0", "architectures": ["amd64"]},
            "epsilon": {"version": "9.0", "architectures": ["amd64"]},
        }
        for package, values in metadata.items():
            values["homepage"] = f"https://{package}.example/"
        sections = []
        groups = [("alpha", "beta"), ("gamma",), ("delta",), ("epsilon",)]
        for category, packages in zip(VALIDATOR.EXPECTED_README_CATEGORIES, groups, strict=True):
            cards = []
            for package in packages:
                values = metadata[package]
                arches = " ".join(f"<code>{arch}</code>" for arch in values["architectures"])
                span = 'colspan="2"' if len(packages) == 1 else 'width="50%"'
                cards.append(f'''<td {span} valign="top">
<!-- package-card:{package} -->
<h3><img src="{package}/icon.svg" alt=""> <a href="{package}/README.md">{package}</a></h3>
<p>Description. <a href="{values['homepage']}">Сайт</a></p>
<!-- package-meta:{package} --><p><sub>Версия <code>{values['version']}</code> · {arches}</sub></p><!-- /package-meta:{package} -->
</td>''')
            sections.append(f"## {category}\n\n<table>\n<tr>\n" + "\n".join(cards) + "\n</tr>\n</table>")
        text = """<!-- package-count -->
<p><strong>5 пакетов</strong></p>
<!-- catalog:start -->
""" + "\n\n".join(sections) + "\n<!-- catalog:end -->\n"
        return text, metadata

    def test_two_column_cards_and_spanning_cards_are_valid(self):
        text, metadata = self.fixture()
        for counter in ("5 пакетов", "5 приложений"):
            with self.subTest(counter=counter):
                errors = []
                VALIDATOR.validate_readme_text(text.replace("5 пакетов", counter), metadata, errors)
                self.assertEqual(errors, [])

    def test_readme_regressions_are_rejected(self):
        text, metadata = self.fixture()
        cases = {
            "wrong counter": (text.replace("5 пакетов", "6 пакетов"), "counter"),
            "duplicate counter": ("<!-- package-count -->" + text, "counter"),
            "missing card": (
                text.replace("<!-- package-card:beta -->", ""),
                "one package card for beta",
            ),
            "duplicate card": (
                text.replace(
                    "<!-- package-card:beta -->", "<!-- package-card:alpha -->",
                ),
                "one package card for alpha",
            ),
            "unknown card": (text.replace("package-card:beta", "package-card:unknown"), "unknown package cards"),
            "two packages in one cell": (
                text.replace("<!-- package-card:alpha -->", "<!-- package-card:alpha --><!-- package-card:beta -->"),
                "every card cell",
            ),
            "stale version": (
                text.replace("<code>4.5.6</code>", "<code>4.5.5</code>"),
                "version 4.5.6",
            ),
            "extra architecture": (
                text.replace("<code>1.2.3</code> · <code>amd64</code>",
                             "<code>1.2.3</code> · <code>amd64</code> <code>arm64</code>"),
                "architectures differ",
            ),
            "duplicate architecture": (
                text.replace("<code>1.2.3</code> · <code>amd64</code>",
                             "<code>1.2.3</code> · <code>amd64</code> <code>amd64</code>"),
                "architectures differ",
            ),
            "architecture moved outside metadata": (
                text.replace("<code>4.5.6</code> · <code>amd64</code> <code>arm64</code>",
                             "<code>4.5.6</code> · <code>amd64</code>")
                    .replace("<!-- /package-meta:beta -->",
                             "<!-- /package-meta:beta --><p>Also mentions <code>arm64</code>.</p>"),
                "architectures differ",
            ),
            "missing metadata boundary": (text.replace("<!-- /package-meta:alpha -->", ""), "metadata"),
            "cross-card metadata": (
                text.replace("package-meta:alpha", "package-meta:swap")
                    .replace("package-meta:beta", "package-meta:alpha")
                    .replace("package-meta:swap", "package-meta:beta"),
                "metadata block",
            ),
            "metadata before card marker": (
                text.replace("<!-- package-card:alpha -->", "")
                    .replace("<!-- /package-meta:alpha -->", "<!-- /package-meta:alpha --><!-- package-card:alpha -->"),
                "metadata is out of order",
            ),
            "unexpected metadata markup": (
                text.replace("<p><sub>Версия", '<p class="extra"><sub>Версия', 1),
                "invalid metadata paragraph",
            ),
            "unknown metadata outside catalogue": (
                text + "<!-- package-meta:unknown --><!-- /package-meta:unknown -->",
                "metadata markers",
            ),
            "missing package link": (text.replace('href="alpha/README.md"', 'href="beta/README.md"'), "package README link"),
            "wrong website": (text.replace('href="https://alpha.example/"', 'href="https://other.example/"'), "official homepage link"),
            "missing icon": (text.replace('<img src="alpha/icon.svg" alt="">', ""), "icon is missing"),
            "missing category": (
                text.replace(f"## {VALIDATOR.EXPECTED_README_CATEGORIES[-1]}\n", ""),
                "category",
            ),
            "table without category": (
                text.replace("<!-- catalog:end -->", "<table></table><!-- catalog:end -->"),
                "each category",
            ),
            "single card without span": (
                text.replace('<td colspan="2" valign="top">', '<td valign="top">', 1),
                "each row needs",
            ),
            "empty row": (
                text.replace("</table>", '<tr></tr></table>', 1),
                "each row needs",
            ),
            "empty placeholder cell": (
                text.replace("</tr>", '<td></td></tr>', 1),
                "every card cell",
            ),
            "duplicate category": (
                text.replace(
                    VALIDATOR.EXPECTED_README_CATEGORIES[-1],
                    VALIDATOR.EXPECTED_README_CATEGORIES[0],
                ),
                "catalog categories",
            ),
            "missing catalogue boundary": (text.replace("<!-- catalog:end -->", ""), "boundary markers"),
            "duplicate catalogue boundary": (text + "<!-- catalog:end -->", "boundary markers"),
            "unbalanced card markup": (text.replace("</sub>", "", 1), "unbalanced catalogue HTML"),
            "card marker outside catalogue": (
                text.replace("<!-- package-card:alpha -->", "") + "<!-- package-card:alpha -->",
                "markers must stay inside",
            ),
        }
        for name, (candidate, expected) in cases.items():
            with self.subTest(name=name):
                errors = []
                VALIDATOR.validate_readme_text(candidate, metadata, errors)
                self.assertTrue(any(expected in error for error in errors), errors)


class HeroTests(unittest.TestCase):
    def test_hero_requires_valid_bounded_svg_with_the_declared_viewbox(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            asset = root / ".github/assets/readme-hero.svg"
            asset.parent.mkdir(parents=True)
            valid = b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 360"><rect width="1200" height="360"/></svg>'
            asset.write_bytes(valid)
            old_root = VALIDATOR.ROOT
            VALIDATOR.ROOT = root
            try:
                errors = []
                VALIDATOR.validate_readme_hero(errors)
                self.assertEqual(errors, [])

                cases = {
                    "malformed XML": b"not an SVG",
                    "wrong root": b'<html xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 360"/>',
                    "wrong viewBox": valid.replace(b"1200 360", b"1200 400"),
                    "oversized SVG": valid + b" " * (1024 * 1024),
                }
                for name, candidate in cases.items():
                    with self.subTest(name=name):
                        asset.write_bytes(candidate)
                        errors = []
                        VALIDATOR.validate_readme_hero(errors)
                        self.assertEqual(len(errors), 1, errors)
            finally:
                VALIDATOR.ROOT = old_root


class WorkflowTests(unittest.TestCase):
    def test_mutable_sources_are_checked_hourly(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workflow = root / ".github/workflows/check-updates.yml"
            workflow.parent.mkdir(parents=True)
            workflow.write_text(
                'on:\n  schedule:\n    - cron: "17 * * * *"\n',
                encoding="utf-8",
            )
            old_root = VALIDATOR.ROOT
            VALIDATOR.ROOT = root
            try:
                errors = []
                VALIDATOR.validate_autonomous_update_workflow(errors)
                self.assertEqual(errors, [])

                workflow.write_text(
                    'on:\n  schedule:\n    - cron: "0 17 * * *"\n',
                    encoding="utf-8",
                )
                errors = []
                VALIDATOR.validate_autonomous_update_workflow(errors)
                self.assertEqual(len(errors), 1)
            finally:
                VALIDATOR.ROOT = old_root


class AppStreamTests(unittest.TestCase):
    def test_sidecar_reports_the_launchable_it_declares(self):
        with tempfile.TemporaryDirectory() as directory:
            package_dir = Path(directory)
            sidecar = package_dir / "com.example.App.metainfo.xml"
            # The component id and the desktop id need not match: upstream
            # ChatGPT is com.openai.chatgpt launching chatgpt.desktop.
            sidecar.write_text(
                """<component type="desktop-application">
  <id>com.example.App</id>
  <launchable type="desktop-id">example.desktop</launchable>
</component>
""",
                encoding="utf-8",
            )
            errors = []
            launchable = VALIDATOR.validate_appstream_sidecar(
                "demo", package_dir, "com.example.App", errors
            )
            self.assertEqual(errors, [])
            self.assertEqual(launchable, "example.desktop")

            sidecar.write_text(
                "<component><id>wrong</id></component>", encoding="utf-8"
            )
            errors = []
            launchable = VALIDATOR.validate_appstream_sidecar(
                "demo", package_dir, "com.example.App", errors
            )
            self.assertIsNone(launchable)
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


class PackageLayoutTests(unittest.TestCase):
    RECIPE = (
        "sources=(\n"
        "\t'https://example.invalid/app.tar.gz'\n"
        "\t'local:///app-launcher'\n"
        ")\n\n"
        "checksums=(\n"
        "\t'sha256:{zero}'\n"
        "\t'sha256:{zero}'\n"
        ")\n\n"
        "package() {{\n"
        "\tinstall -Dm755 app-launcher \"${{pkgdir}}/usr/bin/app\"\n"
        "}}\n"
    ).format(zero="0" * 64)

    def layout(self, files, appstream_id=None, recipe=None):
        with tempfile.TemporaryDirectory() as directory:
            package_dir = Path(directory)
            for name, payload in files.items():
                target = package_dir / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(payload)
            errors = []
            VALIDATOR.validate_package_directory(
                "demo", package_dir, recipe or self.RECIPE, appstream_id, errors
            )
            return errors

    def test_declared_local_source_and_layout_files_are_accepted(self):
        errors = self.layout({
            "Staplerfile": b"x",
            "README.md": b"y",
            "postinstall.sh": b"z",
            "tests/test-thing.sh": b"t",
            "app-launcher": b"launcher",
        })
        self.assertEqual(errors, [])

    def test_file_that_is_neither_source_nor_layout_is_rejected(self):
        # Per-package repository configs are unused: Stapler reads one root file.
        errors = self.layout({"Staplerfile": b"x", "stapler-repo.toml": b"q"})
        self.assertEqual(len(errors), 1)
        self.assertIn("stapler-repo.toml", errors[0])

    def test_appstream_icon_and_metadata_are_allowed_under_their_id(self):
        errors = self.layout(
            {
                "Staplerfile": b"x",
                "com.example.App.metainfo.xml": b"<component/>",
                "com.example.App.png": b"icon",
            },
            appstream_id="com.example.App",
        )
        self.assertEqual(errors, [])

    def test_current_catalog_package_layouts_are_closed(self):
        for package in VALIDATOR.EXPECTED_PACKAGES:
            with self.subTest(package=package):
                package_dir = VALIDATOR.ROOT / package
                recipe = (package_dir / "Staplerfile").read_text(encoding="utf-8")
                errors = []
                VALIDATOR.validate_package_directory(
                    package,
                    package_dir,
                    recipe,
                    VALIDATOR.scalar(recipe, "appstream_app_id"),
                    errors,
                )
                self.assertEqual(errors, [])

    def test_two_names_for_the_same_icon_are_rejected(self):
        errors = self.layout(
            {
                "Staplerfile": b"x",
                "app.png": b"same-bytes",
                "com.example.App.png": b"same-bytes",
            },
            appstream_id="com.example.App",
            recipe=self.RECIPE.replace("local:///app-launcher", "local:///app.png"),
        )
        self.assertEqual(len(errors), 1)
        self.assertIn("duplicates", errors[0])

    def test_identical_hooks_are_not_treated_as_leftovers(self):
        # postinstall and postremove legitimately run the same cache refresh.
        errors = self.layout({
            "Staplerfile": b"x",
            "postinstall.sh": b"refresh",
            "postremove.sh": b"refresh",
        })
        self.assertEqual(errors, [])


class LocalSourceUseTests(unittest.TestCase):
    def test_local_source_never_read_by_the_recipe_is_rejected(self):
        recipe = (
            "sources=(\n\t'local:///icon.svg'\n)\n\n"
            "checksums=(\n\t'sha256:%s'\n)\n\n"
            "package() {\n\t:\n}\n" % ("0" * 64)
        )
        errors = []
        VALIDATOR.validate_local_sources_are_used("demo", recipe, errors)
        self.assertEqual(len(errors), 1)
        self.assertIn("icon.svg", errors[0])

    def test_local_source_used_in_the_body_is_accepted(self):
        recipe = (
            "sources=(\n\t'local:///icon.svg'\n)\n\n"
            "checksums=(\n\t'sha256:%s'\n)\n\n"
            "package() {\n\tinstall -Dm644 icon.svg \"${pkgdir}/x\"\n}\n"
            % ("0" * 64)
        )
        errors = []
        VALIDATOR.validate_local_sources_are_used("demo", recipe, errors)
        self.assertEqual(errors, [])


class RecipeContinuationTests(unittest.TestCase):
    def test_continuation_running_into_a_command_is_rejected(self):
        # A trailing backslash makes files-find consume the next command as
        # a path pattern and fail far from the actual typo.
        recipe = (
            "files() {\n"
            "\tfiles-find \\\n"
            '\t\t"/usr/share/metainfo/app.metainfo.xml" \\\n'
            "\tfiles-find '/usr/share/icons/hicolor/*/apps/app.png'\n"
            "}\n"
        )
        errors = []
        VALIDATOR.validate_recipe_continuations("demo", recipe, errors)
        self.assertEqual(len(errors), 1)
        self.assertIn("files-find", errors[0])

    def test_properly_continued_argument_list_is_accepted(self):
        recipe = (
            "files() {\n"
            "\tfiles-find \\\n"
            '\t\t"/usr/share/metainfo/app.metainfo.xml" \\\n'
            "\t\t'/usr/share/icons/hicolor/*/apps/app.png'\n"
            "}\n"
        )
        errors = []
        VALIDATOR.validate_recipe_continuations("demo", recipe, errors)
        self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()
