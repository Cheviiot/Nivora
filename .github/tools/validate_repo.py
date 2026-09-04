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
    "balena-etcher",
    "chatgpt",
    "claude",
    "distroshelf",
    "github-desktop",
    "happ",
    "nivora-cli",
    "parsec",
    "pineconemc",
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
SUPPORTED_TIERS = {"verified", "partial", "experimental", "unsupported"}
EXPECTED_TARGETS = {
    "debian-13",
    "ubuntu-24.04",
    "ubuntu-26.04",
    "fedora-43",
    "fedora-44",
    "alt-p11",
    "alt-sisyphus",
    "arch-snapshot",
    "opensuse-leap-16.0",
    "alpine-3.23",
}


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
    expected_desktop: str,
    errors: list[str],
) -> None:
    sidecar = directory / f"{appstream_id}.metainfo.xml"
    if not sidecar.is_file():
        errors.append(f"G2 {package}: missing Stapler AppStream sidecar {sidecar.name}")
        return
    try:
        root = ET.parse(sidecar).getroot()
    except (ET.ParseError, OSError) as error:
        errors.append(f"G2 {package}: invalid AppStream sidecar: {error}")
        return

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
    if launchables != [Path(expected_desktop).name]:
        errors.append(
            f"G2 {package}: AppStream launchable differs from "
            f"{Path(expected_desktop).name}"
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


def support_by_target(package: dict[str, object]) -> dict[str, dict[str, object]]:
    result: dict[str, dict[str, object]] = {}
    for group in package.get("support", []):
        if not isinstance(group, dict):
            continue
        for target in group.get("targets", []):
            if isinstance(target, str):
                result[target] = group
    return result


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
            "support matrix: target IDs differ from the approved 10-target set"
        )

    packages = matrix.get("packages", [])
    package_ids = [item.get("id") for item in packages if isinstance(item, dict)]
    if len(package_ids) != len(set(package_ids)):
        errors.append("support matrix: duplicate package IDs")
    if set(package_ids) != set(EXPECTED_PACKAGES):
        errors.append("support matrix: package IDs differ from repository packages")

    logical_cells = 0
    scheduled_cells = 0
    unique_build_cells = 0
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
        if any(arch not in {"amd64", "arm64"} for arch in expanded):
            errors.append(f"support matrix: {package_id}: invalid architectures")

        coverage: dict[str, dict[str, object]] = {}
        for group in package.get("support", []):
            if not isinstance(group, dict):
                errors.append(f"support matrix: {package_id}: invalid support group")
                continue
            tier = group.get("tier")
            caveats = group.get("caveats")
            group_targets = group.get("targets")
            if tier not in SUPPORTED_TIERS:
                errors.append(f"support matrix: {package_id}: invalid tier {tier!r}")
            if not isinstance(caveats, list) or any(
                not isinstance(item, str) or not item for item in caveats
            ):
                errors.append(f"support matrix: {package_id}: invalid caveats")
            if tier != "verified" and not caveats:
                errors.append(
                    f"support matrix: {package_id}: {tier} needs a concrete caveat"
                )
            if not isinstance(group_targets, list):
                errors.append(f"support matrix: {package_id}: targets must be an array")
                continue
            for target in group_targets:
                if target in coverage:
                    errors.append(
                        f"support matrix: {package_id}: duplicate target {target}"
                    )
                coverage[target] = group

        if set(coverage) != EXPECTED_TARGETS:
            errors.append(
                f"support matrix: {package_id}: every target must occur exactly once"
            )
        for target, group in coverage.items():
            logical_cells += len(expanded)
            if group.get("tier") != "unsupported":
                scheduled_cells += len(expanded)
                unique_build_cells += 1 if architectures == ["all"] else len(expanded)
            if group.get("tier") == "verified":
                verified_cells += len(expanded)
                target = targets_by_id.get(target)
                if target is None:
                    continue
                if target.get("ci_mode") != "blocking-runtime":
                    errors.append(
                        f"support matrix: {package_id}: verified target "
                        f"{target.get('id')} is not a blocking runtime target"
                    )
                runners = target.get("native_runners", {})
                for architecture in expanded:
                    if not isinstance(runners, dict) or not runners.get(architecture):
                        errors.append(
                            f"support matrix: {package_id}: verified target "
                            f"{target.get('id')} lacks native {architecture} runner"
                        )

    expectations = matrix.get("expectations", {})
    actual = {
        "package_count": len(packages),
        "target_count": len(targets),
        "logical_runtime_cells": logical_cells,
        "declared_supported_runtime_cells": scheduled_cells,
        "declared_unique_build_cells": unique_build_cells,
        "blocking_ci_build_cells_full_common_change": len(packages),
        "blocking_ci_runtime_cells": verified_cells,
        "advisory_main_build_cells_full_common_change": len(packages),
    }
    for key, value in actual.items():
        if expectations.get(key) != value:
            errors.append(
                f"support matrix: expectations.{key}={expectations.get(key)!r}, "
                f"calculated {value}"
            )
    if verified_cells:
        workflow = ROOT / ".github/workflows/package-ci.yml"
        workflow_text = workflow.read_text(encoding="utf-8") if workflow.is_file() else ""
        for required in (
            ".github/tools/target_plan.py",
            ".github/tools/target_lifecycle.sh",
            "fromJSON(needs.plan.outputs.verified_targets)",
        ):
            if required not in workflow_text:
                errors.append(
                    f"support matrix: blocking target lifecycle workflow lacks {required}"
                )
    for name, image in matrix.get("images", {}).items():
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
    if flag(text, "auto_req") != 0 or flag(text, "auto_prov") != 0:
        errors.append(f"G2 {package}: base auto_req/auto_prov must both be 0")
    if scalar(text, "auto_reqprov_method") != "dirty":
        errors.append(f"G2 {package}: auto_reqprov_method must be dirty")
    for distro in ("altlinux", "fedora", "opensuse"):
        req = flag(text, f"auto_req_{distro}", default=0)
        prov = flag(text, f"auto_prov_{distro}", default=0)
        method = scalar(text, f"auto_reqprov_method_{distro}")
        if req not in {0, 1}:
            errors.append(f"G2 {package}: auto_req_{distro} must be 0 or 1")
        if prov != 0:
            errors.append(f"G2 {package}: auto_prov_{distro} must stay disabled")
        if method not in {None, "dirty"}:
            errors.append(
                f"G2 {package}: {distro} must not switch away from dirty finder"
            )
    for distro in ("debian", "ubuntu", "arch", "alpine"):
        if flag(text, f"auto_req_{distro}", default=0) != 0:
            errors.append(f"G2 {package}: auto_req_{distro} must stay disabled")
        if flag(text, f"auto_prov_{distro}", default=0) != 0:
            errors.append(f"G2 {package}: auto_prov_{distro} must stay disabled")

    matrix_architectures = (
        matrix_package.get("architectures") if matrix_package is not None else None
    )
    if matrix_architectures != architectures:
        errors.append(
            f"G0 {package}: recipe/matrix architectures differ: "
            f"{architectures} != {matrix_architectures}"
        )
    if matrix_package is not None:
        support = support_by_target(matrix_package)
        alpine_supported = (
            support.get("alpine-3.23", {}).get("tier") != "unsupported"
        )
        incompatibilities = array(text, "incompatible_with") or []
        if alpine_supported and "alpine" in incompatibilities:
            errors.append(
                f"G0 {package}: Alpine is supported by matrix but recipe rejects it"
            )
        if not alpine_supported and "alpine" not in incompatibilities:
            errors.append(
                f"G0 {package}: Alpine is unsupported but recipe does not reject it"
            )
        dependency_fields = {
            "debian-13": "deps_debian",
            "ubuntu-24.04": "deps_ubuntu",
            "ubuntu-26.04": "deps_ubuntu",
            "arch-snapshot": "deps_arch",
            "alpine-3.23": "deps_alpine",
        }
        for target, dependency_field in dependency_fields.items():
            if support.get(target, {}).get("tier") == "unsupported":
                continue
            dependencies = array(text, dependency_field)
            if not dependencies:
                errors.append(
                    f"G2 {package}: {dependency_field} must explicitly map {target}"
                )

    appstream_id = scalar(text, "appstream_app_id")
    has_appstream_payload = bool(
        re.search(r"/usr/share/(?:metainfo|appdata)/[^\s'\"]+\.(?:metainfo|appdata)\.xml", text)
    )
    if appstream_id:
        expected_desktop = f"/usr/share/applications/{appstream_id}"
        if not appstream_id.endswith(".desktop"):
            expected_desktop += ".desktop"
        if expected_desktop not in text:
            errors.append(
                f"G2 {package}: AppStream ID is not adjacent to {expected_desktop}"
            )
        if not has_appstream_payload:
            errors.append(f"G2 {package}: appstream_app_id lacks metadata payload")
        validate_appstream_sidecar(
            package, directory, appstream_id, expected_desktop, errors
        )
    elif has_appstream_payload:
        errors.append(f"G2 {package}: metadata payload needs appstream_app_id")

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


