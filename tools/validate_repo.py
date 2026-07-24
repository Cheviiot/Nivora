#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import os
import re
import shlex
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

ROOT = Path(__file__).resolve().parents[1]

EXPECTED_PACKAGES = (
    "adwyra",
    "anidesk",
    "balena-etcher",
    "chatbox",
    "clash-verge-rev",
    "claude",
    "claude-alt",
    "codex",
    "fisher",
    "github-desktop",
    "happ",
    "msvc-go-wine",
    "netbird",
    "nivora-cli",
    "opencode",
    "parsec",
    "pineconemc",
    "tailscale",
    "ventoy",
    "vual",
    "yandex-browser-stable",
)

REQUIRED_ROOT_FILES = {
    Path("README.md"),
    Path("CHANGELOG.md"),
    Path("CONTRIBUTING.md"),
    Path("SECURITY.md"),
    Path("LICENSE"),
    Path("stapler-repo.toml"),
    Path("docs/maintenance.md"),
    Path("docs/security-model.md"),
    Path("docs/packages/claude.md"),
    Path("docs/packages/claude-alt.md"),
    Path("docs/packages/codex.md"),
    Path("docs/packages/github-desktop.md"),
    Path("docs/packages/opencode.md"),
    Path("docs/packages/nivora-cli.md"),
    Path("docs/packages/ventoy.md"),
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


def markdown_targets(text: str) -> set[str]:
    return set(MARKDOWN_LINK_RE.findall(text)) | set(HTML_LINK_RE.findall(text))


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


def validate_package(package: str, errors: list[str]) -> dict[str, object]:
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

    if name != package:
        errors.append(f"{package}: directory and name differ: {name!r}")
    if not version:
        errors.append(f"{package}: version is missing")
    if not release or not release.isdigit() or int(release) < 1:
        errors.append(f"{package}: release must be a positive integer")
    if not architectures:
        errors.append(f"{package}: architectures are missing")
    elif any(item not in {"amd64", "arm64", "all"} for item in architectures):
        errors.append(f"{package}: unsupported architecture value: {architectures}")

    if provides != [] or conflicts != []:
        errors.append(f"{package}: provides/conflicts must not contain binary aliases")
    expected_replaces = [package]
    if package == "claude":
        expected_replaces.append("claude-desktop")
    if replaces != expected_replaces:
        errors.append(
            f"{package}: replaces must be {expected_replaces}, got {replaces}"
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
    }


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

        scans_validator_source = relative == Path("tools/validate_repo.py")
        if not scans_validator_source and (
            "/home/cheviiot" in text or "/.codex/attachments/" in text
        ):
            errors.append(f"{relative}: personal path is forbidden")
        if not scans_validator_source and "chmod 777" in text:
            errors.append(f"{relative}: chmod 777 is forbidden")
        if not scans_validator_source and re.search(r"\brm\s+-rf\b", text):
            allowed_purge = relative in {
                Path("tailscale/tailscale-purge-data"),
                Path("netbird/netbird-purge-data"),
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

    metadata: dict[str, dict[str, object]] = {}
    for package in package_dirs:
        metadata[package] = validate_package(package, errors)

    validate_readme(metadata, errors)
    for path in sorted([*ROOT.glob("*.md"), *ROOT.glob("docs/**/*.md")]):
        validate_links(path, errors)
    validate_repository_text(errors)

    if errors:
        print("Nivora validation failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"OK: validated {len(package_dirs)} Nivora packages")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
