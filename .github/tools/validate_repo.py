#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import os
import re
import shlex
import sys
import tomllib
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[2]

EXPECTED_PACKAGES = (
    "anidesk",
    "armbian-imager",
    "balena-etcher",
    "chatgpt",
    "claude",
    "distroshelf",
    "github-desktop",
    "happ",
    "parsec",
    "pineconemc",
    "subnetdesk",
    "tailscale",
    "telegram",
    "ventoy",
    "vesktop",
    "vintner",
    "yandex-music",
)

REQUIRED_ROOT_FILES = {
    Path("README.md"),
    Path("CHANGELOG.md"),
    Path("CONTRIBUTING.md"),
    Path("SECURITY.md"),
    Path("LICENSE"),
    Path("stapler-repo.toml"),
    Path(".github/assets/readme-hero.png"),
    Path(".github/support-matrix.toml"),
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
# ALT is the only supported distribution. Every other target was dropped
# together with its per-distro dependency fields.
EXPECTED_TARGETS = {
    "alt-p11",
    "alt-sisyphus",
}
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
EXPECTED_README_CATEGORIES = (
    "Интернет, сеть и VPN",
    "AI и разработка",
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
            "support matrix: target IDs differ from the approved ALT target set"
        )
    for target in targets:
        if not isinstance(target, dict):
            continue
        if target.get("distro") != "altlinux":
            errors.append(
                f"support matrix: {target.get('id')}: only ALT targets are supported"
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
    images = matrix.get("images", {})
    if set(images) != {"alt_p11", "alt_sisyphus"}:
        errors.append("support matrix: images must be exactly the two ALT branches")
    for name, image in images.items():
        if "@sha256:" not in image:
            errors.append(f"support matrix: image {name} is not digest-pinned")
    stapler = matrix.get("stapler", {})
    if stapler.get("stable_version") != "0.1.1":
        errors.append("support matrix: stable Stapler must remain v0.1.1")
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

    # ALT is the only target, so the dependency lists live in the base fields.
    compatible = array(text, "compatible_with")
    if compatible != ["altlinux"]:
        errors.append(
            f"G0 {package}: compatible_with must be ['altlinux'], got {compatible}"
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
        if array(text, f"{field}_altlinux") is not None:
            errors.append(
                f"G2 {package}: {field}_altlinux is redundant; {field} is the ALT "
                "list. Only the branch overrides may specialise it"
            )
        for branch_field in re.findall(
            rf"^({re.escape(field)}_altlinux_[a-z0-9_]+)=", text, re.MULTILINE
        ):
            branch = branch_field.rsplit("_", 1)[-1]
            if branch not in {"p11", "sisyphus"}:
                errors.append(
                    f"G2 {package}: {branch_field} targets an unknown ALT branch"
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


def validate_readme_text(
    text: str, metadata: dict[str, dict[str, object]], errors: list[str]
) -> None:
    count_match = re.search(
        r"<!--\s*package-count\s*-->\s*"
        r"<p[^>]*>\s*<strong>(\d+)\s+пакет",
        text,
    )
    if not count_match or int(count_match.group(1)) != len(metadata):
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

    # A shared table keeps every category on the same column grid on GitHub.
    if len(re.findall(r"<table\b", catalog)) != 1 or catalog.count("</table>") != 1:
        errors.append("README.md: catalog must use a single table for aligned columns")

    rows = re.findall(r"<tr[^>]*>(.*?)</tr>", catalog, re.DOTALL)
    headers = re.findall(r"<th\b[^>]*>([^<]+)</th>", rows[0]) if rows else []
    if headers != ["Приложение", "Версия", "Архитектуры", "Пакет"]:
        errors.append("README.md: catalog column headers are missing or out of order")

    # One package per row. Two packages sharing a row are stretched to the
    # taller one, so the shorter card ends up with dead space at the bottom.
    # Only the column headers and category dividers may contain no package.
    categories = []
    for row in rows[1:]:
        category = re.fullmatch(
            r'\s*<th colspan="4" align="left">([^<]+)</th>\s*', row
        )
        if category:
            categories.append(category.group(1))
            continue
        found = re.findall(r"package-card:([a-z0-9-]+)", row)
        if len(found) != 1:
            errors.append(
                "README.md: every catalogue row must hold exactly one package, "
                f"got {found or 'none'}"
            )

    if tuple(categories) != EXPECTED_README_CATEGORIES:
        errors.append(
            "README.md: catalog categories must be exactly: "
            + ", ".join(EXPECTED_README_CATEGORIES)
        )

    markers = list(
        re.finditer(
            r"<!--\s*package-card:([a-z0-9][a-z0-9-]*)\s*-->", catalog
        )
    )
    marker_ids = [match.group(1) for match in markers]
    expected_ids = set(metadata)
    unknown_ids = sorted(set(marker_ids) - expected_ids)
    if unknown_ids:
        errors.append(
            "README.md: unknown package cards: " + ", ".join(unknown_ids)
        )

    for package, values in metadata.items():
        occurrences = [
            index for index, marker in enumerate(markers) if marker.group(1) == package
        ]
        if len(occurrences) != 1:
            errors.append(f"README.md: expected one package card for {package}")
            continue
        marker_index = occurrences[0]
        block_start = markers[marker_index].end()
        block_end = (
            markers[marker_index + 1].start()
            if marker_index + 1 < len(markers)
            else len(catalog)
        )
        card = catalog[block_start:block_end]

        command = f"<code>nivora/{package}</code>"
        if card.count(command) != 1:
            errors.append(f"README.md: expected one install command for {package}")
        version = str(values["version"])
        if card.count(f"<code>{version}</code>") != 1:
            errors.append(f"README.md: version {version} is missing from {package} card")
        architectures = values.get("architectures", [])
        if isinstance(architectures, list):
            for architecture in architectures:
                if f"<code>{architecture}</code>" not in card:
                    errors.append(
                        f"README.md: architecture {architecture} is missing "
                        f"from {package} card"
                    )


def validate_readme(metadata: dict[str, dict[str, object]], errors: list[str]) -> None:
    path = ROOT / "README.md"
    validate_readme_text(path.read_text(encoding="utf-8"), metadata, errors)


def validate_readme_hero(errors: list[str]) -> None:
    path = ROOT / ".github/assets/readme-hero.png"
    if not path.is_file():
        return
    try:
        header = path.read_bytes()[:24]
    except OSError as error:
        errors.append(f"README hero: cannot read PNG: {error}")
        return
    png_signature = b"\x89PNG\r\n\x1a\n"
    if len(header) != 24 or header[:8] != png_signature or header[12:16] != b"IHDR":
        errors.append("README hero: asset must be a valid PNG")
        return
    width = int.from_bytes(header[16:20], "big")
    height = int.from_bytes(header[20:24], "big")
    if (width, height) != (2400, 800):
        errors.append("README hero: PNG dimensions must be exactly 2400x800")
    if path.stat().st_size > 1024 * 1024:
        errors.append("README hero: PNG must not exceed 1 MiB")


def validate_github_desktop_workflow(errors: list[str]) -> None:
    """The build workflow must never hard-code a package version.

    A literal version in this workflow used to be cross-checked against the
    recipe. That made the package impossible to update autonomously: the
    updater only ever patches its own package directory, and the publish gate
    accepts a single changed path, so a recipe bump could never carry the
    matching workflow edit and the static checks failed forever. The version
    now arrives exclusively through the required `version` input.
    """
    path = ROOT / ".github/workflows/github-desktop-linux.yml"
    if not path.is_file():
        return
    text = path.read_text(encoding="utf-8")
    if re.search(r"inputs\.version\s*\|\|", text):
        errors.append(
            "github-desktop workflow: inputs.version must not have a hard-coded "
            "fallback; it blocks autonomous updates"
        )
    if re.search(
        r"(?m)^      version:\n(?:^        [^\n]*\n)*?^        default:", text
    ):
        errors.append(
            "github-desktop workflow: the version input must not have a default; "
            "it blocks autonomous updates"
        )
    for match in re.finditer(r"(?m)^\s*(?:version|VERSION):\s*[\"']?(\d+\.\d+[^\s\"']*)", text):
        errors.append(
            "github-desktop workflow: hard-coded version literal "
            f"{match.group(1)}"
        )


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
    validate_github_desktop_workflow(errors)
    validate_updater_package_list(errors)
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
