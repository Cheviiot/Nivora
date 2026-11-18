#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import os
import re
import shlex
import sys
import tomllib
import xml.etree.ElementTree as ET
from html import escape, unescape
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]

EXPECTED_PACKAGES = (
    "anidesk",
    "antigravity",
    "balena-etcher",
    "chatgpt",
    "claude",
    "happ",
    "opencode",
    "parsec",
    "pineconemc",
    "tailscale",
    "telegram",
    "yandex-music",
)

REQUIRED_ROOT_FILES = {
    Path("README.md"),
    Path("CHANGELOG.md"),
    Path("CONTRIBUTING.md"),
    Path("SECURITY.md"),
    Path("LICENSE"),
    Path("stapler-repo.toml"),
    Path(".github/assets/readme-hero.svg"),
    Path(".github/support-matrix.toml"),
    Path(".github/docs/index.md"),
    Path(".github/docs/installation.md"),
    Path(".github/docs/package-guide.md"),
    Path(".github/docs/troubleshooting.md"),
    Path(".github/docs/maintenance.md"),
    Path(".github/docs/security-model.md"),
    *(Path(f"{package}/README.md") for package in EXPECTED_PACKAGES),
}

CHECKSUM_RE = re.compile(r"(?:sha256:)?[0-9a-f]{64}\Z")
MARKDOWN_LINK_RE = re.compile(r"!?\[[^\]]*\]\(([^)\s]+)(?:\s+[^)]*)?\)")
HTML_LINK_RE = re.compile(r"(?:src|href)=[\"']([^\"']+)[\"']")
SECRET_PATTERNS = (
    re.compile(r"-----BEGIN (?:RSA |OPENSSH |EC )?PRIVATE KEY-----"),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}\b"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
)

APPROVED_TRANSITION_ALIASES = {
    "chatgpt": ["codex"],
    "claude": ["claude-desktop"],
    "telegram": ["telegram-desktop"],
}
SUPPORTED_TIERS = {"verified", "partial", "unsupported"}
# ALT p11 is the sole build and runtime target.
EXPECTED_TARGETS = {"alt-p11"}
SUPPORTED_ARCHITECTURES = {"amd64", "arm64"}
# Fields that used to carry a foreign distribution's dependency list. Their
# presence now means the recipe was written against the pre-ALT layout.
FOREIGN_DISTRO_SUFFIXES = (
    "debian",
    "ubuntu",
    "fedora",
    "arch",
    "opensuse",
    "opensuse_leap",
    "suse",
    "alpine",
)
OVERRIDABLE_LIST_FIELDS = ("deps", "opt_deps", "build_deps")

# Every file a package directory is allowed to hold beyond its own payload.
# Anything else has to be a declared local source, otherwise it is dead weight
# that no build, no check and no installed package ever reads.
PACKAGE_DIRECTORY_FILES = {
    "Staplerfile",
    "README.md",
    "LICENSE",
    "preinstall.sh",
    "postinstall.sh",
    "preremove.sh",
    "postremove.sh",
    ".stapler/update-check",
    ".stapler/update-run",
}
PACKAGE_TEST_RE = re.compile(r"tests/test-[a-z0-9-]+\.sh\Z")
# Stapler helpers a continued line must never run into. A trailing backslash
# followed by one of these swallows the command name as an argument: the build
# then fails far from the typo, with files-find reporting a pattern that does
# not exist because the pattern it got was the literal string "files-find".
RECIPE_COMMANDS = (
    "files-find",
    "files-find-binary",
    "files-find-desktop",
    "files-find-doc",
    "files-find-lang",
    "files-find-library",
    "files-find-license",
    "files-find-manual",
    "install",
    "install-binary",
    "install-config",
    "install-desktop",
    "install-library",
    "install-license",
    "install-manual",
    "install-pixmap",
    "install-systemd",
    "install-systemd-user",
)
EXPECTED_README_CATEGORIES = (
    "AI и разработка",
    "Интернет, сеть и VPN",
    "Медиа и игры",
    "Системные инструменты",
)


def scalar(text: str, field: str) -> str | None:
    match = re.search(
        rf"^{re.escape(field)}=(?:'([^']*)'|\"([^\"]*)\"|([^#\n]+))",
        text,
        re.MULTILINE,
    )
    if not match:
        return None
    return next(value.strip() for value in match.groups() if value is not None)


def array(text: str, field: str) -> list[str] | None:
    match = re.search(
        rf"^{re.escape(field)}=\((.*?)\)", text, re.MULTILINE | re.DOTALL
    )
    if not match:
        return None
    try:
        return shlex.split(match.group(1), comments=True, posix=True)
    except ValueError:
        return None


def source_arrays(text: str) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for match in re.finditer(r"^(sources(?:_[a-z0-9_]+)?)=\(", text, re.MULTILINE):
        name = match.group(1)
        values = array(text, name)
        if values is not None:
            result[name] = values
    return result


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def local_source_name(source: str) -> str | None:
    if not source.startswith("local:///"):
        return None
    value = unquote(source.removeprefix("local:///").split("?", 1)[0])
    path = Path(value)
    if not value or path.is_absolute() or ".." in path.parts:
        return ""
    return value


