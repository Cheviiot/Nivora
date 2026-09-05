#!/usr/bin/env python3
from __future__ import annotations

import re
import shlex
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
README = ROOT / "README.md"
CARD_METADATA_RE = re.compile(
    r"<code>[^<\n]+</code>\s*·\s*"
    r"(?:<code>(?:amd64|arm64|all)</code>\s*)+<br>"
)


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
    for package, (version, architectures) in sorted(metadata.items()):
        marker = f"<!-- package-card:{package} -->"
        command = f"<code>stplr install nivora/{package}</code>"
        if text.count(marker) != 1:
            raise RuntimeError(
                f"{package}: expected one README package marker, "
                f"got {text.count(marker)}"
            )
        if text.count(command) != 1:
            raise RuntimeError(
                f"{package}: expected one README install command, "
                f"got {text.count(command)}"
            )

        marker_start = text.index(marker)
        command_start = text.index(command)
        if command_start < marker_start:
            raise RuntimeError(f"{package}: install command precedes package marker")
        next_marker = text.find("<!-- package-card:", marker_start + len(marker))
        if next_marker != -1 and command_start > next_marker:
            raise RuntimeError(f"{package}: install command is outside its card")

        card_prefix = text[marker_start:command_start]
        matches = list(CARD_METADATA_RE.finditer(card_prefix))
        if len(matches) != 1:
            raise RuntimeError(
                f"{package}: expected one README card metadata line, "
                f"got {len(matches)}"
            )
        match = matches[0]
        replacement = (
            f"<code>{version}</code> · "
            + " ".join(
                f"<code>{architecture}</code>"
                for architecture in architectures
            )
            + "<br>"
        )
        absolute_start = marker_start + match.start()
        absolute_end = marker_start + match.end()
        text = text[:absolute_start] + replacement + text[absolute_end:]

    return text


def main() -> None:
    package_dirs = sorted(path.parent.name for path in ROOT.glob("*/Staplerfile"))
    metadata = {package: package_metadata(package) for package in package_dirs}
    text = sync_catalog(README.read_text(encoding="utf-8"), metadata)
    README.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
