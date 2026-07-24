#!/usr/bin/env python3
from __future__ import annotations

import re
import shlex
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
README = ROOT / "README.md"


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


def main() -> None:
    lines = README.read_text(encoding="utf-8").splitlines()
    package_dirs = sorted(
        path.parent.name for path in ROOT.glob("*/Staplerfile")
    )

    for package in package_dirs:
        command = f"stplr install nivora/{package}"
        version, architectures = package_metadata(package)
        matching_lines = [
            index
            for index, line in enumerate(lines)
            if line.startswith("|") and command in line
        ]
        if len(matching_lines) != 1:
            raise RuntimeError(
                f"{package}: expected one README catalog row, "
                f"got {len(matching_lines)}"
            )

        index = matching_lines[0]
        cells = lines[index].split("|")
        if len(cells) != 6:
            raise RuntimeError(f"{package}: malformed README catalog row")
        cells[2] = f" `{version}` "
        cells[3] = " " + ", ".join(
            f"`{architecture}`" for architecture in architectures
        ) + " "
        lines[index] = "|".join(cells)

    README.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
