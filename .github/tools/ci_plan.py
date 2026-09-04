#!/usr/bin/env python3
"""Build a deterministic changed-package plan for GitHub Actions."""

from __future__ import annotations

import argparse
import json
import subprocess
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MATRIX_PATH = ROOT / ".github/support-matrix.toml"
COMMON_PREFIXES = (".github/",)
COMMON_FILES = {"stapler-repo.toml"}


def package_ids() -> list[str]:
    with MATRIX_PATH.open("rb") as stream:
        matrix = tomllib.load(stream)
    return sorted(package["id"] for package in matrix["packages"])


def classify_paths(paths: list[str], packages: list[str]) -> tuple[list[str], bool]:
    normalized = [path.removeprefix("./") for path in paths]
    full = any(
        path in COMMON_FILES or path.startswith(COMMON_PREFIXES)
        for path in normalized
    )
    if full:
        return packages, True
    selected = sorted(
        package
        for package in packages
        if any(path == package or path.startswith(f"{package}/") for path in normalized)
    )
    return selected, False


def changed_paths(base: str, head: str) -> list[str]:
    if not base or set(base) == {"0"}:
        return [".github/support-matrix.toml"]
    result = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=ACMRD", base, head, "--"],
        cwd=ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        # Force the conservative full plan when a force-push, shallow clone,
        # or unreachable event SHA makes the requested range unavailable.
        return [".github/support-matrix.toml"]
    return [line for line in result.stdout.splitlines() if line]


def parse_requested(value: str, packages: list[str]) -> tuple[list[str], bool]:
    if value.strip() == "all":
        return packages, True
    requested = sorted(set(value.split()))
    unknown = sorted(set(requested) - set(packages))
    if unknown:
        raise ValueError(f"unknown package(s): {', '.join(unknown)}")
    return requested, False


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", default="")
    parser.add_argument("--head", default="HEAD")
    parser.add_argument("--packages", default="")
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()

    packages = package_ids()
    try:
        if args.packages:
            selected, full = parse_requested(args.packages, packages)
            paths: list[str] = []
        else:
            paths = changed_paths(args.base, args.head)
            selected, full = classify_paths(paths, packages)
    except ValueError as error:
        parser.error(str(error))

    payload = {
        "packages": selected,
        "has_packages": bool(selected),
        "full": full,
        "changed_paths": paths,
    }
    print(json.dumps(payload, separators=(",", ":")))
    if args.github_output:
        with args.github_output.open("a", encoding="utf-8") as stream:
            stream.write(f"packages={json.dumps(selected, separators=(',', ':'))}\n")
            stream.write(f"has_packages={str(bool(selected)).lower()}\n")
            stream.write(f"full={str(full).lower()}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
