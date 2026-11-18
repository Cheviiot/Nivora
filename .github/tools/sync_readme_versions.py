#!/usr/bin/env python3
from __future__ import annotations

import re
import shlex
import tomllib
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
README = ROOT / "README.md"
# Only the explicitly marked metadata paragraph belongs to the updater.
# Card layout, descriptions, icons and navigation remain hand-authored.
CARD_METADATA_RE = re.compile(
    r'(?P<leading>\s*)<p><sub>Версия\s+<code>[^<\r\n]+</code>\s*·\s*'
    r'(?:<code>(?:amd64|arm64|all)</code>\s*)+</sub></p>(?P<trailing>\s*)'
)


def showcase_packages(root: Path) -> list[str]:
    """Keep service packages maintained without placing them on the app shelf."""
    with (root / ".github/support-matrix.toml").open("rb") as stream:
        packages = tomllib.load(stream).get("packages", [])
    discovered = {path.parent.name for path in root.glob("*/Staplerfile")}
    declared: set[str] = set()
    visible: list[str] = []
    for package in packages:
        if not isinstance(package, dict) or not isinstance(package.get("id"), str):
            raise RuntimeError("support matrix has an invalid package entry")
        package_id = package["id"]
        if package_id in declared:
            raise RuntimeError(f"support matrix repeats {package_id}")
        declared.add(package_id)
        if not isinstance(package.get("showcase", True), bool):
            raise RuntimeError(f"{package_id}: showcase must be a boolean")
        if package.get("showcase", True):
            visible.append(package_id)
    if declared != discovered:
        raise RuntimeError("support matrix packages do not match the recipe catalogue")
    return sorted(visible)


def package_metadata(package: str) -> tuple[str, list[str]]:
    text = (ROOT / package / "Staplerfile").read_text(encoding="utf-8")
    version_match = re.search(
        r"^version=(?:'([^']+)'|\"([^\"]+)\"|([^#\s]+))",
        text,
        re.MULTILINE,
    )
    if not version_match:
        raise RuntimeError(f"{package}: version is missing")
    version = next(
        value for value in version_match.groups() if value is not None
    )

    architectures_match = re.search(
        r"^architectures=\((.*?)\)", text, re.MULTILINE | re.DOTALL
    )
    if not architectures_match:
        raise RuntimeError(f"{package}: architectures are missing")
    architectures = shlex.split(architectures_match.group(1))
    if not architectures:
        raise RuntimeError(f"{package}: architectures are empty")

    return version, architectures


def sync_catalog(
    text: str,
    metadata: dict[str, tuple[str, list[str]]],
) -> str:
    start_marker = "<!-- catalog:start -->"
    end_marker = "<!-- catalog:end -->"
    if text.count(start_marker) != 1 or text.count(end_marker) != 1:
        raise RuntimeError("README catalogue boundaries must occur exactly once")
    catalog_start = text.index(start_marker) + len(start_marker)
    catalog_end = text.index(end_marker)
    if catalog_start >= catalog_end:
        raise RuntimeError("README catalogue boundaries are out of order")
    card_ids = re.findall(r"<!-- package-card:([a-z0-9][a-z0-9-]*) -->", text)
    if sorted(card_ids) != sorted(metadata):
        raise RuntimeError("README package cards do not match the recipe catalogue")
    for prefix in ("", "/"):
        field_ids = re.findall(
            rf"<!-- {prefix}package-meta:([a-z0-9][a-z0-9-]*) -->", text
        )
        if sorted(field_ids) != sorted(metadata):
            raise RuntimeError("README metadata blocks do not match the recipe catalogue")

    for package, (version, architectures) in sorted(metadata.items()):
        marker = f"<!-- package-card:{package} -->"
        metadata_marker = f"<!-- package-meta:{package} -->"
        metadata_end_marker = f"<!-- /package-meta:{package} -->"
        for boundary in (marker, metadata_marker, metadata_end_marker):
            if text.count(boundary) != 1:
                raise RuntimeError(f"{package}: expected one README marker {boundary}")
        marker_start = text.index(marker)
        metadata_start = text.index(metadata_marker)
        metadata_end = text.index(metadata_end_marker)
        catalog_end = text.index(end_marker)
        next_marker = text.find("<!-- package-card:", marker_start + len(marker))
        card_end = min(next_marker, catalog_end) if next_marker != -1 else catalog_end
        if not (
            catalog_start <= marker_start < metadata_start < metadata_end
            and metadata_end + len(metadata_end_marker) <= card_end
        ):
            raise RuntimeError(f"{package}: metadata is outside its card")

        content_start = metadata_start + len(metadata_marker)
        match = CARD_METADATA_RE.fullmatch(text[content_start:metadata_end])
        if not match:
            raise RuntimeError(
                f"{package}: expected one version/architecture metadata paragraph"
            )
        if not version or any(character in version for character in "\r\n"):
            raise RuntimeError(f"{package}: invalid recipe version")
        if (
            not architectures
            or len(architectures) != len(set(architectures))
            or any(architecture not in {"amd64", "arm64", "all"} for architecture in architectures)
            or ("all" in architectures and len(architectures) != 1)
        ):
            raise RuntimeError(f"{package}: invalid recipe architectures")
        replacement = (
            match.group("leading")
            + f"<p><sub>Версия <code>{escape(version)}</code> · "
            + " ".join(
                f"<code>{architecture}</code>"
                for architecture in architectures
            )
            + "</sub></p>"
            + match.group("trailing")
        )
        text = text[:content_start] + replacement + text[metadata_end:]

    return text


def main() -> None:
    package_dirs = showcase_packages(ROOT)
    metadata = {package: package_metadata(package) for package in package_dirs}
    text = sync_catalog(README.read_text(encoding="utf-8"), metadata)
    README.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