def validate_appstream_sidecar(
    package: str,
    directory: Path,
    appstream_id: str,
    errors: list[str],
) -> str | None:
    """Check the sidecar and report the desktop entry it launches.

    A component id need not equal its desktop id: upstream ChatGPT ships
    com.openai.chatgpt with <launchable>chatgpt.desktop</launchable>, which is
    perfectly valid AppStream. So the launchable is read from the document
    rather than guessed from the id, and the caller checks the recipe really
    installs that entry.
    """
    sidecar = directory / f"{appstream_id}.metainfo.xml"
    if not sidecar.is_file():
        errors.append(f"G2 {package}: missing Stapler AppStream sidecar {sidecar.name}")
        return None
    try:
        root = ET.parse(sidecar).getroot()
    except (ET.ParseError, OSError) as error:
        errors.append(f"G2 {package}: invalid AppStream sidecar: {error}")
        return None

    def local_name(tag: str) -> str:
        return tag.rsplit("}", 1)[-1]

    if local_name(root.tag) != "component" or root.get("type") != "desktop-application":
        errors.append(f"G2 {package}: AppStream sidecar must be a desktop component")
    component_ids = [
        (child.text or "").strip()
        for child in root
        if local_name(child.tag) == "id"
    ]
    if component_ids != [appstream_id]:
        errors.append(
            f"G2 {package}: AppStream sidecar ID differs from {appstream_id}"
        )
    launchables = [
        (child.text or "").strip()
        for child in root
        if local_name(child.tag) == "launchable"
        and child.get("type") == "desktop-id"
    ]
    if len(launchables) != 1 or not launchables[0].endswith(".desktop"):
        errors.append(
            f"G2 {package}: AppStream sidecar needs exactly one desktop-id "
            "launchable"
        )
        return None
    return launchables[0]


def validate_recipe_continuations(
    package: str, text: str, errors: list[str]
) -> None:
    """Catch a continued line that runs into the next command."""
    lines = text.splitlines()
    for index, line in enumerate(lines[:-1]):
        if not line.rstrip().endswith("\\"):
            continue
        following = lines[index + 1].strip()
        if following.split(" ", 1)[0] in RECIPE_COMMANDS:
            errors.append(
                f"G0 {package}: line {index + 1} continues into "
                f"{following.split(' ', 1)[0]!r} on the next line"
            )