def validate_readme(metadata: dict[str, dict[str, object]], errors: list[str]) -> None:
    path = ROOT / "README.md"
    text = path.read_text(encoding="utf-8")
    count_match = re.search(r"<!--\s*package-count\s*-->\s*\*\*(\d+) пакет", text)
    if not count_match or int(count_match.group(1)) != len(EXPECTED_PACKAGES):
        errors.append("README.md: package counter is stale")
    if text.count("### ") != 6:
        errors.append("README.md: catalog must contain exactly six categories")

    for package, values in metadata.items():
        command = f"`stplr install nivora/{package}`"
        catalog_rows = [
            line for line in text.splitlines() if line.startswith("|") and command in line
        ]
        if len(catalog_rows) != 1:
            errors.append(f"README.md: expected one catalog command for {package}")
        version = str(values["version"])
        if f"`{version}`" not in text:
            errors.append(f"README.md: version {version} is missing for {package}")


def validate_github_desktop_workflow(
    metadata: dict[str, dict[str, object]], errors: list[str]
) -> None:
    path = ROOT / ".github/workflows/github-desktop-linux.yml"
    if not path.is_file() or "github-desktop" not in metadata:
        return
    text = path.read_text(encoding="utf-8")
    expected = str(metadata["github-desktop"]["version"])
    dispatch_default = re.search(
        r"(?m)^      version:\n"
        r"(?:^        [^\n]*\n)*?^        default: [\"']([^\"']+)[\"']",
        text,
    )
    if not dispatch_default or dispatch_default.group(1) != expected:
        errors.append(
            "github-desktop workflow: dispatch version does not match recipe "
            f"{expected}"
        )
    fallbacks = re.findall(r"inputs\.version\s*\|\|\s*'([^']+)'", text)
    if not fallbacks or any(version != expected for version in fallbacks):
        errors.append(
            "github-desktop workflow: every version fallback must match recipe "
            f"{expected}"
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
    validate_github_desktop_workflow(metadata, errors)
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
