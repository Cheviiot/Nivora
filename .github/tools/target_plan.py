#!/usr/bin/env python3
"""Render blocking native lifecycle cells from the support matrix."""

from __future__ import annotations

import argparse
import json
import tomllib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MATRIX_PATH = ROOT / ".github/support-matrix.toml"


def expanded_architectures(architectures: list[str]) -> list[str]:
    return ["amd64", "arm64"] if architectures == ["all"] else architectures


def verified_cells(matrix: dict[str, object]) -> list[dict[str, str]]:
    targets = {target["id"]: target for target in matrix["targets"]}
    cells: list[dict[str, str]] = []
    for package in matrix["packages"]:
        for support in package["support"]:
            if support["tier"] != "verified":
                continue
            for target_id in support["targets"]:
                target = targets[target_id]
                runners = target.get("native_runners", {})
                for architecture in expanded_architectures(package["architectures"]):
                    runner = runners.get(architecture)
                    if not runner:
                        raise ValueError(
                            f"verified cell {package['id']}@{target_id}/{architecture} "
                            "has no native runner"
                        )
                    cells.append(
                        {
                            "package": package["id"],
                            "target": target_id,
                            "architecture": architecture,
                            "runner": runner,
                        }
                    )
    return sorted(
        cells,
        key=lambda cell: (cell["target"], cell["package"], cell["architecture"]),
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()

    with MATRIX_PATH.open("rb") as stream:
        matrix = tomllib.load(stream)
    cells = verified_cells(matrix)
    payload = json.dumps(cells, separators=(",", ":"))
    print(payload)
    if args.github_output:
        with args.github_output.open("a", encoding="utf-8") as stream:
            stream.write(f"targets={payload}\n")
            stream.write(f"count={len(cells)}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