def validate_package_directory(
    package: str,
    directory: Path,
    text: str,
    appstream_id: str | None,
    errors: list[str],
) -> None:
    """Reject files a package directory has no use for.

    Nivora carried fifteen per-package stapler-repo.toml files in two
    mutually incompatible dialects before this rule existed. Stapler reads
    none of them: its repository config is a single file at the repository
    root. The only way such a file accumulates is that nothing ever looked.
    """
    allowed = set(PACKAGE_DIRECTORY_FILES)
    for group in source_arrays(text).values():
        for source in group:
            name = local_source_name(source)
            if name:
                allowed.add(name)
    if appstream_id:
        allowed.update(
            f"{appstream_id}{suffix}" for suffix in (".metainfo.xml", ".svg", ".png")
        )

    seen: dict[str, str] = {}
    for path in sorted(directory.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(directory).as_posix()
        if relative.split("/", 1)[0] == "__pycache__" or relative.endswith(".rpm"):
            continue
        if relative not in allowed and not PACKAGE_TEST_RE.fullmatch(relative):
            errors.append(
                f"G0 {package}: {relative} is neither a declared local source "
                "nor a file the packaging layout uses"
            )
            continue
        # Two names for the same asset means one of them is a leftover: the
        # icon GNOME Software reads and the icon the payload installs are the
        # same picture. Hook scripts are exempt — postinstall and postremove
        # legitimately run the same cache refresh.
        if path.suffix not in {".png", ".svg", ".xml", ".desktop"}:
            continue
        digest = sha256(path)
        if digest in seen:
            errors.append(
                f"G0 {package}: {relative} duplicates {seen[digest]} byte for byte"
            )
        else:
            seen[digest] = relative


def validate_local_sources_are_used(
    package: str, text: str, errors: list[str]
) -> None:
    """A local source that package() never reads only costs a checksum."""
    bodies = [
        match.end()
        for match in re.finditer(
            r"^checksums(?:_[a-z0-9_]+)?=\(.*?\)", text, re.MULTILINE | re.DOTALL
        )
    ]
    body = text[max(bodies, default=0):]
    for group in source_arrays(text).values():
        for source in group:
            name = local_source_name(source)
            if name and name not in body:
                errors.append(
                    f"G1 {package}: local source {name} is declared but never used"
                )


def markdown_targets(text: str) -> set[str]:
    return set(MARKDOWN_LINK_RE.findall(text)) | set(HTML_LINK_RE.findall(text))


def flag(text: str, field: str, default: int | None = None) -> int | None:
    value = scalar(text, field)
    if value is None:
        return default
    if value not in {"0", "1"}:
        return None
    return int(value)


def expanded_architectures(architectures: list[str]) -> list[str]:
    if architectures == ["all"]:
        return ["amd64", "arm64"]
    return architectures


def load_support_matrix(errors: list[str]) -> dict[str, object]:
    path = ROOT / ".github/support-matrix.toml"
    try:
        with path.open("rb") as stream:
            matrix = tomllib.load(stream)
    except (OSError, tomllib.TOMLDecodeError) as error:
        errors.append(f".github/support-matrix.toml: {error}")
        return {}

    targets = matrix.get("targets", [])
    target_ids = [item.get("id") for item in targets if isinstance(item, dict)]
    targets_by_id = {
        item["id"]: item
        for item in targets
        if isinstance(item, dict) and isinstance(item.get("id"), str)
    }
    if len(target_ids) != len(set(target_ids)):
        errors.append("support matrix: duplicate target IDs")
    if set(target_ids) != EXPECTED_TARGETS:
        errors.append(
            "support matrix: the only approved target is alt-p11"
        )
    for target in targets:
        if not isinstance(target, dict):
            continue
        if target.get("distro") != "altlinux":
            errors.append(
                f"support matrix: {target.get('id')}: only ALT targets are supported"
            )
        if target.get("release") != "p11" or target.get("branch_id") != "p11":
            errors.append(
                f"support matrix: {target.get('id')}: release and branch_id must be p11"
            )
        gated = target.get("gated_architectures")
        if not isinstance(gated, list) or any(
            arch not in SUPPORTED_ARCHITECTURES for arch in gated
        ):
            errors.append(
                f"support matrix: {target.get('id')}: invalid gated_architectures"
            )

    packages = matrix.get("packages", [])
    package_ids = [item.get("id") for item in packages if isinstance(item, dict)]
    if len(package_ids) != len(set(package_ids)):
        errors.append("support matrix: duplicate package IDs")
    if set(package_ids) != set(EXPECTED_PACKAGES):
        errors.append("support matrix: package IDs differ from repository packages")

    logical_cells = 0
    scheduled_cells = 0
    verified_cells = 0
    for package in packages:
        if not isinstance(package, dict):
            errors.append("support matrix: every package entry must be a table")
            continue
        package_id = package.get("id", "<unknown>")
        architectures = package.get("architectures")
        if not isinstance(architectures, list) or not architectures:
            errors.append(f"support matrix: {package_id}: architectures are missing")
            continue
        expanded = expanded_architectures(architectures)
        if any(arch not in SUPPORTED_ARCHITECTURES for arch in expanded):
            errors.append(f"support matrix: {package_id}: invalid architectures")

        # Every (target, architecture) cell is declared exactly once, so a tier
        # never has to stand for a mix of gated and ungated architectures.
        coverage: dict[tuple[str, str], dict[str, object]] = {}
        for group in package.get("support", []):
            if not isinstance(group, dict):
                errors.append(f"support matrix: {package_id}: invalid support group")
                continue
            tier = group.get("tier")
            caveats = group.get("caveats")
            group_targets = group.get("targets")
            group_arches = group.get("architectures")
            if tier not in SUPPORTED_TIERS:
                errors.append(f"support matrix: {package_id}: invalid tier {tier!r}")
            if not isinstance(caveats, list) or any(
                not isinstance(item, str) or not item for item in caveats
            ):
                errors.append(f"support matrix: {package_id}: invalid caveats")
            elif tier != "verified" and not caveats:
                errors.append(
                    f"support matrix: {package_id}: {tier} needs a concrete caveat"
                )
            if not isinstance(group_targets, list):
                errors.append(f"support matrix: {package_id}: targets must be an array")
                continue
            if not isinstance(group_arches, list) or not group_arches:
                errors.append(
                    f"support matrix: {package_id}: support group needs architectures"
                )
                continue
            if any(arch not in expanded for arch in group_arches):
                errors.append(
                    f"support matrix: {package_id}: support group declares an "
                    "architecture the recipe does not build"
                )
            for target in group_targets:
                for architecture in group_arches:
                    cell = (target, architecture)
                    if cell in coverage:
                        errors.append(
                            f"support matrix: {package_id}: duplicate cell "
                            f"{target}/{architecture}"
                        )
                    coverage[cell] = group

        expected_cells = {
            (target, architecture)
            for target in EXPECTED_TARGETS
            for architecture in expanded
        }
        if set(coverage) != expected_cells:
            errors.append(
                f"support matrix: {package_id}: every target/architecture cell "
                "must occur exactly once"
            )
        for (target_id, architecture), group in coverage.items():
            logical_cells += 1
            if group.get("tier") != "unsupported":
                scheduled_cells += 1
            if group.get("tier") != "verified":
                continue
            verified_cells += 1
            target = targets_by_id.get(target_id)
            if target is None:
                continue
            if target.get("ci_mode") != "blocking-lifecycle":
                errors.append(
                    f"support matrix: {package_id}: verified target {target_id} "
                    "is not a blocking lifecycle target"
                )
            if architecture not in (target.get("gated_architectures") or []):
                errors.append(
                    f"support matrix: {package_id}: {target_id}/{architecture} "
                    "claims verified but the architecture is not gated"
                )

    expectations = matrix.get("expectations", {})
    actual = {
        "package_count": len(packages),
        "target_count": len(targets),
        "logical_runtime_cells": logical_cells,
        "declared_supported_runtime_cells": scheduled_cells,
        "verified_runtime_cells": verified_cells,
        "blocking_ci_build_cells_full_common_change": len(packages) * len(targets),
        "advisory_main_build_cells_full_common_change": len(packages),
    }
    for key, value in actual.items():
        if expectations.get(key) != value:
            errors.append(
                f"support matrix: expectations.{key}={expectations.get(key)!r}, "
                f"calculated {value}"
            )
    if set(expectations) != set(actual):
        errors.append(
            "support matrix: expectations keys differ from the calculated set"
        )
    if verified_cells:
        workflow = ROOT / ".github/workflows/package-ci.yml"
        workflow_text = (
            workflow.read_text(encoding="utf-8") if workflow.is_file() else ""
        )
        for required in (
            ".github/tools/clean_build.sh",
            ".github/tools/verify_artifacts.sh",
            ".github/tools/test_package_lifecycle.sh",
        ):
            if required not in workflow_text:
                errors.append(
                    f"support matrix: blocking lifecycle workflow lacks {required}"
                )
    ci_coverage = matrix.get("ci_coverage", {})
    if ci_coverage.get("blocking_builders") != ["alt-p11-x86_64"]:
        errors.append(
            "support matrix: the only blocking builder must be alt-p11-x86_64"
        )
    if ci_coverage.get("main_canary") != "advisory-alt-p11-x86_64":
        errors.append(
            "support matrix: the Stapler main canary must also target ALT p11"
        )

    images = matrix.get("images", {})
    if set(images) != {"alt_p11"}:
        errors.append("support matrix: images must contain only alt_p11")
    for name, image in images.items():
        if not re.fullmatch(
            r"registry\.altlinux\.org/p11/base@sha256:[0-9a-f]{64}", str(image)
        ):
            errors.append(
                f"support matrix: image {name} must be the official ALT p11 base "
                "with an exact SHA-256 digest"
            )
    stapler = matrix.get("stapler", {})
    stable_version = stapler.get("stable_version")
    if stable_version != "0.2.0":
        errors.append("support matrix: stable Stapler must be v0.2.0 from ALT p11")
    for architecture in ("x86_64", "aarch64"):
        prefix = f"stable_linux_{architecture}"
        expected_url = (
            "https://altlinux.space/stapler/stplr/releases/download/"
            f"v{stable_version}/stplr-{stable_version}-linux-{architecture}.tar.gz"
        )
        if stapler.get(f"{prefix}_url") != expected_url:
            errors.append(
                f"support matrix: {prefix}_url must match the official stable release"
            )
        if not re.fullmatch(r"[0-9a-f]{64}", str(stapler.get(f"{prefix}_sha256", ""))):
            errors.append(f"support matrix: {prefix}_sha256 must be an exact SHA-256")
    if not re.fullmatch(r"[0-9a-f]{40}", str(stapler.get("stable_commit", ""))):
        errors.append("support matrix: stable Stapler source commit must be exact")
    if not re.fullmatch(r"[0-9a-f]{40}", str(stapler.get("main_commit", ""))):
        errors.append("support matrix: Stapler main canary commit must be exact")
    return matrix


def validate_links(path: Path, errors: list[str]) -> None:
    text = path.read_text(encoding="utf-8")
    for target in markdown_targets(text):
        parsed = urlsplit(target)
        if parsed.scheme or target.startswith(("mailto:", "#")):
            continue
        local = unquote(parsed.path)
        if not local:
            continue
        if local.startswith("/"):
            errors.append(f"{path.relative_to(ROOT)}: unsafe local link: {target}")
            continue
        resolved = (path.parent / local).resolve()
        try:
            resolved.relative_to(ROOT)
        except ValueError:
            errors.append(f"{path.relative_to(ROOT)}: link escapes repository: {target}")
            continue
        if not resolved.exists():
            errors.append(f"{path.relative_to(ROOT)}: missing link target: {target}")


def validate_package(
    package: str,
    errors: list[str],
    matrix_package: dict[str, object] | None,
) -> dict[str, object]:
    directory = ROOT / package
    staplerfile = directory / "Staplerfile"
    text = staplerfile.read_text(encoding="utf-8")

    name = scalar(text, "name")
    version = scalar(text, "version")
    release = scalar(text, "release")
    architectures = array(text, "architectures")
    provides = array(text, "provides")
    replaces = array(text, "replaces")
    conflicts = array(text, "conflicts")
    maintainer = scalar(text, "maintainer")

    if name != package:
        errors.append(f"{package}: directory and name differ: {name!r}")
    if not version:
        errors.append(f"{package}: version is missing")
    elif not re.search(r"(?m)^version='[^']+'$", text):
        # stplr-spec update-package writes it back unquoted; the updater
        # restores the style before the static checks run.
        errors.append(f"G0 {package}: version must be single-quoted")
    if not release or not release.isdigit() or int(release) < 1:
        errors.append(f"{package}: release must be a positive integer")

    expected_fingerprint_fields = {
        "chatgpt": {"source_fingerprint_amd64", "source_fingerprint_arm64"},
        "parsec": {"source_fingerprint"},
    }.get(package, set())
    declared_fingerprint_fields = re.findall(
        r"^(source_fingerprint(?:_[a-z0-9_]+)?)=", text, re.MULTILINE
    )
    if set(declared_fingerprint_fields) != expected_fingerprint_fields or len(
        declared_fingerprint_fields
    ) != len(expected_fingerprint_fields):
        errors.append(
            f"G1 {package}: mutable-source fingerprint fields must be "
            f"{sorted(expected_fingerprint_fields)}"
        )
    for field in expected_fingerprint_fields:
        value = scalar(text, field)
        if value is None or not re.fullmatch(r"[0-9a-f]{64}", value):
            errors.append(f"G1 {package}: {field} must be a SHA-256 value")
    if not architectures:
        errors.append(f"{package}: architectures are missing")
    elif any(item not in {"amd64", "arm64", "all"} for item in architectures):
        errors.append(f"{package}: unsupported architecture value: {architectures}")

    aliases = APPROVED_TRANSITION_ALIASES.get(package, [])
    expected_provides = aliases if package in {"chatgpt", "telegram"} else []
    expected_conflicts = expected_provides
    if provides != expected_provides:
        errors.append(
            f"G0 {package}: provides must be {expected_provides}, got {provides}"
        )
    if conflicts != expected_conflicts:
        errors.append(
            f"G0 {package}: conflicts must be {expected_conflicts}, got {conflicts}"
        )
    expected_replaces = [package, *aliases]
    if replaces != expected_replaces:
        errors.append(
            f"G0 {package}: replaces must be {expected_replaces}, got {replaces}"
        )

    if not maintainer or not re.search(r"<[^<>\s]+@[^<>\s]+>", maintainer):
        errors.append(f"G0 {package}: maintainer must contain a valid email address")

    if flag(text, "disable_network") != 1:
        errors.append(f"G1 {package}: disable_network=1 is required")

    # license goes straight into RPM License: and into AppStream
    # project_license, so a made-up word there is what every tool reads back.
    # SPDX identifiers, or LicenseRef-* for terms that are not a public licence.
    licenses = array(text, "license") or []
    if not licenses:
        errors.append(f"G0 {package}: license must be declared")
    for value in licenses:
        if value.startswith("LicenseRef-"):
            continue
        if not re.fullmatch(r"[A-Za-z0-9.+-]+", value):
            errors.append(f"G0 {package}: license {value!r} is not an identifier")
        elif value in {"Custom", "Proprietary", "Commercial", "Other", "Unknown"}:
            errors.append(
                f"G0 {package}: license {value!r} is not SPDX; use an SPDX "
                "identifier or LicenseRef-proprietary"
            )

    # Stapler recognises distro_release IDs, so p11 compatibility is enforced
    # by its native repository filter and build pre-checks.
    compatible = array(text, "compatible_with")
    if compatible != ["altlinux_p11"]:
        errors.append(
            f"G0 {package}: compatible_with must be ['altlinux_p11'], got {compatible}"
        )
    if array(text, "incompatible_with") is not None:
        errors.append(
            f"G0 {package}: incompatible_with is obsolete; compatible_with is the "
            "whitelist"
        )
    for field in OVERRIDABLE_LIST_FIELDS:
        for suffix in FOREIGN_DISTRO_SUFFIXES:
            if array(text, f"{field}_{suffix}") is not None:
                errors.append(
                    f"G2 {package}: {field}_{suffix} belongs to a distribution "
                    "Nivora does not support"
                )
        # Stapler combines architecture and distro suffixes, for example
        # deps_amd64_altlinux_p11. A pure architecture override remains valid.
        for override in re.findall(
            rf"^({re.escape(field)}_(?:[a-z0-9]+_)*altlinux(?:_[a-z0-9_]+)?)=",
            text,
            re.MULTILINE,
        ):
            errors.append(
                f"G2 {package}: {override} is redundant or unsupported; "
                f"declare the ALT p11 list in {field} or an architecture-only override"
            )
    if array(text, "deps") is None:
        errors.append(f"G2 {package}: deps must be declared, even if empty")
    # ALT's apt-rpm cannot parse an alternative in a dependency at all, neither
    # the Debian 'a | b' form nor an RPM rich dependency.
    for field_match in re.finditer(
        r"^((?:deps|opt_deps|build_deps)(?:_[a-z0-9_]+)?)=\(", text, re.MULTILINE
    ):
        field = field_match.group(1)
        for value in array(text, field) or []:
            if "|" in value or value.startswith("("):
                errors.append(
                    f"G2 {package}: {field} entry {value!r} uses an alternative "
                    "that ALT cannot resolve"
                )

    if flag(text, "auto_prov") != 0:
        errors.append(
            f"G2 {package}: auto_prov must stay 0 so a bundled runtime is never "
            "advertised system-wide"
        )
    if flag(text, "auto_req") not in {0, 1}:
        errors.append(f"G2 {package}: auto_req must be 0 or 1")
    # The native ALT finder would need auto_prov to cancel out the sonames a
    # self-contained payload ships itself. The dirty finder subtracts them on
    # its own, which is the only combination that keeps auto_prov disabled.
    if scalar(text, "auto_reqprov_method") != "dirty":
        errors.append(f"G2 {package}: auto_reqprov_method must be dirty")
    for override in re.findall(
        r"^(auto_(?:req|prov|reqprov_method)_[a-z0-9_]+)=", text, re.MULTILINE
    ):
        errors.append(
            f"G2 {package}: {override} is a per-distribution override and ALT is "
            "the only target"
        )

    matrix_architectures = (
        matrix_package.get("architectures") if matrix_package is not None else None
    )
    if matrix_architectures != architectures:
        errors.append(
            f"G0 {package}: recipe/matrix architectures differ: "
            f"{architectures} != {matrix_architectures}"
        )

    appstream_id = scalar(text, "appstream_app_id")
    validate_package_directory(package, directory, text, appstream_id, errors)
    validate_local_sources_are_used(package, text, errors)
    validate_recipe_continuations(package, text, errors)
    has_appstream_payload = bool(
        re.search(r"/usr/share/(?:metainfo|appdata)/[^\s'\"]+\.(?:metainfo|appdata)\.xml", text)
    )
    if appstream_id:
        if not has_appstream_payload:
            errors.append(f"G2 {package}: appstream_app_id lacks metadata payload")
        launchable = validate_appstream_sidecar(
            package, directory, appstream_id, errors
        )
        if launchable:
            expected_desktop = f"/usr/share/applications/{launchable}"
            if expected_desktop not in text:
                errors.append(
                    f"G2 {package}: sidecar launches {launchable}, but the recipe "
                    f"does not install {expected_desktop}"
                )
        # The GNOME Software plugin for Stapler resolves the icon by name from
        # the package directory of the checked-out repository:
        #   /var/cache/stplr/repo/<repo>/<package>/<appstream id>.{svg,png}
        # Without a file under exactly that name the application shows up in
        # GNOME Software with no icon at all.
        if not any(
            (directory / f"{appstream_id}{suffix}").is_file()
            for suffix in (".svg", ".png")
        ):
            errors.append(
                f"G2 {package}: GNOME Software needs {appstream_id}.svg or "
                f"{appstream_id}.png next to the Staplerfile"
            )
    elif has_appstream_payload:
        errors.append(f"G2 {package}: metadata payload needs appstream_app_id")
    elif "/usr/share/applications/" in text or "install-desktop" in text:
        # A package with a desktop entry is an application, and an application
        # without appstream_app_id is invisible to the GNOME Software plugin:
        # it matches packages with `appstream_app_id == '<id>'` and nothing else.
        errors.append(
            f"G2 {package}: installs a desktop entry but declares no "
            "appstream_app_id, so GNOME Software cannot offer it"
        )

    if "package()" not in text or "files()" not in text:
        errors.append(f"{package}: package() or files() is missing")

    arrays = source_arrays(text)
    if not arrays:
        errors.append(f"{package}: sources are missing")
    for source_field, sources in arrays.items():
        checksum_field = source_field.replace("sources", "checksums", 1)
        checksums = array(text, checksum_field)
        if checksums is None:
            errors.append(f"{package}: {checksum_field} is missing")
            continue
        if len(sources) != len(checksums):
            errors.append(
                f"{package}: {source_field}/{checksum_field} lengths differ "
                f"({len(sources)} != {len(checksums)})"
            )
            continue
        for source, checksum in zip(sources, checksums, strict=True):
            if checksum == "SKIP" or not CHECKSUM_RE.fullmatch(checksum):
                errors.append(f"{package}: invalid checksum for {source}: {checksum}")
                continue
            if source.startswith("http://"):
                errors.append(f"{package}: insecure source URL: {source}")
            if source.startswith("git+") and "#" not in source:
                errors.append(f"{package}: unpinned Git source: {source}")

            local_name = local_source_name(source)
            if local_name is None:
                continue
            if local_name == "":
                errors.append(f"{package}: unsafe local source: {source}")
                continue
            local_path = directory / local_name
            if not local_path.is_file():
                errors.append(f"{package}: missing local source: {local_name}")
                continue
            expected = checksum.removeprefix("sha256:")
            actual = sha256(local_path)
            if actual != expected:
                errors.append(
                    f"{package}: checksum mismatch for {local_name}: {actual} != {expected}"
                )

    for hook in re.findall(r"\['[^']+'\]='([^']+)'", text):
        hook_path = directory / hook
        if not hook_path.is_file():
            errors.append(f"{package}: missing lifecycle script: {hook}")
        elif not os.access(hook_path, os.X_OK):
            errors.append(f"{package}: lifecycle script is not executable: {hook}")

    update_check = directory / ".stapler/update-check"
    if not update_check.is_file() or not os.access(update_check, os.X_OK):
        errors.append(f"{package}: executable .stapler/update-check is required")

    return {
        "name": name,
        "version": version,
        "homepage": scalar(text, "homepage"),
        "architectures": architectures or [],
        "local_sources": sorted(
            {
                source
                for values in arrays.values()
                for source in values
                if source.startswith("local:///")
            }
        ),
    }


def validate_unique_local_source_urls(
    metadata: dict[str, dict[str, object]], errors: list[str]
) -> None:
    owners: dict[str, str] = {}
    for package, values in metadata.items():
        local_sources = values.get("local_sources", [])
        if not isinstance(local_sources, list):
            continue
        for source in local_sources:
            owner = owners.setdefault(str(source), package)
            if owner != package:
                errors.append(
                    f"G1 {package}: local source URL collides with {owner}: {source}"
                )


class ReadmeCatalogParser(HTMLParser):
    """Locate real card cells without tying metadata to a visual column layout."""

    VOID_TAGS = {
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr",
    }

    def __init__(self, text: str) -> None:
        super().__init__(convert_charrefs=True)
        self.line_offsets = [0, *(match.end() for match in re.finditer("\n", text))]
        self.stack: list[str] = []
        self.categories: list[str] = []
        self.tables: list[dict] = []
        self.pending_category = None
        self.table = None
        self.row = None
        self.cell = None

    def absolute_position(self) -> int:
        line, column = self.getpos()
        return self.line_offsets[line - 1] + column

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attributes = dict(attrs)
        if len(attributes) != len(attrs):
            raise ValueError("duplicate HTML attributes in catalogue")
        parent = self.stack[-1] if self.stack else None
        if tag == "table":
            if self.table is not None or self.pending_category is None:
                raise ValueError("each category must have its own table after its heading")
            self.table = {"category": self.pending_category, "rows": []}
            self.tables.append(self.table)
            self.pending_category = None
        elif tag == "tr":
            if self.table is None or self.row is not None or parent not in {"table", "tbody"}:
                raise ValueError("catalogue rows must belong to their category table")
            self.row = {"cells": []}
            self.table["rows"].append(self.row)
        elif tag == "td":
            if self.row is None or self.cell is not None or parent != "tr":
                raise ValueError("package cells must belong to a catalogue row")
            span = attributes.get("colspan", "1")
            if span not in {"1", "2"}:
                raise ValueError("package cells may span only one or two columns")
            self.cell = {
                "start": self.absolute_position() + len(self.get_starttag_text()),
                "end": None,
                "span": int(span),
                "markers": [],
                "metadata": [],
                "links": [],
                "icons": [],
            }
            self.row["cells"].append(self.cell)
        elif tag == "th":
            raise ValueError("category headings belong outside the package card table")
        if self.cell is not None:
            if tag == "a":
                self.cell["links"].append(attributes.get("href"))
            elif tag == "img":
                self.cell["icons"].append(attributes.get("src"))
        if tag not in self.VOID_TAGS:
            self.stack.append(tag)

    def handle_startendtag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        self.handle_starttag(tag, attrs)
        if tag not in self.VOID_TAGS:
            self.handle_endtag(tag)

    def handle_endtag(self, tag: str) -> None:
        if not self.stack or self.stack[-1] != tag:
            raise ValueError(f"unbalanced catalogue HTML near </{tag}>")
        if tag == "td":
            self.cell["end"] = self.absolute_position()
            self.cell = None
        elif tag == "tr":
            self.row = None
        elif tag == "table":
            self.table = None
        self.stack.pop()

    def handle_data(self, data: str) -> None:
        if self.table is not None and self.cell is None and data.strip():
            raise ValueError("catalogue text must belong to a package card")
        if self.table is None and not self.stack:
            for line in data.splitlines():
                match = re.fullmatch(r"##[ \t]+(.+?)[ \t]*", line)
                if match:
                    if self.pending_category is not None:
                        raise ValueError("category heading has no card table")
                    self.pending_category = match.group(1)
                    self.categories.append(match.group(1))

    def handle_comment(self, data: str) -> None:
        comment = data.strip()
        card = re.fullmatch(r"package-card:([a-z0-9][a-z0-9-]*)", comment)
        metadata = re.fullmatch(r"(/?)package-meta:([a-z0-9][a-z0-9-]*)", comment)
        if card or metadata:
            if self.cell is None:
                raise ValueError("package markers must be inside a card cell")
            if card:
                self.cell["markers"].append((card.group(1), self.absolute_position()))
            else:
                self.cell["metadata"].append((metadata.group(1), metadata.group(2), self.absolute_position()))
        elif comment.startswith(("package-card:", "package-meta:", "/package-meta:")):
            raise ValueError("malformed package marker in catalogue")

    def close(self) -> None:
        super().close()
        if self.stack:
            raise ValueError("unclosed HTML elements in catalogue")
        if self.pending_category is not None:
            raise ValueError("category heading has no card table")


def validate_readme_text(
    text: str, metadata: dict[str, dict[str, object]], errors: list[str]
) -> None:
    count_match = re.search(
        r"<!--\s*package-count\s*-->\s*"
        r"<p[^>]*>\s*<strong>(\d+)\s+(?:пакет(?:а|ов)?|приложени[ейя])(?=\s|<)",
        text,
    )
    if (
        len(re.findall(r"<!--\s*package-count\s*-->", text)) != 1
        or not count_match
        or int(count_match.group(1)) != len(metadata)
    ):
        errors.append("README.md: package counter is stale")

    start_marker = "<!-- catalog:start -->"
    end_marker = "<!-- catalog:end -->"
    if text.count(start_marker) != 1 or text.count(end_marker) != 1:
        errors.append("README.md: catalog boundary markers must occur exactly once")
        return
    start = text.index(start_marker) + len(start_marker)
    end = text.index(end_marker)
    if start >= end:
        errors.append("README.md: catalog boundary markers are out of order")
        return
    catalog = text[start:end]

    parser = ReadmeCatalogParser(catalog)
    try:
        parser.feed(catalog)
        parser.close()
    except ValueError as error:
        errors.append(f"README.md: {error}")
        return
    if tuple(parser.categories) != EXPECTED_README_CATEGORIES:
        errors.append(
            "README.md: catalog categories must be exactly: "
            + ", ".join(EXPECTED_README_CATEGORIES)
        )

    cards = []
    for table in parser.tables:
        if not table["rows"]:
            errors.append("README.md: category tables must contain package cards")
        for row in table["rows"]:
            cells = row["cells"]
            if not (
                (len(cells) == 2 and all(cell["span"] == 1 for cell in cells))
                or (len(cells) == 1 and cells[0]["span"] == 2)
            ):
                errors.append("README.md: each row needs two cards or one card spanning both columns")
            for cell in cells:
                if len(cell["markers"]) != 1:
                    errors.append("README.md: every card cell must hold exactly one package")
                else:
                    cards.append(cell)

    marker_ids = [cell["markers"][0][0] for cell in cards]
    all_marker_ids = re.findall(r"<!-- package-card:([a-z0-9][a-z0-9-]*) -->", text)
    if sorted(all_marker_ids) != sorted(marker_ids):
        errors.append("README.md: package card markers must stay inside catalogue cells")
    expected_ids = set(metadata)
    unknown_ids = sorted(set(all_marker_ids) - expected_ids)
    if unknown_ids:
        errors.append(
            "README.md: unknown package cards: " + ", ".join(unknown_ids)
        )
    for prefix in ("", "/"):
        field_ids = re.findall(
            rf"<!-- {prefix}package-meta:([a-z0-9][a-z0-9-]*) -->", text
        )
        if sorted(field_ids) != sorted(expected_ids):
            errors.append("README.md: metadata markers must match the recipe catalogue")

    for package, values in metadata.items():
        occurrences = [cell for cell in cards if cell["markers"][0][0] == package]
        if len(occurrences) != 1:
            errors.append(f"README.md: expected one package card for {package}")
            continue
        cell = occurrences[0]
        card = catalog[cell["start"]:cell["end"]]

        if f"{package}/README.md" not in cell["links"]:
            errors.append(f"README.md: package README link is missing from {package} card")
        homepage = values.get("homepage")
        if not isinstance(homepage, str) or not any(
            isinstance(link, str) and link.rstrip("/") == homepage.rstrip("/")
            for link in cell["links"]
        ):
            errors.append(f"README.md: official homepage link is missing from {package} card")
        if not any(cell["icons"]):
            errors.append(f"README.md: icon is missing from {package} card")

        opening = f"<!-- package-meta:{package} -->"
        closing = f"<!-- /package-meta:{package} -->"
        fields = cell["metadata"]
        if (
            len(fields) != 2
            or [field[:2] for field in fields] != [("", package), ("/", package)]
            or text.count(opening) != 1
            or text.count(closing) != 1
        ):
            errors.append(f"README.md: expected one metadata block for {package}")
            continue
        metadata_start = fields[0][2] + len(opening)
        metadata_end = fields[1][2]
        if not cell["markers"][0][1] < fields[0][2] < metadata_end:
            errors.append(f"README.md: metadata is out of order for {package}")
            continue
        match = re.fullmatch(
            r"\s*<p><sub>Версия\s+<code>([^<\r\n]+)</code>\s*·\s*"
            r"((?:<code>(?:amd64|arm64|all)</code>\s*)+)</sub></p>\s*",
            catalog[metadata_start:metadata_end],
        )
        if not match:
            errors.append(f"README.md: invalid metadata paragraph for {package}")
            continue
        version = str(values["version"])
        if unescape(match.group(1)) != version or card.count(f"<code>{escape(version)}</code>") != 1:
            errors.append(f"README.md: version {version} is missing from {package} card")
        architectures = values.get("architectures", [])
        declared = re.findall(r"<code>(amd64|arm64|all)</code>", match.group(2))
        if declared != architectures:
            errors.append(f"README.md: architectures differ from the recipe for {package}")


def validate_readme(metadata: dict[str, dict[str, object]], errors: list[str]) -> None:
    path = ROOT / "README.md"
    validate_readme_text(path.read_text(encoding="utf-8"), metadata, errors)


def validate_readme_hero(errors: list[str]) -> None:
    path = ROOT / ".github/assets/readme-hero.svg"
    if not path.is_file():
        return
    try:
        if path.stat().st_size > 1024 * 1024:
            errors.append("README hero: SVG must not exceed 1 MiB")
            return
        root = ET.fromstring(path.read_bytes())
    except (OSError, ET.ParseError) as error:
        errors.append(f"README hero: cannot read SVG: {error}")
        return
    if root.tag != "{http://www.w3.org/2000/svg}svg":
        errors.append("README hero: asset must be a valid SVG")
        return
    try:
        view_box = [float(value) for value in root.get("viewBox", "").split()]
    except ValueError:
        view_box = []
    if view_box != [0, 0, 1200, 360]:
        errors.append("README hero: SVG viewBox must be 0 0 1200 360")


def validate_updater_package_list(errors: list[str]) -> None:
    """The updater carries its own package list; it must not drift.

    A package missing from this array is never checked for updates at all, and
    nothing else in the repository would notice.
    """
    path = ROOT / ".github/tools/package_updates.sh"
    if not path.is_file():
        errors.append("package_updates.sh is missing")
        return
    text = path.read_text(encoding="utf-8")
    match = re.search(r"(?ms)^readonly -a PACKAGES=\(\n(.*?)^\)$", text)
    if not match:
        errors.append("package_updates.sh: cannot read the PACKAGES array")
        return
    declared = tuple(match.group(1).split())
    if declared != tuple(sorted(EXPECTED_PACKAGES)):
        errors.append(
            "package_updates.sh: PACKAGES differs from the repository packages: "
            f"{', '.join(declared)}"
        )
    for package in EXPECTED_PACKAGES:
        if not re.search(rf"(?m)^\s+{re.escape(package)}\)", text):
            errors.append(
                f"package_updates.sh: latest_version has no branch for {package}"
            )


def validate_lifecycle_catalog(
    matrix_packages: dict[str, dict[str, object]], errors: list[str]
) -> None:
    """Keep the full lifecycle gate aligned with the recipes and support claims."""
    path = ROOT / ".github/tools/test_package_lifecycle.sh"
    if not path.is_file():
        errors.append("lifecycle catalog: test_package_lifecycle.sh is missing")
        return
    text = path.read_text(encoding="utf-8")
    match = re.search(
        r"(?ms)^readonly -a lifecycle_package_catalog=\(\n(.*?)^\)$", text
    )
    if not match:
        errors.append("lifecycle catalog: cannot read lifecycle_package_catalog")
        return
    try:
        entries = shlex.split(match.group(1), comments=True, posix=True)
    except ValueError as error:
        errors.append(f"lifecycle catalog: invalid shell array: {error}")
        return

    package_ids = []
    for entry in entries:
        fields = entry.split("|")
        package = fields[0]
        package_ids.append(package)
        if len(fields) != 6 or any(not value for value in fields):
            errors.append(f"lifecycle catalog: {package}: expected six nonempty fields")
            continue
        _, command, state, expected_a, expected_b, sandbox = fields
        for label, value in (
            ("command", command), ("state", state),
            ("expected_a", expected_a), ("expected_b", expected_b),
            ("sandbox", sandbox),
        ):
            if value == "-" and label not in {"command", "state"}:
                continue
            parts = value.split("/")
            if (
                not value.startswith("/")
                or any(part in {"", ".", ".."} for part in parts[1:])
                or any(character in value for character in "\n\r\x00")
            ):
                errors.append(
                    f"lifecycle catalog: {package}: {label} needs a canonical absolute path"
                )
        if not state.startswith(("/home/nivora-test/", "/var/lib/")):
            errors.append(
                f"lifecycle catalog: {package}: state must be inside the test home or /var/lib"
            )
        expected_command = matrix_packages.get(package, {}).get("smoke_path")
        if command != expected_command:
            errors.append(
                f"lifecycle catalog: {package}: command differs from matrix smoke_path: "
                f"{command!r} != {expected_command!r}"
            )
    if len(package_ids) != len(set(package_ids)):
        errors.append("lifecycle catalog: duplicate package IDs")
    if set(package_ids) != set(EXPECTED_PACKAGES):
        missing = sorted(set(EXPECTED_PACKAGES) - set(package_ids))
        extra = sorted(set(package_ids) - set(EXPECTED_PACKAGES))
        errors.append(
            f"lifecycle catalog: package IDs differ from repository packages; "
            f"missing={missing}, extra={extra}"
        )


def validate_autonomous_update_workflow(errors: list[str]) -> None:
    path = ROOT / ".github/workflows/check-updates.yml"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8")
    if not re.search(r'(?m)^    - cron: ["\']17 \* \* \* \*["\']$', text):
        errors.append(
            "autonomous update workflow: mutable sources must be checked hourly"
        )


def validate_repository_text(errors: list[str]) -> None:
    for path in ROOT.rglob("*"):
        if not path.is_file() or ".git" in path.parts:
            continue
        relative = path.relative_to(ROOT)
        if relative.parts[0] in {".cache", "external", ".venv"}:
            continue
        if path.suffix.lower() in {".png", ".ico", ".zip", ".gz"}:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue

        scans_validator_source = relative == Path(".github/tools/validate_repo.py")
        if not scans_validator_source and (
            "/home/cheviiot" in text or "/.codex/attachments/" in text
        ):
            errors.append(f"{relative}: personal path is forbidden")
        if not scans_validator_source and "chmod 777" in text:
            errors.append(f"{relative}: chmod 777 is forbidden")
        if not scans_validator_source and re.search(r"\brm\s+-rf\b", text):
            allowed_purge = relative in {
                Path("tailscale/tailscale-purge-data"),
            }
            if not allowed_purge or "--yes" not in text:
                errors.append(f"{relative}: unsafe rm -rf")
        for pattern in SECRET_PATTERNS:
            if pattern.search(text):
                errors.append(f"{relative}: possible secret detected")

        if text.startswith("#!") and not os.access(path, os.X_OK):
            errors.append(f"{relative}: script is not executable")


def main() -> int:
    errors: list[str] = []

    for required in sorted(REQUIRED_ROOT_FILES):
        if not (ROOT / required).is_file():
            errors.append(f"missing required file: {required}")

    package_dirs = tuple(
        sorted(path.name for path in ROOT.iterdir() if (path / "Staplerfile").is_file())
    )
    if package_dirs != EXPECTED_PACKAGES:
        errors.append(
            "package list mismatch: "
            f"expected {', '.join(EXPECTED_PACKAGES)}; got {', '.join(package_dirs)}"
        )

    matrix = load_support_matrix(errors)
    matrix_packages = {
        package.get("id"): package
        for package in matrix.get("packages", [])
        if isinstance(package, dict)
    }

    metadata: dict[str, dict[str, object]] = {}
    for package in package_dirs:
        metadata[package] = validate_package(
            package, errors, matrix_packages.get(package)
        )

    validate_unique_local_source_urls(metadata, errors)
    validate_readme(metadata, errors)
    validate_readme_hero(errors)
    validate_updater_package_list(errors)
    validate_lifecycle_catalog(matrix_packages, errors)
    validate_autonomous_update_workflow(errors)
    for path in sorted([
        *ROOT.glob("*.md"),
        *ROOT.glob(".github/docs/**/*.md"),
        *ROOT.glob("*/README.md"),
    ]):
        validate_links(path, errors)
    validate_repository_text(errors)

    if errors:
        print("Nivora validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(
        f"OK: validated G0 metadata, G1 hermeticity and G2 dependency policy "
        f"for {len(package_dirs)} Nivora packages"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
